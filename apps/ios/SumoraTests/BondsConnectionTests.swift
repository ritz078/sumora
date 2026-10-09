import Foundation
import Testing
@testable import Sumora
struct BondsConnectionTests {
 @Test func datedBondBalancesDecodeWithRedemptionWarningAndNoInventedReturns() throws {
  let status=try JSONDecoder().decode(BondsStatus.self,from:Data("""
  {"configured":true,"gmailConnected":true,"lastSyncAt":null,"error":null,"balance":{"total":"448845","statement_date":"2026-08-31","count":9,"redemptionChecks":1}}
  """.utf8))
  #expect(status.balance?.total.value == Decimal(448845))
  #expect(status.balance?.redemptionChecks == 1)
  let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
  let holding=try decoder.decode(Holding.self,from:Data("""
  {"id":"bonds:INE0MYJ07112","name":"PROGFIN PRIVATE LIMITED","symbol":"INE0MYJ07112","assetClass":"bond","accountID":"bonds","quantity":"5","unit":"bonds","invested":"0","costBasisKnown":false,"value":"50000","gain":null,"gainPercent":null,"quote":"10000","quoteCurrency":"INR","fxRate":"1","fxAt":null,"quoteAt":"2026-08-31T00:00:00Z","source":"CDSL CAS · NSDL","priceBasis":"Statement value","history":[],"bondTerms":{"coupon":"11","maturesOn":"2026-10-04","redemptionCheck":true}}
  """.utf8))
  #expect(holding.assetClass == .bond)
  #expect(holding.bondTerms?.coupon?.value == Decimal(11))
  #expect(holding.bondTerms?.redemptionCheck == true)
  #expect(holding.bondTerms?.maturesOn == "2026-10-04")
  #expect(holding.costBasisKnown == false && holding.gain == nil && holding.dailyGain == nil)
  #expect(HoldingsQuery(assetClass:.bond).apply(to:[holding]).count == 1)
 }
}
