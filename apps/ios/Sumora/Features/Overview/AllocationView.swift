import SwiftUI

struct AllocationView: View {
    @Environment(PortfolioStore.self) private var store

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                List {
                    Section { PortfolioStatusView(); AllocationSummary(allocations: snapshot.allocation) }
                    Section("Current values") {
                        ForEach(snapshot.allocation) { allocation in
                            HStack {
                                Label(allocation.assetClass.title, systemImage: allocation.assetClass.symbol)
                                    .foregroundStyle(allocation.assetClass.color)
                                Spacer()
                                MoneyText(amount: allocation.value, currency: snapshot.reportingCurrency)
                            }.font(.appFont(.subheadline))
                        }
                    }
                }.refreshable { await store.refresh() }
            } else { PortfolioLoadingView() }
        }
        .navigationTitle("Allocation")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { BalanceVisibilityButton() } }
    }
}
