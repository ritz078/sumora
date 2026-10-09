import SwiftUI

struct DailyPerformanceCard: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize
    let snapshot: PortfolioSnapshot
    private let classes: [AssetClass] = [.indianEquity, .usEquity, .mutualFund, .gold]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("DAILY PERFORMANCE").tracking(0.55)
                    Circle().fill(Color(red: 0.20, green: 0.83, blue: 0.60)).frame(width: 6, height: 6)
                }.font(.inter(.caption2, weight: .semibold)).frame(minHeight: 16.5)
                Text(preferences.hideBalances ? "TRACKED ASSETS · ••••" : "TRACKED ASSETS · \(snapshot.value.map { DisplayFormat.compactMoney($0.value, currency: snapshot.reportingCurrency) } ?? "—")")
                    .font(.inter(.caption)).frame(minHeight: 18)
            }.foregroundStyle(Color(red: 148/255, green: 163/255, blue: 184/255))
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(preferences.hideBalances ? "••••" : "—").font(.inter(.title, weight: .bold))
                Text(preferences.hideBalances ? "Hidden" : "Daily change unavailable")
                    .font(.inter(.caption)).foregroundStyle(Color.white.opacity(0.65))
            }.frame(minHeight: 42)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(classes) { asset in
                    let item = snapshot.allocation.first { $0.assetClass == asset }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(asset.title).font(.inter(.caption2, weight: .medium)).lineLimit(2).foregroundStyle(Color(red: 148/255, green: 163/255, blue: 184/255))
                            Spacer(minLength: 0)
                            Text(preferences.hideBalances ? "••••" : item.map { "\(DisplayFormat.decimal($0.percent.value, digits: 1))%" } ?? "—")
                                .foregroundStyle(Color(red: 0.20, green: 0.83, blue: 0.60)).font(.inter(.caption2, weight: .semibold))
                        }.font(.inter(.caption2)).frame(minHeight: 16.5)
                        MoneyText(amount: item?.value, currency: snapshot.reportingCurrency).font(.inter(.subheadline, weight: .bold, size: 14)).frame(minHeight: 21)
                        Text(item != nil ? "Current value" : snapshot.holdings.contains(where: { $0.assetClass == asset }) ? "Price unavailable" : "Not imported")
                            .font(.inter(.caption2, size: 10)).foregroundStyle(Color.white.opacity(0.55)).frame(minHeight: 15)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1))
                }
            }
        }
        .padding(21).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white)
        .background(LinearGradient(colors: [Color(red: 15/255, green: 23/255, blue: 42/255), Color(red: 30/255, green: 41/255, blue: 59/255), Color(red: 51/255, green: 75/255, blue: 112/255)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}
