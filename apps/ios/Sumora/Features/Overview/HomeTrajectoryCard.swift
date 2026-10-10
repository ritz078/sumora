import SwiftUI
import Charts

struct HomeTrajectoryCard: View {
 @Environment(AppPreferences.self) private var preferences
 let history: [HistoryPoint]
 let referenceDate: Date
 let currency: String
 var errorMessage: String?
 @State private var period: HistoryPeriod = .year
 private var points: [HistoryPoint] { (showsPeriodSelector ? period : .all).points(in: history, relativeTo: referenceDate).sorted { $0.date < $1.date } }
 private var change: Decimal? {
  guard points.count > 1, let first = points.first, let last = points.last, first.value.value > 0 else { return nil }
  return (last.value.value - first.value.value) / first.value.value * 100
 }
 var title = "Portfolio Trajectory"
 var instrumentStyle = false
 var roundedInstrumentCallout = false
 var showsPeriodSelector = true
 var goldStyle = false
 private var chartColor:Color { goldStyle ? Color(red:217/255,green:119/255,blue:6/255) : HomeStyle.indigo }
 private var calloutColor:Color { goldStyle ? chartColor : Color(red:15/255,green:23/255,blue:42/255) }
 var body: some View {
  VStack(alignment: .leading, spacing: 0) {
   HStack {
    VStack(alignment: .leading, spacing: 3) {
     Text(title).font(.inter(.headline, weight: .bold, size: instrumentStyle ? 15 : 17)).tracking(-0.425)
     Text(subtitle).font(.inter(.caption, size: instrumentStyle ? 11 : 12)).foregroundStyle(HomeStyle.secondary)
    }
    Spacer(minLength: 4)
    if let change, !preferences.hideBalances {
     Text("\(change >= 0 ? "+" : "")\(DisplayFormat.decimal(change, digits: 1))%")
      .font(.inter(.caption2, weight: .semibold, size: 10)).foregroundStyle(change >= 0 ? DashboardStyle.positive : .red)
      .padding(.horizontal, 8).padding(.vertical, 2)
      .background(HomeStyle.emerald.opacity(0.08), in: RoundedRectangle(cornerRadius: instrumentStyle && !goldStyle ? 99 : 4))
      .overlay(RoundedRectangle(cornerRadius: instrumentStyle && !goldStyle ? 99 : 4).stroke(HomeStyle.emerald.opacity(0.2), lineWidth: 1))
    }
   }.padding(.bottom, 12)
   if showsPeriodSelector { HStack(spacing: 0) {
    ForEach([HistoryPeriod.month, .halfYear, .year, .all]) { item in
     Button { period = item } label: {
      Text(item == .all ? "ALL" : item.rawValue).font(.inter(.caption2, weight: period == item ? .semibold : .medium, size: 11))
       .foregroundStyle(period == item ? HomeStyle.ink : HomeStyle.secondary)
       .frame(maxWidth: .infinity, minHeight: goldStyle ? 26 : 22)
       .background(period == item ? HomeStyle.card : .clear, in: RoundedRectangle(cornerRadius: 6))
       .shadow(color: .black.opacity(period == item ? 0.05 : 0), radius: 1, y: 1)
     }.buttonStyle(.plain).accessibilityLabel("\(item.rawValue) history").accessibilityAddTraits(period == item ? .isSelected : [])
    }
   }.padding(2).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(HomeStyle.border, lineWidth: 1)).padding(.bottom, 16) }
   if preferences.hideBalances {
    Text("History hidden").font(.inter(.caption)).foregroundStyle(HomeStyle.secondary).frame(maxWidth: .infinity, minHeight: 158)
   } else if points.count < 2 {
    VStack(spacing: 12) {
     Image(systemName: "chart.xyaxis.line").font(.system(size: 28)).foregroundStyle(HomeStyle.indigo.opacity(0.4))
     Text(points.isEmpty ? "Daily snapshots will appear here" : "History starts today")
      .font(.inter(.caption, size: 12)).foregroundStyle(HomeStyle.secondary)
    }.frame(maxWidth: .infinity, minHeight: 158)
   } else { chart.accessibilityElement(children: .contain).accessibilityLabel("Portfolio history").accessibilityIdentifier("portfolioHistory") }
   if let errorMessage {
    Text(errorMessage).font(.inter(.caption2, size: 10)).foregroundStyle(HomeStyle.secondary).lineLimit(2).padding(.top, 8)
   }
  }.homeCard(padding:goldStyle ? 16 : 20,cornerRadius:goldStyle ? 8 : 16).foregroundStyle(HomeStyle.ink)
   .accessibilityHint("Valuation changes include deposits and withdrawals.")
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
  let interval = last.date.timeIntervalSince(first.date)
  let segments = min(4, max(1, Int(interval / 86400)))
  return (0...segments).map { first.date.addingTimeInterval(interval * Double($0) / Double(segments)) }
 }
 private func dateLabel(_ date: Date, latest: Bool) -> String {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
  if latest { return calendar.isDate(date, inSameDayAs: referenceDate) ? "Today" : "Latest" }
  let formatter = DateFormatter()
  formatter.timeZone = calendar.timeZone
  formatter.locale = Locale(identifier: "en_IN")
  formatter.dateFormat = (points.last!.date.timeIntervalSince(points.first!.date) < 90 * 86400) ? "d MMM" : "MMM ''yy"
  return formatter.string(from: date)
 }
 private func axisLabel(_ value: Double) -> String {
  let amount = Decimal(value)
  if currency == "INR", abs(amount) >= 10_000_000 { return "₹" + DisplayFormat.decimal(amount / 10_000_000, digits: 1) + " Cr" }
  if currency == "INR", abs(amount) >= 100_000 { return "₹" + DisplayFormat.decimal(amount / 100_000, digits: 1) + " L" }
  return DisplayFormat.money(amount, currency: currency)
 }
 private var chart: some View {
  VStack(spacing: 0) {
   GeometryReader { geometry in
    ZStack(alignment: .topLeading) {
     // Stitch's labels sit inside the plot. Native axes reserve an extra gutter.
     Path { path in
      for y in [20.0, 65.0, 110.0] {
       path.move(to: CGPoint(x: 0, y: y))
       path.addLine(to: CGPoint(x: geometry.size.width, y: y))
      }
     }.stroke(Color(red: 226/255, green: 232/255, blue: 240/255), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
      .accessibilityHidden(true)
     plot.accessibilityLabel("Daily portfolio values")
     if !instrumentStyle {
     ForEach(0..<3) { index in
      let y = 20.0 + Double(index) * 45
      let value = upper - (upper - lower) * y / 140
      Text(axisLabel(value))
       .font(.inter(.caption2, size: 9)).foregroundStyle(HomeStyle.muted)
       .frame(maxWidth: .infinity, alignment: .trailing).offset(y: y - 15)
       .accessibilityIdentifier("home-y-label-\(index)")
     }
     }
     if let last = points.last {
      HStack(spacing: 4) {
       if !goldStyle && (!instrumentStyle || roundedInstrumentCallout) { Circle().fill(HomeStyle.emerald).frame(width: 6, height: 6) }
       Text(DisplayFormat.compactMoney(last.value.value, currency: currency))
        .font(.inter(.caption2, weight: .semibold, size: 10))
      }.foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3)
       .background(calloutColor, in: RoundedRectangle(cornerRadius: instrumentStyle && !roundedInstrumentCallout ? 2 : 99))
       .overlay(alignment: .bottom) {
        if instrumentStyle && !roundedInstrumentCallout { Rectangle().fill(calloutColor).frame(width: 6, height: 6).rotationEffect(.degrees(45)).offset(y: 3) }
       }
       .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
       .fixedSize().frame(maxWidth: .infinity, alignment: .trailing).offset(x: -4, y: instrumentStyle ? -8 : -18)
       .accessibilityElement(children: .ignore)
       .accessibilityLabel("Latest recorded value " + DisplayFormat.compactMoney(last.value.value, currency: currency))
       .accessibilityIdentifier("home-latest-value")
     }
    }.accessibilityElement(children: .contain).accessibilityLabel("Recorded net worth plot").accessibilityIdentifier("home-plot")
   }.frame(height: 140).padding(.top, 8)
   dateFooter
  }
 }
 private var plot: some View {
  Chart(points) { point in
   AreaMark(x: .value("Date", point.date), yStart: .value("Base", lower), yEnd: .value("Net worth", number(point.value)))
    .interpolationMethod(.monotone)
    .foregroundStyle(LinearGradient(stops: [.init(color: chartColor.opacity(0.24), location: 0), .init(color: chartColor.opacity(0.02), location: 0.8), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
   LineMark(x: .value("Date", point.date), y: .value("Net worth", number(point.value)))
    .interpolationMethod(.monotone)
    .foregroundStyle(chartColor).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
   if point.id == points.last?.id {
    PointMark(x: .value("Date", point.date), y: .value("Net worth", number(point.value)))
     .symbolSize(154).foregroundStyle(chartColor.opacity(0.15))
    PointMark(x: .value("Date", point.date), y: .value("Net worth", number(point.value)))
     .symbolSize(50).foregroundStyle(chartColor)
    PointMark(x: .value("Date", point.date), y: .value("Net worth", number(point.value)))
     .symbolSize(10).foregroundStyle(.white)
   }
  }.chartYScale(domain: lower...upper)
   .chartXScale(domain: points.first!.date...points.last!.date)
   .chartXAxis(.hidden).chartYAxis(.hidden)
 }
 private var dateFooter: some View {
  GeometryReader { geometry in
   let dates = axisDates
   let width = geometry.size.width / CGFloat(max(dates.count, 1))
   ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
    let latest = index == dates.count - 1
    let x = index == 0 ? width / 2 : latest ? geometry.size.width - width / 2 : geometry.size.width * CGFloat(date.timeIntervalSince(dates[0]) / dates.last!.timeIntervalSince(dates[0]))
    Text(dateLabel(date, latest: latest))
     .font(.inter(.caption2, weight: latest ? .semibold : .medium, size: 10))
     .foregroundStyle(latest ? (goldStyle ? HomeStyle.ink : HomeStyle.indigo) : HomeStyle.muted)
     .frame(width: width, alignment: index == 0 ? .leading : latest ? .trailing : .center)
     .position(x: x, y: 14)
     .accessibilityIdentifier("home-x-label-\(index)")
   }
  }.frame(height: 26)
   .overlay(alignment: .top) { Rectangle().fill(HomeStyle.border).frame(height: 1).accessibilityHidden(true) }
 }
}
