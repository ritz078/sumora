import SwiftUI

struct OverviewView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(AppDependencies.self) private var dependencies

    @State private var history = HomeHistoryConnection()

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                if snapshot.holdings.isEmpty { emptyPortfolio }
                else { dashboard(snapshot) }
            } else { PortfolioLoadingView() }
        }
        .overlay(alignment: .topTrailing) {
            if store.snapshot == nil || store.snapshot?.holdings.isEmpty == true {
                NavigationLink { SettingsView().toolbar(.visible, for: .navigationBar) } label: {
                    Image(systemName: "gearshape").frame(width: 44, height: 44).background(HomeStyle.card, in: Circle())
                }.accessibilityLabel("Profile and settings").accessibilityIdentifier("homeSettings").padding(16)
            }
        }
        .background(HomeStyle.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var connectionScope: String { "\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "demo"):\(dependencies.isLivePortfolio)" }

    private func dashboard(_ snapshot: PortfolioSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HomeHeader(snapshot: snapshot)
                NetWorthCard(snapshot: snapshot)
                DailyPerformanceCard(snapshot: snapshot)
                HomeTrajectoryCard(history: dependencies.isLivePortfolio ? history.history : snapshot.history,
                    referenceDate: dependencies.demoDate, currency: snapshot.reportingCurrency, errorMessage: history.errorMessage)
                HomeAllocationCard(snapshot: snapshot)
                Text(dependencies.isLivePortfolio ? "Values reflect available linked accounts and recorded assets. Some prices and statements may be delayed." : "Sample portfolio · 6 Oct 2026. Illustrative values, not live prices.")
                    .font(.appFont(.caption2, size: 10)).foregroundStyle(HomeStyle.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 8)
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
        }
        .refreshable { await store.refresh(); await history.refresh() }
        .task(id: connectionScope) {
            history.configure(address: dependencies.zerodha.address, token: dependencies.isLivePortfolio ? dependencies.zerodha.sessionToken : nil)
            if dependencies.isLivePortfolio {
                async let saved: () = history.refresh()
                dependencies.gmail.configure(address: dependencies.zerodha.address, token: dependencies.zerodha.sessionToken)
                await dependencies.gmail.refresh()
                await saved
            }
        }
    }

    private var emptyPortfolio: some View {
        ContentUnavailableView {
            Label("Your portfolio starts here", systemImage: "chart.pie")
        } description: { Text("Once you add investments, your wealth will come together in one view.") }
        actions: {
            if dependencies.isLivePortfolio {
                NavigationLink("Manage Zerodha connection") { ConnectionsView().toolbar(.visible, for: .navigationBar) }
            } else {
                Button("Explore sample portfolio") { Task { await dependencies.selectScenario(.complete) } }.buttonStyle(.borderedProminent)
            }
        }
    }
}
