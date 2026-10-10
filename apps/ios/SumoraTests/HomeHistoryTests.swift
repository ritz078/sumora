import Foundation
import Testing
@testable import Sumora

@Suite(.serialized) @MainActor
struct HomeHistoryTests {
 @Test func instrumentHistoryUsesItsOwnCoverageAndNeverPortfolioTotals() async {
  let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HomeHistoryProtocol.self]
  let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
  let connection = HomeHistoryConnection(session: session, assetClass: .indianEquity)
  connection.configure(address: "https://example.com", token: "account")
  HomeHistoryProtocol.responses = [(200, #"{"from":"2026-10-01","firstRecordedDay":"2026-10-01","snapshots":[{"day":"2026-10-08","value":"9000","coverage":"partial","instruments":[{"assetClass":"indianEquity","value":"1200","coverage":"complete"}]},{"day":"2026-10-09","value":"9900","coverage":"complete","instruments":[{"assetClass":"indianEquity","value":"1300","coverage":"partial"}]},{"day":"2026-10-10","value":"9999","coverage":"complete"}]}"#)]
  await connection.refresh()
  #expect(connection.history.map { $0.value.value } == [1200])
 }
 @Test func usdHistoryUsesRecordedDollarsAndDoesNotConvertOlderRupeeSnapshots() async {
  let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HomeHistoryProtocol.self]
  let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
  let connection = HomeHistoryConnection(session: session, assetClass: .usEquity)
  connection.configure(address: "https://example.com", token: "account")
  HomeHistoryProtocol.responses = [(200, #"{"from":"2026-10-01","firstRecordedDay":"2026-10-01","snapshots":[{"day":"2026-10-08","coverage":"complete","instruments":[{"assetClass":"usEquity","value":"1200","coverage":"complete"}]},{"day":"2026-10-09","coverage":"complete","instruments":[{"assetClass":"usEquity","value":"1300","valueUSD":"12.125","coverage":"complete"}]}]}"#)]
  await connection.refresh()
  #expect(connection.history.map { $0.value.value } == [1200,1300])
  #expect(connection.usdHistory.map { $0.value.value } == [Decimal(string: "12.125")!])
  connection.configure(address: "https://example.com", token: "other")
  #expect(connection.usdHistory.isEmpty)
 }
 @Test func paginatesOlderSnapshotsAndRetainsHistoryOnFailureThenClearsForAnotherAccount() async {
  let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HomeHistoryProtocol.self]
  let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
  let connection = HomeHistoryConnection(session: session)
  connection.configure(address: "https://example.com", token: "first-account")
  HomeHistoryProtocol.requests = []
  HomeHistoryProtocol.responses = [
   (200, #"{"from":"2026-09-11","firstRecordedDay":"2026-08-01","snapshots":[{"day":"2026-10-10","value":"1200","coverage":"complete"},{"day":"2026-10-09","value":"900","coverage":"partial"}]}"#),
   (200, #"{"from":"2026-08-01","firstRecordedDay":"2026-08-01","snapshots":[{"day":"2026-08-01","value":"1000","coverage":"complete"}]}"#),
   (503, "{}")
  ]
  await connection.refresh()
  #expect(connection.history.map { $0.value.value } == [1000, 1200])
  #expect(HomeHistoryProtocol.requests.count == 2)
  #expect(HomeHistoryProtocol.requests[1].url?.query == "from=2026-08-01&to=2026-09-10")
  #expect(HomeHistoryProtocol.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer first-account" })
  await connection.refresh()
  #expect(connection.history.count == 2 && connection.errorMessage != nil)
  connection.configure(address: "https://example.com", token: "second-account")
  #expect(connection.history.isEmpty && connection.errorMessage == nil)
 }
}
private final class HomeHistoryProtocol: URLProtocol, @unchecked Sendable {
 nonisolated(unsafe) static var requests: [URLRequest] = []
 nonisolated(unsafe) static var responses: [(Int, String)] = []
 override class func canInit(with request: URLRequest) -> Bool { true }
 override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
 override func startLoading() {
  Self.requests.append(request)
  guard !Self.responses.isEmpty else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
  let response = Self.responses.removeFirst()
  client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: response.0, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
  client?.urlProtocol(self, didLoad: Data(response.1.utf8)); client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() {}
}
