import SwiftUI

struct AnalyticsView: View {
    @Environment(PortfolioStore.self) private var store

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                List {
                    Section {
                        PortfolioStatusView()
                        PortfolioHistoryChart(history: snapshot.history, referenceDate: snapshot.capturedAt, currency: snapshot.reportingCurrency)
                    }
                    Section("Unrealized return") {
                        GainLossLabel(gain: snapshot.gain, percent: snapshot.gainPercent, currency: snapshot.reportingCurrency)
                        HStack {
                            Text(snapshot.coverage == .complete ? "Invested" : "Invested in priced holdings")
                            Spacer()
                            MoneyText(amount: snapshot.coveredInvested, currency: snapshot.reportingCurrency)
                        }
                        Text("Returns exclude realized gains. Valuation history includes deposits and withdrawals.")
                            .font(.inter(.caption)).foregroundStyle(DashboardStyle.secondary)
                    }
                    Section("Holdings by unrealized gain") {
                        ForEach(HoldingsQuery(sort: .gain).apply(to: snapshot.holdings)) { holding in
                            NavigationLink(value: holding.id) { HoldingRow(holding: holding, currency: snapshot.reportingCurrency, compact: true) }
                        }
                    }
                }.refreshable { await store.refresh() }
            } else { PortfolioLoadingView() }
        }
        .navigationTitle("Analytics")
        .navigationDestination(for: String.self) { HoldingDetailView(holdingID: $0) }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { BalanceVisibilityButton() } }
    }
}
