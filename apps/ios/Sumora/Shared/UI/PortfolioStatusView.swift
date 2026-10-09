import SwiftUI

struct PortfolioStatusView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = store.snapshot {
                if dependencies.isLivePortfolio && snapshot.connections.contains(where: { $0.status == .attention }) {
                    Label("Reconnect Zerodha to update quantities. Available closing prices are applied to your recorded holdings.", systemImage: "link.badge.plus")
                        .foregroundStyle(.orange)
                    Button("Reconnect Zerodha") { Task { await dependencies.connectZerodha() } }
                        .disabled(dependencies.zerodha.isConnecting)
                }
                if snapshot.coverage == .partial {
                    Label("Partial valuation · \(snapshot.holdings.filter { $0.value == nil }.count) holding has no price", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                    Text("Totals and returns include only holdings with available prices.").foregroundStyle(.secondary)
                } else if snapshot.coverage == .unavailable {
                    Label("Prices unavailable", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                    Text("Your holdings are available. Portfolio value and returns will appear when prices return.").foregroundStyle(.secondary)
                }
                if dependencies.demoDate.timeIntervalSince(snapshot.capturedAt) > 86400 {
                    Label("Outdated snapshot · updated \(DisplayFormat.age(snapshot.capturedAt, relativeTo: dependencies.demoDate))", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
            }
        }
        .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PortfolioLoadingView: View {
    @Environment(PortfolioStore.self) private var store
    var body: some View {
        if store.isRefreshing {
            VStack(spacing: 16) {
                ProgressView()
                Text("Gathering your portfolio…").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Couldn't load your portfolio", systemImage: "wifi.exclamationmark")
            } description: {
                Text(store.errorMessage ?? "Try refreshing to load your portfolio.")
            } actions: {
                Button("Try again") { Task { await store.refresh() } }.buttonStyle(.borderedProminent)
            }
        }
    }
}

struct DemoBadge: View {
    @Environment(AppDependencies.self) private var dependencies
    var body: some View {
        Label(dependencies.isLivePortfolio ? "ZERODHA" : "DEMO", systemImage: dependencies.isLivePortfolio ? "link" : "sparkle")
            .font(.caption2.weight(.semibold)).tracking(1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1), in: Capsule())
            .foregroundStyle(Color.accentColor)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(dependencies.isLivePortfolio ? "Your Zerodha portfolio" : "Demo portfolio with sample data")
    }
}
