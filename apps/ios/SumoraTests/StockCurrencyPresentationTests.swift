import Foundation
import Testing
@testable import Sumora

struct StockCurrencyPresentationTests {
 @Test func rupeesRemainDefaultAndDollarsUseRecordedFX() throws {
  let holdings = try MockPortfolioAPI.load(.complete).holdings.filter { $0.assetClass == .usEquity }
  let inr = StockCurrencyPresentation(holdings: holdings, reportingCurrency: "INR", usesUSD: false)
  #expect(inr.currency == "INR")
  #expect(inr.amount(DecimalValue(1190000))?.value == 1190000)
  let usd = StockCurrencyPresentation(holdings: holdings, reportingCurrency: "INR", usesUSD: true)
  #expect(usd.amount(DecimalValue(1190000))?.value == 14000)
  #expect(usd.amount(holdings[0].value, holding: holdings[0])?.value == 10000)
  let point = HistoryPoint(date: Date(), value: DecimalValue(850000))
  #expect(usd.history([point]).first?.value.value == 10000)
 }
 @Test func missingFXNeverRelabelsRupeesAsDollars() throws {
  let fixture = try MockPortfolioAPI.load(.complete)
  let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
  var raw = try JSONSerialization.jsonObject(with: encoder.encode(fixture)) as! [String: Any]
  var holdings = raw["holdings"] as! [[String: Any]]
  for i in holdings.indices where holdings[i]["assetClass"] as? String == "usEquity" { holdings[i].removeValue(forKey: "fxRate") }
  raw["holdings"] = holdings
  let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
  let snapshot = try decoder.decode(PortfolioSnapshot.self, from: JSONSerialization.data(withJSONObject: raw))
  let us = snapshot.holdings.filter { $0.assetClass == .usEquity }
  let usd = StockCurrencyPresentation(holdings: us, reportingCurrency: "INR", usesUSD: true)
  #expect(usd.amount(DecimalValue(1190000)) == nil)
  #expect(usd.amount(us[0].value, holding: us[0]) == nil)
  #expect(usd.history([HistoryPoint(date: Date(), value: DecimalValue(850000))]).isEmpty)
 }
}
