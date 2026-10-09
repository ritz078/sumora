import Foundation
import Observation

struct HDFCStatus: Decodable {
 struct Balance: Decodable { let total: DecimalValue; let statement_date: String; let count: Int }
 let configured: Bool
 let gmailConnected: Bool
 let lastSyncAt: Double?
 let error: String?
 let balance: Balance?
}

@MainActor @Observable
final class HDFCConnection {
 private(set) var status: HDFCStatus?
 private(set) var isBusy = false
 private(set) var message: String?
 var errorMessage: String?
 @ObservationIgnored private var address = ""
 @ObservationIgnored private var token: String?
 @ObservationIgnored private var generation = UUID()
 @ObservationIgnored private let session: URLSession
 init(session: URLSession = .shared) { self.session = session }
 func configure(address: String, token: String?) {
  guard self.address != address || self.token != token else { return }
  generation = UUID(); self.address = address; self.token = token
  status = nil; errorMessage = nil; message = nil; isBusy = false
 }
 func refresh() async {
  guard token != nil, !isBusy else { return }
  isBusy = true; let current = generation
  defer { if generation == current { isBusy = false } }
  do {
   let value: HDFCStatus = try await send("status", method: "GET")
   guard generation == current else { return }
   status = value; errorMessage = nil
  } catch { if generation == current { errorMessage = error.localizedDescription } }
 }
 @discardableResult func save(password: String) async -> Bool {
  guard token != nil, !isBusy else { return false }
  isBusy = true; let current = generation
  defer { if generation == current { isBusy = false } }
  do {
   let _: Saved = try await send("password", method: "PUT", body: ["password": password])
   guard generation == current else { return false }
   let value: HDFCStatus = try await send("status", method: "GET")
   guard generation == current else { return false }
   status = value
   errorMessage = nil; message = "Decryption password saved securely. Tap Sync Gmail documents."
   return true
  } catch { if generation == current { errorMessage = error.localizedDescription }; return false }
 }
 func sync() async {
  guard token != nil, !isBusy else { return }
  isBusy = true; message = nil; let current = generation
  defer { if generation == current { isBusy = false } }
  do {
   let result: Sync = try await send("sync", method: "POST")
   guard generation == current else { return }
   let value: HDFCStatus = try await send("status", method: "GET")
   guard generation == current else { return }
   status = value; errorMessage = nil
   message = result.skipped == true ? "An HDFC sync is already running." : result.imported > 0 ? "Fixed deposit balances updated." : "No new HDFC monthly statement found."
  } catch {
   if generation == current {
    errorMessage = error.localizedDescription
    if let value: HDFCStatus = try? await send("status", method: "GET"), generation == current { status = value }
   }
  }
 }
 func removePassword() async {
  guard token != nil, !isBusy else { return }
  isBusy = true; let current = generation
  defer { if generation == current { isBusy = false } }
  do {
   let _: Removed = try await send("password", method: "DELETE")
   guard generation == current else { return }
   let value: HDFCStatus = try await send("status", method: "GET")
   guard generation == current else { return }
   status = value; errorMessage = nil; message = "Automatic imports stopped. Your recorded FD balances is retained."
  } catch { if generation == current { errorMessage = error.localizedDescription } }
 }
 private func send<T: Decodable>(_ path: String, method: String, body: [String: String]? = nil) async throws -> T {
  guard let token, let base = APIConfiguration.baseURL(address) else { throw ZerodhaError.message("Connect Zerodha first to sign in to Sumora.") }
  var request = URLRequest(url: base.appendingPathComponent("v1/hdfc/\(path)"))
  request.httpMethod = method; request.timeoutInterval = 60
  request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  if let body { request.httpBody = try JSONEncoder().encode(body) }
  let (data,response) = try await session.data(for: request)
  guard let http = response as? HTTPURLResponse else { throw PortfolioAPIError.invalidSnapshot }
  guard (200..<300).contains(http.statusCode) else {
   throw ZerodhaError.message((try? JSONDecoder().decode(APIErrorResponse.self,from:data).error.message) ?? "HDFC request failed.")
  }
  return try JSONDecoder().decode(T.self,from:data)
 }
 private struct Saved: Decodable { let saved: Bool }
 private struct Removed: Decodable { let removed: Bool }
 private struct Sync: Decodable { let imported: Int; let skipped: Bool? }
}
