import SwiftUI
import Charts

struct PortfolioHistoryChart: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize
    let history: [HistoryPoint]
    let referenceDate: Date
    var currency = "INR"
    var title = "Portfolio history"
    @State private var period: HistoryPeriod = .year
    @State private var selectedDate: Date?

    private var points: [HistoryPoint] { period.points(in: history, relativeTo: referenceDate).sorted { $0.date < $1.date } }
    private var selected: HistoryPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.appFont(.headline, weight: .bold, size: 17)).tracking(-0.425)
                    if !preferences.hideBalances, let first = points.first, let last = points.last, points.count > 1 {
                        Text("Starting Base \(DisplayFormat.compactMoney(first.value.value, currency: currency)) → \(DisplayFormat.compactMoney(last.value.value, currency: currency))")
                            .font(.appFont(.caption)).foregroundStyle(DashboardStyle.secondary)
                    }
                }
                Spacer(minLength: 0)
                if !preferences.hideBalances, let first = points.first, let last = points.last, first.value.value > 0, points.count > 1 {
                    let change = (last.value.value - first.value.value) / first.value.value * 100
                    Text("\(change >= 0 ? "+" : "")\(DisplayFormat.decimal(change, digits: 1))%")
                        .font(.appFont(.caption, weight: .bold)).foregroundStyle(DashboardStyle.chart)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(DashboardStyle.badge, in: Capsule())
                        .accessibilityLabel("Valuation change \(DisplayFormat.decimal(change, digits: 1)) percent")
                }
            }
            if typeSize.isAccessibilitySize {
                Picker("History period", selection: $period) { periods }.pickerStyle(.menu)
            } else {
                HStack(spacing: 0) {
                    ForEach(displayPeriods) { item in
                        Button { period = item } label: {
                            Text(item.rawValue).font(.appFont(.caption, weight: period == item ? .semibold : .medium))
                                .foregroundStyle(period == item ? DashboardStyle.ink : DashboardStyle.secondary)
                                .frame(maxWidth: .infinity, minHeight: 26)
                                .background(period == item ? Color(.secondarySystemGroupedBackground) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).accessibilityLabel("\(item.rawValue) history")
                            .accessibilityAddTraits(period == item ? [.isSelected] : [])
                    }
                }.padding(3).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            if preferences.hideBalances {
                ContentUnavailableView("History hidden", systemImage: "eye.slash", description: Text("Show balances to view your chart.")).frame(height: 150)
            } else if points.isEmpty {
                ContentUnavailableView("No history yet", systemImage: "chart.xyaxis.line", description: Text("Historical valuations will appear here.")).frame(height: 150)
            } else {
                if let selected {
                    HStack {
                        Text(selected.date, format: .dateTime.day().month(.abbreviated))
                        Spacer()
                        MoneyText(amount: selected.value, currency: currency).fontWeight(.semibold)
                    }.font(.appFont(.caption)).foregroundStyle(DashboardStyle.secondary)
                }
                Chart(points) { point in
                    AreaMark(x: .value("Date", point.date), yStart: .value("Baseline", lowerBound), yEnd: .value("Value", number(point.value)))
                        .foregroundStyle(LinearGradient(colors: [DashboardStyle.chart.opacity(0.22), DashboardStyle.chart.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", point.date), y: .value("Value", number(point.value)))
                        .foregroundStyle(DashboardStyle.chart).lineStyle(StrokeStyle(lineWidth: 2))
                    if let selected, point.id == selected.id {
                        RuleMark(x: .value("Selected date", selected.date)).foregroundStyle(Color.secondary.opacity(0.4))
                        PointMark(x: .value("Date", selected.date), y: .value("Value", number(selected.value))).foregroundStyle(DashboardStyle.chart)
                    } else if selected == nil, point.id == points.last?.id {
                        PointMark(x: .value("Date", point.date), y: .value("Value", number(point.value)))
                            .symbolSize(12).foregroundStyle(DashboardStyle.chart)
                            .annotation(position: .top, alignment: .trailing) {
                                Text(DisplayFormat.compactMoney(point.value.value, currency: currency) + (point.value.value == points.map { $0.value.value }.max() ? " · High" : ""))
                                    .font(.appFont(.caption2, weight: .semibold, size: 9)).foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 4)
                                    .background(Color(red: 15/255, green: 23/255, blue: 42/255), in: RoundedRectangle(cornerRadius: 5))
                            }
                    }
                }
                .chartYScale(domain: lowerBound...upperBound).chartXSelection(value: $selectedDate)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: axisDates) { value in
                        AxisValueLabel(anchor: value.as(Date.self) == points.last?.date ? .topTrailing : value.as(Date.self) == points.first?.date ? .topLeading : .top) {
                            if let date = value.as(Date.self) {
                                if date == points.last?.date {
                                    Text("Latest").font(.appFont(.caption2, weight: .semibold)).foregroundStyle(DashboardStyle.chart)
                                } else {
                                    Text(date, format: .dateTime.month(.abbreviated).year(.twoDigits)).font(.appFont(.caption2)).foregroundStyle(DashboardStyle.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(height: 144).accessibilityLabel(title).accessibilityIdentifier("portfolioHistory")
            }
            Text("Valuation changes include deposits and withdrawals.").font(.appFont(.caption2)).foregroundStyle(DashboardStyle.secondary)
        }
        .onChange(of: period) { _, _ in selectedDate = nil }
        .onChange(of: history.last?.date) { _, _ in selectedDate = nil }
    }

    private var periods: some View {
        ForEach(displayPeriods) { Text($0.rawValue).tag($0) }
    }
    private var displayPeriods: [HistoryPeriod] { [.month, .halfYear, .yearToDate, .year, .threeYears, .all] }
    private var axisDates: [Date] {
        guard let first = points.first, let last = points.last, first.date != last.date else { return points.map(\.date) }
        return [first.date] + (1...3).map { first.date.addingTimeInterval(last.date.timeIntervalSince(first.date) * Double($0) / 4) } + [last.date]
    }
    // Floating-point conversion is confined to chart geometry.
    private func number(_ value: DecimalValue) -> Double { NSDecimalNumber(decimal: value.value).doubleValue }
    private var lowerBound: Double { (points.map { number($0.value) }.min() ?? 0) * 0.97 }
    private var upperBound: Double { max((points.map { number($0.value) }.max() ?? 1) * 1.02, lowerBound + 1) }
}
