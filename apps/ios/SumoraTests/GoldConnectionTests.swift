import Foundation
import Testing
@testable import Sumora
struct GoldConnectionTests {
 @Test func decodesDatedGoldBalanceAndPrice() throws {
  let data=Data("""
  {"configured":true,"gmailConnected":true,"lastSyncAt":1791561600000,"error":null,"priceError":null,"balance":{"grams":"56.3252","silver_grams":"12.25","balance_date":"2026-10-06","period_end":"2026-09-30"},"quote":{"price":"14943","date":"2026-10-09","source":"Snapdata / IBJA daily benchmark (provisional)"}}
  """.utf8)
  let status=try JSONDecoder().decode(GoldStatus.self,from:data)
  #expect(status.balance?.grams.value == Decimal(string:"56.3252"))
  #expect(status.balance?.silver_grams?.value == Decimal(string:"12.25"))
  #expect(status.balance?.balance_date == "2026-10-06")
  #expect(status.quote?.price.value == Decimal(14943))
 }
 @Test func decodesGoldHoldingWithUnknownAcquisitionCost() throws {
  let data=Data("""
  {"id":"gullak:gold","name":"Gullak Gold","symbol":"XAU.24K.INR.G","assetClass":"gold","accountID":"gullak","quantity":"56.3252","unit":"grams","invested":"0","costBasisKnown":false,"value":"841667.4636","gain":null,"gainPercent":null,"dailyGain":"10048.41568","dailyGainPercent":"1.2083","quote":"14943","quoteCurrency":"INR","fxRate":"1","fxAt":null,"quoteAt":"2026-10-09T00:00:00Z","source":"Snapdata","priceBasis":"Estimated benchmark value","history":[]}
  """.utf8)
  let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
  let holding=try decoder.decode(Holding.self,from:data)
  #expect(holding.assetClass == .gold)
  #expect(holding.costBasisKnown == false)
  #expect(holding.gain == nil)
  #expect(holding.dailyGain?.value == Decimal(string:"10048.41568"))
 }
}
