import Foundation
import AuthenticationServices
import CryptoKit
import Observation
import UIKit

struct GmailStatus: Decodable {
 let connected: Bool
 let email: String?
 let status: String
 let lastSyncAt: Double?
 let error: String?
}
enum GmailCallback {
 static func code(from url: URL, expectedState: String) throws -> String {
  guard url.scheme == "sumora", url.host == "gmail", url.path.isEmpty,
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
        items.filter({$0.name == "state"}).count == 1,
        items.first(where: {$0.name == "state"})?.value == expectedState,
        !items.contains(where: {$0.name == "error"}),
        items.filter({$0.name == "code"}).count == 1,
        let code = items.first(where: {$0.name == "code"})?.value,
        code.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
   throw ZerodhaError.message("Gmail login couldn't be verified. Connect again.")
  }
  return code
 }
}

@MainActor @Observable
final class GmailConnection: NSObject, ASWebAuthenticationPresentationContextProviding {
 private(set) var status: GmailStatus?
 private(set) var isBusy = false
 var errorMessage: String?
 @ObservationIgnored private var address = ""
 @ObservationIgnored private var token: String?
 @ObservationIgnored private var generation = UUID()
 @ObservationIgnored private var authentication: ASWebAuthenticationSession?

 func configure(address: String, token: String?) {
  guard self.address != address || self.token != token else { return }
  generation = UUID(); authentication?.cancel(); authentication = nil
  self.address = address; self.token = token; status = nil; errorMessage = nil; isBusy = false
 }
 func refresh() async {
  guard token != nil, !isBusy else { return }
  isBusy = true; let current = generation
  defer { if generation == current { isBusy = false } }
  do {
   let value: GmailStatus = try await send("connection", method: "GET")
   guard generation == current else { return }
   status = value; errorMessage = nil
  } catch { if generation == current { errorMessage = error.localizedDescription } }
 }
 func connect() async {
  guard token != nil, !isBusy else { return }
  isBusy = true; errorMessage = nil; let current = generation
  defer { if generation == current { isBusy = false; authentication = nil } }
  do {
   let verifier = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
   let challenge = SHA256.hash(data: Data(verifier.utf8)).map { String(format: "%02x", $0) }.joined()
   let start: Start = try await send("start", body: ["challenge": challenge])
   guard generation == current else { return }
   guard let url = URL(string: start.loginURL), url.scheme == "https", url.host == "accounts.google.com" else {
    throw ZerodhaError.message("The server returned an invalid Google login address.")
   }
   let callback: URL = try await withCheckedThrowingContinuation { continuation in
    let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: "sumora") { url, error in
     if let url { continuation.resume(returning: url) }
     else { continuation.resume(throwing: error ?? ZerodhaError.message("Gmail login was cancelled.")) }
    }
    auth.presentationContextProvider = self
    authentication = auth
    if !auth.start() { continuation.resume(throwing: ZerodhaError.message("The login window couldn't open.")) }
   }
   guard generation == current else { return }
   let code = try GmailCallback.code(from: callback, expectedState: start.state)
   let claim: Claim = try await send("claim", body: ["code": code, "verifier": verifier])
   guard generation == current else { return }
   status = GmailStatus(connected: claim.connected, email: claim.email, status: "connected", lastSyncAt: nil, error: nil)
  } catch {
   if generation == current && (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin { errorMessage = error.localizedDescription }
  }
 }
 func disconnect() async {
  guard token != nil, !isBusy else { return }
  isBusy = true; let current = generation
  defer { if generation == current { isBusy = false } }
  do {
   let _: Disconnected = try await send("connection", method: "DELETE")
   guard generation == current else { return }
   status = nil; errorMessage = nil
  } catch { if generation == current { errorMessage = error.localizedDescription } }
 }
 func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
  UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
 }
 private func send<T: Decodable>(_ path: String, method: String = "POST", body: [String: String]? = nil) async throws -> T {
  guard let token, let base = APIConfiguration.baseURL(address) else { throw ZerodhaError.message("Connect Zerodha first to link Gmail.") }
  var request = URLRequest(url: base.appendingPathComponent("v1/gmail/\(path)"))
  request.httpMethod = method; request.timeoutInterval = 30
  request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  if let body { request.httpBody = try JSONEncoder().encode(body) }
  let (data, response) = try await URLSession.shared.data(for: request)
  guard let http = response as? HTTPURLResponse else { throw PortfolioAPIError.invalidSnapshot }
  guard (200..<300).contains(http.statusCode) else {
   throw ZerodhaError.message((try? JSONDecoder().decode(APIErrorResponse.self, from: data).error.message) ?? "Gmail request failed.")
  }
  return try JSONDecoder().decode(T.self, from: data)
 }
 private struct Start: Decodable { let state: String; let loginURL: String }
 private struct Claim: Decodable { let connected: Bool; let email: String }
 private struct Disconnected: Decodable { let disconnected: Bool }
}
