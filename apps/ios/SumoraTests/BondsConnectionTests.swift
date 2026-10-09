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
 @Test func matchedPurchasesPayoutsAndRedemptionsDecodeWithoutTurningInterestIntoMarketGain() throws {
  let status=try JSONDecoder().decode(BondsStatus.self,from:Data("""
  {"configured":true,"gmailConnected":true,"lastSyncAt":null,"error":null,"balance":{"total":"398845","statement_date":"2026-08-31","count":8,"redemptionChecks":0,"matchedPurchases":8},"redeemed":[{"isin":"INE0MYJ07112","name":"Progfin","date":"2026-10-01","principal":"50000","interestNet":"3420.45","tds":"380"}]}
  """.utf8))
  #expect(status.balance?.matchedPurchases == 8)
  #expect(status.redeemed?.first?.principal.value == Decimal(50000))
  let terms=try JSONDecoder().decode(BondTerms.self,from:Data("""
  {"coupon":"9.3","maturesOn":"2028-11-20","redemptionCheck":false,"investedAmount":"48616.58","accruedAtPurchase":"152.88","interestGross":"1000","interestNet":"900","tds":"100","principalReceived":"0","nextPayout":"2026-11-01","frequency":"Monthly","repayment":"At Maturity","ytm":"11.75","projectedMaturityValue":"12100","quotedCoupon":"9.3","valuationBasis":"statement","reconciliationNote":null,"payoutDifference":"0.2"}
  """.utf8))
  #expect(terms.investedAmount?.value == Decimal(string:"48616.58"))
  #expect(terms.interestNet?.value == Decimal(900))
  #expect(terms.nextPayout == "2026-11-01")
  #expect(terms.ytm?.value == Decimal(string:"11.75"))
  #expect(terms.projectedMaturityValue?.value == Decimal(12100))
  #expect(terms.payoutDifference?.value == Decimal(string:"0.2"))
 }

}
