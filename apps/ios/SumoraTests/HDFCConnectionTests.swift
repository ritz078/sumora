import Foundation
import Testing
@testable import Sumora
struct HDFCConnectionTests {
 @Test func decodesFDStatusAndDatedMaturityValue() throws {
  let data=Data("""
  {"configured":true,"gmailConnected":true,"lastSyncAt":1791561600000,"error":null,"balance":{"total":"3500","statement_date":"2026-09-30","count":2}}
  """.utf8)
  let status=try JSONDecoder().decode(HDFCStatus.self,from:data)
  #expect(status.balance?.total.value == Decimal(3500))
  #expect(status.balance?.count == 2)
  #expect(status.balance?.statement_date == "2026-09-30")
 }
 @Test func decodesFDHoldingAndTermsWithoutInventingReturns() throws {
  let data=Data("""
  {"id":"hdfc:fd:masked","name":"HDFC FD ••1234","symbol":"FD ••1234","assetClass":"fixedDeposit","accountID":"hdfc","quantity":"1","unit":"deposit","invested":"0","costBasisKnown":false,"value":"1200","gain":null,"gainPercent":null,"quote":"1200","quoteCurrency":"INR","fxRate":"1","fxAt":null,"quoteAt":"2026-09-30T00:00:00Z","source":"HDFC monthly combined statement","priceBasis":"Maturity amount from statement dated 2026-09-30","history":[],"depositTerms":{"originalPrincipal":"1000","currentAmount":"1100","maturityAmount":"1200","rate":"6.25","openedOn":"2025-09-01","maturesOn":"2027-09-02","lien":"0"}}
  """.utf8)
  let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
  let holding=try decoder.decode(Holding.self,from:data)
  #expect(holding.assetClass == .fixedDeposit)
  #expect(holding.value?.value == Decimal(1200))
  #expect(holding.costBasisKnown == false)
  #expect(holding.gain == nil && holding.dailyGain == nil)
  #expect(holding.depositTerms?.maturityAmount.value == Decimal(1200))
  #expect(holding.depositTerms?.rate.value == Decimal(string:"6.25"))
 }
}
