import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

enum AuthError: LocalizedError {
    case cancelled
    case notSignedIn
    case expired
    case invalidGrant
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Login cancelado."
        case .notSignedIn: return "Entre com a sua conta Google."
        case .expired, .invalidGrant: return "O acesso ao Google expirou. Entre de novo."
        case .failed(let message): return message
        }
    }
}

/// Google OAuth for an installed app: authorization code + PKCE through the system browser sheet.
/// Only the refresh token is persisted (Keychain); access tokens live in memory.
@MainActor
final class GoogleAuth: NSObject {
    private static let scope = "https://www.googleapis.com/auth/spreadsheets"
    private static let refreshKey = "refresh_token"

    private let config: AppConfig
    private let keychain = Keychain(service: "gimmy.google")
    private var accessToken: String?
    private var expiry = Date.distantPast
    private var refreshTask: Task<String, Error>?
    private var webSession: ASWebAuthenticationSession?

    init(config: AppConfig) {
        self.config = config
    }

    var hasSession: Bool { keychain.read(Self.refreshKey) != nil }

    func signIn() async throws {
        let verifier = Self.randomURLSafe(byteCount: 48)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafe(byteCount: 16)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        guard let url = components.url else { throw AuthError.failed("Endereço de login inválido.") }

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: config.redirectScheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: AuthError.failed(error?.localizedDescription ?? "O Google não respondeu."))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            if !session.start() {
                continuation.resume(throwing: AuthError.failed("Não consegui abrir o login do Google."))
            }
        }
        webSession = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = item("error") {
            throw error == "access_denied" ? AuthError.cancelled : AuthError.failed("O Google recusou o login (\(error)).")
        }
        guard item("state") == state, let code = item("code") else {
            throw AuthError.failed("Resposta inesperada do Google. Tente de novo.")
        }

        let token = try await tokenRequest([
            "code": code,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        guard let refresh = token.refreshToken else {
            throw AuthError.failed("O Google não devolveu acesso permanente. Remova o Gimmy em myaccount.google.com, Segurança, e entre de novo.")
        }
        keychain.write(Self.refreshKey, refresh)
        store(token)
    }

    func signOut() {
        keychain.delete(Self.refreshKey)
        accessToken = nil
        expiry = .distantPast
    }

    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let accessToken, Date() < expiry.addingTimeInterval(-60) { return accessToken }
        if let refreshTask { return try await refreshTask.value }
        guard let refresh = keychain.read(Self.refreshKey) else { throw AuthError.notSignedIn }

        let task = Task<String, Error> {
            do {
                let token = try await self.tokenRequest([
                    "refresh_token": refresh,
                    "client_id": self.config.clientID,
                    "grant_type": "refresh_token",
                ])
                self.store(token)
                return token.accessToken
            } catch AuthError.invalidGrant {
                self.signOut()
                throw AuthError.expired
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    // MARK: - Token endpoint

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Double?
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    private struct TokenError: Decodable {
        let error: String?
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    private func store(_ token: TokenResponse) {
        accessToken = token.accessToken
        expiry = Date().addingTimeInterval(token.expiresIn ?? 3600)
    }

    private func tokenRequest(_ form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SheetsError(kind: .network, message: "Sem conexão com o Google. Confira a internet e tente de novo.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let body = try? JSONDecoder().decode(TokenError.self, from: data)
            if body?.error == "invalid_grant" { throw AuthError.invalidGrant }
            throw AuthError.failed("O Google recusou o login: \(body?.errorDescription ?? body?.error ?? "erro \(status)").")
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AuthError.failed("Resposta inesperada do Google.")
        }
    }

    // MARK: - Helpers

    private static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let formAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? value
    }
}

extension GoogleAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
        }
    }
}
