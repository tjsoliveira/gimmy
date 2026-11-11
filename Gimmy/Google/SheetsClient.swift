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

/// A value written with valueInputOption=USER_ENTERED. An empty text clears the cell.
enum OutCell: Encodable, Sendable {
    case text(String)
    case number(Double)

    static let blank = OutCell.text("")

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
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

            let separator = path.hasPrefix(":") ? "" : "/"
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
