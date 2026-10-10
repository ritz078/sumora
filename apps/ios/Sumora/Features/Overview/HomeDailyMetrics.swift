import Foundation

/// Daily performance is available only when every holding in the group has a baseline.
struct HomeDailyMetrics {
 let value: DecimalValue?
 let gain: DecimalValue?
 let percent: DecimalValue?
 init(snapshot: PortfolioSnapshot, asset: AssetClass? = nil) {
  let traded: Set<AssetClass> = [.indianEquity, .usEquity, .mutualFund, .gold]
  let holdings = snapshot.holdings.filter { asset == nil ? traded.contains($0.assetClass) : $0.assetClass == asset }
  guard !holdings.isEmpty, holdings.allSatisfy({ $0.value != nil }) else {
   value = nil; gain = nil; percent = nil; return
  }
  let total = holdings.reduce(Decimal.zero) { $0 + ($1.value?.value ?? 0) }
  value = DecimalValue(total)
  guard holdings.allSatisfy({ $0.dailyGain != nil }) else { gain = nil; percent = nil; return }
  let change = holdings.reduce(Decimal.zero) { $0 + ($1.dailyGain?.value ?? 0) }
  gain = DecimalValue(change)
  percent = total - change > 0 ? DecimalValue(change / (total - change) * 100) : nil
 }
}
