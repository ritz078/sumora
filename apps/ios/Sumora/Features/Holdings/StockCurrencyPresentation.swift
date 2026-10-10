import Foundation

/// A display translation, not a reconstruction of historical USD cost or FX returns.
struct StockCurrencyPresentation {
 let currency: String
 private let rate: Decimal?
 private let usesUSD: Bool
 init(holdings: [Holding], reportingCurrency: String, usesUSD: Bool) {
  self.usesUSD = usesUSD
  currency = usesUSD ? "USD" : reportingCurrency
  guard usesUSD else { rate = 1; return }
  guard reportingCurrency == "INR", !holdings.isEmpty,
   holdings.allSatisfy({ $0.quoteCurrency == "USD" && ($0.fxRate?.value ?? 0) > 0 && $0.value != nil }) else { rate = nil; return }
  let inr = holdings.reduce(Decimal.zero) { $0 + $1.value!.value }
  let usd = holdings.reduce(Decimal.zero) { $0 + $1.value!.value / $1.fxRate!.value }
  rate = usd > 0 ? inr / usd : holdings.first?.fxRate?.value
 }
 func amount(_ amount: DecimalValue?, holding: Holding? = nil) -> DecimalValue? {
  guard let amount else { return nil }
  guard usesUSD else { return amount }
  let conversion = holding.map { $0.quoteCurrency == "USD" ? $0.fxRate?.value : nil } ?? rate
  guard let conversion, conversion > 0 else { return nil }
  return DecimalValue(amount.value / conversion)
 }
 func history(_ points: [HistoryPoint]) -> [HistoryPoint] {
  points.compactMap { point in amount(point.value).map { HistoryPoint(date: point.date, value: $0) } }
 }
}
