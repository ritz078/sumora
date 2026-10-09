import SwiftUI

struct NetWorthCard: View {
    @Environment(AppDependencies.self) private var dependencies
    let snapshot: PortfolioSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack { heading; Spacer(minLength: 8); returnBadge }
                VStack(alignment: .leading, spacing: 8) { heading; returnBadge }
            }
            MoneyText(amount: snapshot.value, currency: snapshot.reportingCurrency)
                .font(.inter(.largeTitle, weight: .bold)).tracking(-0.8)
                .padding(.vertical, 8)
                .accessibilityIdentifier("portfolioValue")
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Today:")
                Text("Daily return unavailable")
            }.font(.inter(.caption)).foregroundStyle(DashboardStyle.secondary).padding(.top, 5)
        }.frame(maxWidth: .infinity, alignment: .leading).portfolioCard()
    }

    private var heading: some View {
        Text(dependencies.isLivePortfolio ? "IMPORTED PORTFOLIO" : "ESTIMATED NET WORTH")
            .font(.inter(.caption2, weight: .semibold)).tracking(0.55).foregroundStyle(DashboardStyle.secondary)
    }
    private var returnBadge: some View { ReturnBadge(percent: snapshot.gainPercent, label: "All-time") }
}

struct ReturnBadge: View {
    @Environment(AppPreferences.self) private var preferences
    let percent: DecimalValue?
    var label = ""

    var body: some View {
        if let percent {
            HStack(spacing: 3) {
                if !preferences.hideBalances && percent.value >= 0 {
                    Image("ReturnArrow").renderingMode(.original).accessibilityHidden(true)
                }
                Text(preferences.hideBalances ? "••••" : "\(percent.value >= 0 ? "+" : "")\(DisplayFormat.decimal(percent.value))%")
                    .fontWeight(.semibold)
                if !label.isEmpty { Text(label).font(.inter(.caption2, size: 10)) }
            }
            .font(.inter(.caption2)).padding(.horizontal, 11).padding(.vertical, 3)
            .foregroundStyle(preferences.hideBalances ? Color.secondary : percent.value >= 0 ? DashboardStyle.positive : .red)
            .background((preferences.hideBalances ? Color.secondary : percent.value >= 0 ? DashboardStyle.positive : Color.red).opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke((preferences.hideBalances ? Color.secondary : percent.value >= 0 ? DashboardStyle.positive : Color.red).opacity(0.16), lineWidth: 1))
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}
