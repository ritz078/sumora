import SwiftUI

struct OverviewView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                if snapshot.holdings.isEmpty { emptyPortfolio }
                else { dashboard(snapshot) }
            } else { PortfolioLoadingView() }
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
    }

    private func dashboard(_ snapshot: PortfolioSnapshot) -> some View {
        List {
            Section {
                if snapshot.coverage != .complete || snapshot.connections.contains(where: { $0.status == .attention }) && dependencies.isLivePortfolio || dependencies.demoDate.timeIntervalSince(snapshot.capturedAt) > 86400 {
                    PortfolioStatusView().padding(.vertical, 8)
                }
                NetWorthCard(snapshot: snapshot).padding(.vertical, 8)
                DailyPerformanceCard(snapshot: snapshot).padding(.vertical, 8)
                AllocationSummary(allocations: snapshot.allocation, compact: true).portfolioCard().padding(.vertical, 8)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden).listRowBackground(Color.clear)

            Section {
                HStack {
                    DemoBadge()
                    Spacer()
                    BalanceVisibilityButton()
                    NavigationLink("Manage accounts") { ConnectionsView().toolbar(.visible, for: .navigationBar) }
                        .font(.inter(.caption))
                }.buttonStyle(.borderless).labelStyle(.titleAndIcon)
                Text(dependencies.isLivePortfolio ? "Imported from Zerodha’s primary demat account and Coin. Secondary demat holdings and intraday positions are excluded." : "Sample portfolio · 6 Oct 2026. Illustrative values, not live prices.")
                    .font(.inter(.caption)).foregroundStyle(DashboardStyle.secondary)
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        .listStyle(.plain).listSectionSpacing(8)
        .contentMargins(.top, 0)
        .scrollContentBackground(.hidden)
        .refreshable { await store.refresh() }
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
