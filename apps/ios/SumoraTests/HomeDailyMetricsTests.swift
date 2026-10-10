import Foundation
import Testing
@testable import Sumora

struct HomeDailyMetricsTests {
 @Test func dailyPerformanceUsesPriceChangesRatherThanAllocationPercentages() throws {
  let fixture=try MockPortfolioAPI.load(.complete)
  let encoder=JSONEncoder();encoder.dateEncodingStrategy = .iso8601
  var raw=try JSONSerialization.jsonObject(with:encoder.encode(fixture)) as! [String:Any]
  var holdings=raw["holdings"] as! [[String:Any]]
  for i in holdings.indices where holdings[i]["assetClass"] as? String == "indianEquity" { holdings[i]["dailyGain"]="100" }
  raw["holdings"]=holdings
  let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
  let snapshot=try decoder.decode(PortfolioSnapshot.self,from:JSONSerialization.data(withJSONObject:raw))
  let metric=HomeDailyMetrics(snapshot:snapshot,asset:.indianEquity)
  #expect(metric.gain?.value == 200)
  #expect(metric.percent?.value != snapshot.allocation.first(where:{$0.assetClass == .indianEquity})?.percent.value)
  #expect(HomeDailyMetrics(snapshot:snapshot,asset:.usEquity).gain == nil)
  let oneMissing = holdings.firstIndex { $0["assetClass"] as? String == "indianEquity" }!
  holdings[oneMissing].removeValue(forKey: "dailyGain")
  raw["holdings"] = holdings
  let incomplete = try decoder.decode(PortfolioSnapshot.self, from: JSONSerialization.data(withJSONObject: raw))
  #expect(HomeDailyMetrics(snapshot: incomplete, asset: .indianEquity).gain == nil)
 }
 @Test func aMissingDailyPriceNeverBecomesZeroOrAPartialReturn() throws {
  let snapshot=try MockPortfolioAPI.load(.complete)
  #expect(HomeDailyMetrics(snapshot:snapshot,asset:.indianEquity).gain == nil)
  #expect(HomeDailyMetrics(snapshot:snapshot,asset:.realEstate).value == nil)
 }
}
