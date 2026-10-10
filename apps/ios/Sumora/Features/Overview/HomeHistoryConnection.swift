import Foundation
import Observation

@MainActor @Observable
final class HomeHistoryConnection {
 private(set) var history: [HistoryPoint] = []
 private(set) var errorMessage: String?
 @ObservationIgnored private var address = ""
 @ObservationIgnored private var token: String?
 @ObservationIgnored private var generation = UUID()
 @ObservationIgnored private var isBusy = false
 @ObservationIgnored private let assetClass: AssetClass?
 @ObservationIgnored private let session: URLSession
 init(session: URLSession = .shared, assetClass: AssetClass? = nil) { self.session = session; self.assetClass = assetClass }
 func configure(address: String, token: String?) {
  guard self.address != address || self.token != token else { return }
  self.address = address; self.token = token; generation = UUID()
  history = []; errorMessage = nil; isBusy = false
 }
 func refresh() async {
  guard let token, let base = APIConfiguration.baseURL(address), !isBusy else { return }
  let current = generation
  isBusy = true
  defer { if generation == current { isBusy = false } }
  do {
   var page = try await fetch(base: base, token: token)
   var records = page.snapshots
   let earliest = page.firstRecordedDay
   // Once loaded, older daily records are immutable; refresh the recent window only.
   if history.isEmpty, let earliest {
    var pages = 0
    while page.from > earliest {
     try Task.checkCancellation()
     pages += 1
     guard pages < 100 else { throw PortfolioAPIError.invalidSnapshot }
     guard let start = dayDate(page.from) else { throw PortfolioAPIError.invalidSnapshot }
     let to = dayString(start.addingTimeInterval(-86400))
     let from = max(earliest, dayString(start.addingTimeInterval(-90 * 86400)))
     page = try await fetch(base: base, token: token, from: from, to: to)
     records += page.snapshots
    }
   }
   guard current == generation else { return }
   var merged = Dictionary(uniqueKeysWithValues: history.map { ($0.date, $0) })
   for record in records {
    guard let date = dayDate(record.day) else { throw PortfolioAPIError.invalidSnapshot }
    // Never connect partial valuations into a misleading net-worth curve.
    merged.removeValue(forKey: date)
    if let assetClass {
     if let instrument = record.instruments?.first(where: { $0.assetClass == assetClass }), instrument.coverage == .complete, let value = instrument.value {
      merged[date] = HistoryPoint(date: date, value: value)
     }
    } else if record.coverage == .complete, let value = record.value { merged[date] = HistoryPoint(date: date, value: value) }
   }
   history = merged.values.sorted { $0.date < $1.date }; errorMessage = nil
  } catch is CancellationError { }
  catch { if current == generation { errorMessage = "Saved history couldn’t refresh. Previous history is retained." } }
 }
 private func fetch(base: URL, token: String, from: String? = nil, to: String? = nil) async throws -> Page {
  var url = URLComponents(url: base.appendingPathComponent("v1/portfolio/history"), resolvingAgainstBaseURL: false)!
  if let from, let to { url.queryItems = [.init(name: "from", value: from), .init(name: "to", value: to)] }
  var request = URLRequest(url: url.url!); request.timeoutInterval = 20
  request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  let (data, response) = try await session.data(for: request)
  guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw PortfolioAPIError.invalidSnapshot }
  return try JSONDecoder().decode(Page.self, from: data)
 }
 private func dayDate(_ day: String) -> Date? { ISO8601DateFormatter().date(from: day + "T00:00:00+05:30") }
 private func dayString(_ date: Date) -> String {
  let f = DateFormatter(); f.timeZone = TimeZone(identifier: "Asia/Kolkata"); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f.string(from: date)
 }
 private struct Page: Decodable { let from: String; let firstRecordedDay: String?; let snapshots: [Record] }
 private struct Record: Decodable { let day: String; let value: DecimalValue?; let coverage: Coverage; let instruments: [Instrument]? }
 private struct Instrument: Decodable { let assetClass: AssetClass; let value: DecimalValue?; let coverage: Coverage }
}
