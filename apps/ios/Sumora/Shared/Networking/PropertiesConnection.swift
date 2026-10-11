import Foundation
import Observation

struct PropertyEntry: Codable, Identifiable, Sendable {
 let id: String
 let name: String
 let estimatedValue: DecimalValue
 let valuationDate: String
 let purchaseCost: DecimalValue?
 let updatedAt: Double
 var classification: String? = nil
 var location: String? = nil
}

@MainActor @Observable
final class PropertiesConnection {
 private(set) var properties: [PropertyEntry] = []
 private(set) var isBusy = false
 var errorMessage: String?
 @ObservationIgnored private var address = ""
 @ObservationIgnored private var token: String?
 @ObservationIgnored private var generation = UUID()
 @ObservationIgnored private let session: URLSession
 init(session: URLSession = .shared) { self.session = session }
 func configure(address: String, token: String?) {
  guard self.address != address || self.token != token else { return }
  generation = UUID(); self.address = address; self.token = token
  properties = []; errorMessage = nil; isBusy = false
 }
 func refresh() async {
  guard token != nil, !isBusy else { return }
  isBusy = true; let current = generation
  defer { if generation == current { isBusy = false } }
  do {
   let result: ListResponse = try await send("", method:"GET")
   guard generation == current else { return }
   properties = result.properties; errorMessage = nil
  } catch { if generation == current { errorMessage = error.localizedDescription } }
 }
 func save(id: String, name: String, value: String, date: String, cost: String, classification: String = "", location: String = "") async -> Bool {
  guard token != nil, !isBusy else { return false }
  isBusy = true; let current = generation
  defer { if generation == current { isBusy = false } }
  do {
   let result: SaveResponse = try await send(id,method:"PUT",body:["name":name,"estimatedValue":value,"valuationDate":date,"purchaseCost":cost,"classification":classification,"location":location])
   guard generation == current else { return false }
   properties.removeAll { $0.id == id }; properties.insert(result.property,at:0); errorMessage = nil; return true
  } catch { if generation == current { errorMessage = error.localizedDescription }; return false }
 }
 func remove(id: String) async -> Bool {
  guard token != nil, !isBusy else { return false }
  isBusy = true; let current = generation
  defer { if generation == current { isBusy = false } }
  do {
   let _: RemoveResponse = try await send(id,method:"DELETE")
   guard generation == current else { return false }
   properties.removeAll { $0.id == id }; errorMessage = nil; return true
  } catch { if generation == current { errorMessage = error.localizedDescription }; return false }
 }
 private func send<T:Decodable>(_ path:String,method:String,body:[String:String]? = nil) async throws -> T {
  guard let token,let base=APIConfiguration.baseURL(address) else { throw ZerodhaError.message("Sign in to manage real estate.") }
  var request=URLRequest(url:base.appendingPathComponent(path.isEmpty ? "v1/properties" : "v1/properties/"+path));request.httpMethod=method;request.timeoutInterval=30
  request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Content-Type")
  if let body { request.httpBody=try JSONEncoder().encode(body) }
  let (data,response)=try await session.data(for:request)
  guard let http=response as? HTTPURLResponse else { throw PortfolioAPIError.invalidSnapshot }
  checkAppSession(http, data: data, token: token)
  guard (200..<300).contains(http.statusCode) else { throw ZerodhaError.message((try? JSONDecoder().decode(APIErrorResponse.self,from:data).error.message) ?? "Property request failed. Previous data is retained.") }
  return try JSONDecoder().decode(T.self,from:data)
 }
 private struct ListResponse:Decodable { let properties:[PropertyEntry] }
 private struct SaveResponse:Decodable { let property:PropertyEntry }
 private struct RemoveResponse:Decodable { let removed:Bool }
}
