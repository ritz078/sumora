import Foundation
import Testing
@testable import Sumora
struct NPSConnectionTests {
 @Test func statementBalanceAndSchemesDecodeWithoutInventingDailyReturns() throws {
  let status=try JSONDecoder().decode(NPSStatus.self,from:Data("""
  {"configured":true,"gmailConnected":true,"lastSyncAt":1791561600000,"error":null,"balance":{"total":"2000","statement_date":"2026-09-30","count":2}}
  """.utf8))
  #expect(status.balance?.total.value == Decimal(2000))
  #expect(status.balance?.statement_date == "2026-09-30")
  let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
  let holding=try decoder.decode(Holding.self,from:Data("""
  {"id":"nps:I:E","name":"HDFC SCHEME E - TIER I","symbol":"Tier I · E","assetClass":"nps","accountID":"nps","quantity":"100","unit":"units","invested":"0","costBasisKnown":false,"value":"1000","gain":null,"gainPercent":null,"quote":"10","quoteCurrency":"INR","fxRate":"1","fxAt":null,"quoteAt":"2026-09-30T00:00:00Z","source":"KFintech NPS statement","priceBasis":"Statement valuation as of 2026-09-30","history":[]}
  """.utf8))
  #expect(holding.assetClass == .nps)
  #expect(holding.quantity.value == Decimal(100))
  #expect(holding.value?.value == Decimal(1000))
  #expect(holding.costBasisKnown == false)
  #expect(holding.gain == nil && holding.dailyGain == nil)
  #expect(HoldingsQuery(assetClass:.nps).apply(to:[holding]).count == 1)
 }
}
