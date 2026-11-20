import Foundation

/// A cell as returned with valueRenderOption=UNFORMATTED_VALUE.
enum Cell: Decodable, Equatable, Sendable {
    case text(String)
    case number(Double)
    case bool(Bool)
    case empty

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .empty }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = value.isEmpty ? .empty : .text(value) }
        else { self = .empty }
    }
}

/// A value written with valueInputOption=USER_ENTERED. An empty text clears the cell; `skip` leaves it as is.
enum OutCell: Encodable, Equatable, Sendable {
    case text(String)
    case number(Double)
    case skip

    static let blank = OutCell.text("")

    /// Free text that must stay text: "10-10-10" or "1/12" would otherwise become dates, "=x" a formula.
    static func literal(_ value: String) -> OutCell { value.isEmpty ? .blank : .text("'" + value) }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .skip: try container.encodeNil()
        }
    }
}

extension Array where Element == Cell {
    func at(_ index: Int) -> Cell { index < count ? self[index] : .empty }
}

struct SheetsError: LocalizedError {
    enum Kind { case network, server, rejected, auth }
    let kind: Kind
    let message: String

    var errorDescription: String? { message }
    /// The request may or may not have reached the sheet.
    var isUncertain: Bool { kind == .network || kind == .server }
}

/// Thin wrapper over the Google Sheets REST API v4.
@MainActor
final class SheetsClient {
    private let spreadsheetID: String
    private let auth: GoogleAuth
    private static let base = "https://sheets.googleapis.com/v4/spreadsheets/"
    private static let rangeAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!:")

    init(spreadsheetID: String, auth: GoogleAuth) {
        self.spreadsheetID = spreadsheetID
        self.auth = auth
    }

    func values(_ range: String) async throws -> [[Cell]] {
        struct ValueRange: Decodable { let values: [[Cell]]? }
        let data = try await send(
            method: "GET",
            path: "values/" + encode(range),
            query: [
                URLQueryItem(name: "valueRenderOption", value: "UNFORMATTED_VALUE"),
                URLQueryItem(name: "dateTimeRenderOption", value: "SERIAL_NUMBER"),
            ],
            body: nil,
            idempotent: true
        )
        do {
            return try JSONDecoder().decode(ValueRange.self, from: data).values ?? []
        } catch {
            throw SheetsError(kind: .rejected, message: "A planilha devolveu dados que não entendi.")
        }
    }

    func update(_ range: String, _ rows: [[OutCell]]) async throws {
        struct Body: Encodable { let range: String; let majorDimension = "ROWS"; let values: [[OutCell]] }
        _ = try await send(
            method: "PUT",
            path: "values/" + encode(range),
            query: [URLQueryItem(name: "valueInputOption", value: "USER_ENTERED")],
            body: try JSONEncoder().encode(Body(range: range, values: rows)),
            idempotent: false
        )
    }

    /// Inserts `count` rows right after 1-based row `after`, copying its formatting.
    func insertRows(sheetID: Int, after: Int, count: Int) async throws {
        let body: [String: Any] = [
            "requests": [[
                "insertDimension": [
                    "range": ["sheetId": sheetID, "dimension": "ROWS", "startIndex": after, "endIndex": after + count],
                    "inheritFromBefore": true,
                ],
            ]],
        ]
        _ = try await send(
            method: "POST",
            path: ":batchUpdate",
            query: [],
            body: try JSONSerialization.data(withJSONObject: body),
            idempotent: false
        )
    }

    /// Writes several ranges in one request.
    func update(_ ranges: [(range: String, rows: [[OutCell]])]) async throws {
        struct ValueRange: Encodable { let range: String; let majorDimension = "ROWS"; let values: [[OutCell]] }
        struct Body: Encodable { let valueInputOption = "USER_ENTERED"; let data: [ValueRange] }
        guard !ranges.isEmpty else { return }
        _ = try await send(
            method: "POST",
            path: "values:batchUpdate",
            query: [],
            body: try JSONEncoder().encode(Body(data: ranges.map { ValueRange(range: $0.range, values: $0.rows) })),
            idempotent: false
        )
    }

    /// Deletes 1-based row `row`.
    func deleteRow(sheetID: Int, row: Int) async throws {
        try await deleteRows(sheetID: sheetID, rows: [row])
    }

    /// Deletes several 1-based rows in one request, bottom first so the numbers stay valid.
    func deleteRows(sheetID: Int, rows: [Int]) async throws {
        let requests: [[String: Any]] = Set(rows).sorted(by: >).map { row in
            ["deleteDimension": ["range": ["sheetId": sheetID, "dimension": "ROWS", "startIndex": row - 1, "endIndex": row]]]
        }
        guard !requests.isEmpty else { return }
        _ = try await send(
            method: "POST",
            path: ":batchUpdate",
            query: [],
            body: try JSONSerialization.data(withJSONObject: ["requests": requests]),
            idempotent: false
        )
    }

    /// Tab titles to sheet ids.
    func sheetIDs() async throws -> [String: Int] {
        struct Spreadsheet: Decodable {
            struct Sheet: Decodable {
                struct Properties: Decodable { let sheetId: Int; let title: String }
                let properties: Properties
            }
            let sheets: [Sheet]
        }
        let data = try await send(
            method: "GET",
            path: "",
            query: [URLQueryItem(name: "fields", value: "sheets.properties(sheetId,title)")],
            body: nil,
            idempotent: true
        )
        guard let decoded = try? JSONDecoder().decode(Spreadsheet.self, from: data) else {
            throw SheetsError(kind: .rejected, message: "A planilha devolveu dados que não entendi.")
        }
        return Dictionary(decoded.sheets.map { ($0.properties.title, $0.properties.sheetId) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Transport

    private func encode(_ range: String) -> String {
        range.addingPercentEncoding(withAllowedCharacters: Self.rangeAllowed) ?? range
    }

    private func send(method: String, path: String, query: [URLQueryItem], body: Data?, idempotent: Bool) async throws -> Data {
        var attempt = 0
        var forceRefresh = false
        while true {
            attempt += 1
            let token: String
            do {
                token = try await auth.validAccessToken(forceRefresh: forceRefresh)
            } catch let error as AuthError {
                switch error {
                case .notSignedIn, .expired, .invalidGrant: throw SheetsError(kind: .auth, message: error.localizedDescription)
                default: throw error
                }
            }

            let separator = path.isEmpty || path.hasPrefix(":") ? "" : "/"
            var components = URLComponents(string: Self.base)!
            components.percentEncodedPath += spreadsheetID + separator + path
            if !query.isEmpty { components.queryItems = query }
            var request = URLRequest(url: components.url!)
            request.httpMethod = method
            request.timeoutInterval = 30
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            let data: Data, response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw SheetsError(kind: .network, message: "Sem conexão com a planilha. Confira a internet e tente de novo.")
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) { return data }

            if status == 401, attempt == 1 {
                forceRefresh = true
                continue
            }
            if (status == 429 || (status >= 500 && idempotent)), attempt == 1 {
                try? await Task.sleep(for: .milliseconds(Int.random(in: 700...1300)))
                continue
            }
            throw Self.error(status: status, data: data)
        }
    }

    private static func error(status: Int, data: Data) -> SheetsError {
        struct Envelope: Decodable { struct Detail: Decodable { let message: String? }; let error: Detail? }
        let detail = (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message
        switch status {
        case 401:
            return SheetsError(kind: .auth, message: "O acesso ao Google expirou. Entre de novo.")
        case 403:
            return SheetsError(kind: .rejected, message: "Esta conta Google não tem permissão de edição na planilha.")
        case 404:
            return SheetsError(kind: .rejected, message: "Não achei a planilha. Confira o SPREADSHEET_ID no Config/Secrets.xcconfig.")
        case 429:
            return SheetsError(kind: .rejected, message: "O Google pediu uma pausa. Espere alguns segundos e tente de novo.")
        case 500...:
            return SheetsError(kind: .server, message: "O Google Sheets não respondeu agora. Tente de novo em instantes.")
        default:
            return SheetsError(kind: .rejected, message: "A planilha recusou a operação: \(detail ?? "erro \(status)").")
        }
    }
}
