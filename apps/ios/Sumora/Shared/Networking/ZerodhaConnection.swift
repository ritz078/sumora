import Foundation
import AuthenticationServices
import CryptoKit
import Observation
import Security
import UIKit

enum ZerodhaCallback {
    static func code(from url: URL, expectedState: String) throws -> String {
        guard url.scheme == "sumora", url.host == "zerodha",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.first(where: { $0.name == "state" })?.value == expectedState else {
            throw ZerodhaError.message("The login response couldn't be verified. Connect again.")
        }
        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            throw ZerodhaError.message(error == "ACCOUNT_NOT_ALLOWED" ? "Sign in with the Zerodha account configured for this Sumora app." : "Zerodha login didn't complete. Connect again.")
        }
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              code.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw ZerodhaError.message("Zerodha login didn't complete. Connect again.")
        }
        return code
    }
}

enum ZerodhaError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { message } else { nil } }
}

enum SessionKeychain {
    private static func query(_ address: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.ritz078.sumora.sessions",
         kSecAttrAccount as String: address]
    }
    static func read(_ address: String) -> String? {
        var query = query(address)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ token: String, address: String) throws {
        var query = query(address)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw ZerodhaError.message("The app couldn't securely save your session. Connect again.")
        }
    }
    static func remove(_ address: String) { SecItemDelete(query(address) as CFDictionary) }
}

@MainActor @Observable
final class ZerodhaConnection: NSObject, ASWebAuthenticationPresentationContextProviding {
    private(set) var sessionToken: String?
    private(set) var isConnecting = false
    var errorMessage: String?
    @ObservationIgnored private var authentication: ASWebAuthenticationSession?
    private(set) var address: String
    @ObservationIgnored private let restoreSession: Bool

    init(address: String, restoreSession: Bool = true) {
        self.address = address
        self.restoreSession = restoreSession
        sessionToken = restoreSession ? SessionKeychain.read(address) : nil
        super.init()
    }

    func configure(address: String) {
        guard self.address != address else { return }
        self.address = address
        sessionToken = restoreSession ? SessionKeychain.read(address) : nil
    }

    func connect() async -> Bool {
        guard !isConnecting else { return false }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false; authentication = nil }
        do {
            let verifier = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let challenge = SHA256.hash(data: Data(verifier.utf8)).map { String(format: "%02x", $0) }.joined()
            let start: StartResponse = try await send("start", body: ["challenge": challenge])
            guard let url = URL(string: start.loginURL), url.scheme == "https", url.host == "kite.zerodha.com" else {
                throw ZerodhaError.message("The server returned an invalid Zerodha login address.")
            }
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: "sumora") { url, error in
                    if let url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: error ?? ZerodhaError.message("Login was cancelled.")) }
                }
                auth.presentationContextProvider = self
                auth.prefersEphemeralWebBrowserSession = true
                authentication = auth
                if !auth.start() { continuation.resume(throwing: ZerodhaError.message("The login window couldn't open.")) }
            }
            let code = try ZerodhaCallback.code(from: callback, expectedState: start.state)
            let claim: ClaimResponse = try await send("claim", body: ["code": code, "verifier": verifier])
            guard claim.sessionToken.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw PortfolioAPIError.invalidSnapshot }
            try SessionKeychain.write(claim.sessionToken, address: address)
            sessionToken = claim.sessionToken
            return true
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin { errorMessage = error.localizedDescription }
            return false
        }
    }

    func disconnect() async -> Bool {
        guard let sessionToken else { return true }
        do {
            let _: DisconnectResponse = try await send("connection", method: "DELETE", token: sessionToken)
            SessionKeychain.remove(address)
            self.sessionToken = nil
            errorMessage = nil
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func send<T: Decodable>(_ path: String, method: String = "POST", body: [String: String]? = nil, token: String? = nil) async throws -> T {
        guard let base = APIConfiguration.baseURL(address) else { throw HTTPPortfolioError.configuration }
        var request = URLRequest(url: base.appendingPathComponent("v1/zerodha/\(path)"))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PortfolioAPIError.invalidSnapshot }
        guard (200..<300).contains(http.statusCode) else {
            throw ZerodhaError.message((try? JSONDecoder().decode(APIErrorResponse.self, from: data).error.message) ?? "Zerodha request failed (HTTP \(http.statusCode)).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private struct StartResponse: Decodable { let state: String; let loginURL: String }
    private struct ClaimResponse: Decodable { let sessionToken: String }
    private struct DisconnectResponse: Decodable { let disconnected: Bool }
}

struct APIErrorResponse: Decodable {
    let error: Details
    struct Details: Decodable { let code: String; let message: String }
}
