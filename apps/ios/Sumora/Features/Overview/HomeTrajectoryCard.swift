import SwiftUI
import Charts

struct HomeTrajectoryCard: View {
 @Environment(AppPreferences.self) private var preferences
 let history: [HistoryPoint]
 let referenceDate: Date
 let currency: String
 var errorMessage: String?
 @State private var period: HistoryPeriod = .year
 private var points: [HistoryPoint] { period.points(in: history, relativeTo: referenceDate).sorted { $0.date < $1.date } }
 private var change: Decimal? {
  guard points.count > 1, let first = points.first, let last = points.last, first.value.value > 0 else { return nil }
  return (last.value.value - first.value.value) / first.value.value * 100
 }
 var body: some View {
  VStack(alignment: .leading, spacing: 16) {
   HStack {
    VStack(alignment: .leading, spacing: 3) {
     Text("Portfolio Trajectory").font(.inter(.headline, weight: .bold, size: 17)).tracking(-0.425)
     Text(subtitle).font(.inter(.caption, size: 12)).foregroundStyle(HomeStyle.secondary)
    }
    Spacer(minLength: 4)
    if let change, !preferences.hideBalances {
     Text("\(change >= 0 ? "+" : "")\(DisplayFormat.decimal(change, digits: 1))%")
      .font(.inter(.caption, weight: .bold, size: 12)).foregroundStyle(change >= 0 ? HomeStyle.emerald : .red)
      .padding(.horizontal, 8).padding(.vertical, 4).background(HomeStyle.emerald.opacity(0.08), in: Capsule())
    }
   }
   HStack(spacing: 0) {
    ForEach([HistoryPeriod.month, .halfYear, .year, .all]) { item in
     Button { period = item } label: {
      Text(item == .all ? "ALL" : item.rawValue).font(.inter(.caption2, weight: .semibold, size: 11))
       .foregroundStyle(period == item ? HomeStyle.ink : HomeStyle.secondary)
       .frame(maxWidth: .infinity, minHeight: 26)
       .background(period == item ? HomeStyle.card : .clear, in: RoundedRectangle(cornerRadius: 6))
       .shadow(color: .black.opacity(period == item ? 0.05 : 0), radius: 1, y: 1)
     }.buttonStyle(.plain).accessibilityLabel("\(item.rawValue) history").accessibilityAddTraits(period == item ? .isSelected : [])
    }
   }.padding(3).background(HomeStyle.fill, in: RoundedRectangle(cornerRadius: 8))
   if preferences.hideBalances {
    Text("History hidden").font(.inter(.caption)).foregroundStyle(HomeStyle.secondary).frame(maxWidth: .infinity, minHeight: 158)
   } else if points.count < 2 {
    VStack(spacing: 12) {
     Image(systemName: "chart.xyaxis.line").font(.system(size: 28)).foregroundStyle(HomeStyle.indigo.opacity(0.4))
     Text(points.isEmpty ? "Daily snapshots will appear here" : "History starts today")
      .font(.inter(.caption, size: 12)).foregroundStyle(HomeStyle.secondary)
    }.frame(maxWidth: .infinity, minHeight: 158)
   } else { chart.frame(height: 158).accessibilityIdentifier("portfolioHistory") }
   Text(errorMessage ?? "Valuation changes include deposits and withdrawals.")
    .font(.inter(.caption2, size: 10)).foregroundStyle(HomeStyle.secondary).lineLimit(2)
  }.homeCard().foregroundStyle(HomeStyle.ink)
 }
 private var subtitle: String {
  guard !preferences.hideBalances, let first = points.first, let last = points.last, points.count > 1 else { return "Your recorded net worth over time" }
  let delta = last.value.value - first.value.value
  return (delta >= 0 ? "+" : "−") + DisplayFormat.compactMoney(abs(delta), currency: currency) + " over available history"
 }
 private func number(_ value: DecimalValue) -> Double { NSDecimalNumber(decimal: value.value).doubleValue }
 private var lower: Double { (points.map { number($0.value) }.min() ?? 0) * 0.97 }
 private var upper: Double { max((points.map { number($0.value) }.max() ?? 1) * 1.03, lower + 1) }
 private var axisDates: [Date] {
  guard let first = points.first, let last = points.last else { return [] }
  return [first.date] + (1...3).map { first.date.addingTimeInterval(last.date.timeIntervalSince(first.date) * Double($0) / 4) } + [last.date]
 }
 private var chart: some View {
  Chart(points) { point in
   AreaMark(x: .value("Date", point.date), yStart: .value("Base", lower), yEnd: .value("Net worth", number(point.value)))
    .foregroundStyle(LinearGradient(colors: [HomeStyle.indigo.opacity(0.24), HomeStyle.indigo.opacity(0)], startPoint: .top, endPoint: .bottom))
   LineMark(x: .value("Date", point.date), y: .value("Net worth", number(point.value)))
    .foregroundStyle(HomeStyle.indigo).lineStyle(StrokeStyle(lineWidth: 2.5))
   if point.id == points.last?.id {
    PointMark(x: .value("Date", point.date), y: .value("Net worth", number(point.value))).symbolSize(24).foregroundStyle(HomeStyle.indigo)
     .annotation(position: .top, alignment: .trailing) {
      HStack(spacing: 4) {
       Circle().fill(HomeStyle.emerald).frame(width: 6, height: 6)
       Text(DisplayFormat.compactMoney(point.value.value, currency: currency)).font(.inter(.caption2, weight: .semibold, size: 10))
      }.foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3)
       .background(Color(red: 15/255, green: 23/255, blue: 42/255), in: Capsule())
     }
   }
  }.chartYScale(domain: lower...upper)
   .chartYAxis {
    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
     AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(HomeStyle.border)
     AxisValueLabel { if let number = value.as(Double.self) { Text(DisplayFormat.compactMoney(Decimal(number), currency: currency)).font(.inter(.caption2, size: 9)).foregroundStyle(HomeStyle.muted) } }
    }
   }
   .chartXAxis {
    AxisMarks(values: axisDates) { value in
     AxisValueLabel(anchor: value.as(Date.self) == points.last?.date ? .topTrailing : .topLeading) {
      if value.as(Date.self) == points.last?.date { Text("Latest").foregroundStyle(HomeStyle.indigo).font(.inter(.caption2, weight: .semibold, size: 10)) }
      else if let date = value.as(Date.self) { Text(date, format: .dateTime.month(.abbreviated).year(.twoDigits)).font(.inter(.caption2, size: 10)).foregroundStyle(HomeStyle.muted) }
     }
    }
   }
 }
}
