import Foundation

/// Values injected at build time from Config/Secrets.xcconfig (see README).
struct AppConfig {
    let clientIDPrefix: String
    let spreadsheetID: String

    /// Sheet id of the "Registro" tab, used when inserting rows.
    static let registroSheetID = 0

    var clientID: String { "\(clientIDPrefix).apps.googleusercontent.com" }
    var redirectScheme: String { "com.googleusercontent.apps.\(clientIDPrefix)" }
    var redirectURI: String { "\(redirectScheme):/oauth2redirect" }
    var spreadsheetURL: URL? { URL(string: "https://docs.google.com/spreadsheets/d/\(spreadsheetID)/edit") }

    var isComplete: Bool {
        !clientIDPrefix.isEmpty && !spreadsheetID.isEmpty
            && !clientIDPrefix.contains("$(") && !spreadsheetID.contains("$(")
    }

    static func load() -> AppConfig {
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ key: String) -> String {
            (info[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var prefix = value("GimmyGoogleClientIDPrefix")
        // Accept the full client ID too.
        if prefix.hasSuffix(".apps.googleusercontent.com") {
            prefix = String(prefix.dropLast(".apps.googleusercontent.com".count))
        }
        return AppConfig(clientIDPrefix: prefix, spreadsheetID: value("GimmySpreadsheetID"))
    }
}
