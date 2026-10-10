import SwiftUI

struct HomeAllocationCard: View {
 @Environment(AppPreferences.self) private var preferences
 let snapshot: PortfolioSnapshot
 @State private var showMoney = false
 private var allocations: [Allocation] { snapshot.allocation.sorted { $0.value.value > $1.value.value } }
 var body: some View {
  VStack(alignment: .leading, spacing: 16) {
   HStack(alignment: .top) {
    VStack(alignment: .leading, spacing: 3) {
     Text("Asset Allocation").font(.inter(.headline, weight: .bold, size: 17)).tracking(-0.425)
     Text("Diversification across \(allocations.count) asset classes").font(.inter(.caption, size: 12)).foregroundStyle(HomeStyle.secondary)
    }
    Spacer(minLength: 4)
    HStack(spacing: 2) {
     toggle("₹", money: true)
     toggle("%", money: false)
    }.padding(3).background(HomeStyle.fill, in: RoundedRectangle(cornerRadius: 8))
   }
   GeometryReader { geometry in
    HStack(spacing: 0) {
     ForEach(allocations) { allocation in
      Rectangle().fill(HomeStyle.allocationColor(allocation.assetClass))
       .frame(width: geometry.size.width * CGFloat(NSDecimalNumber(decimal: allocation.percent.value / 100).doubleValue))
     }
    }.clipShape(Capsule())
   }.frame(height: 12).opacity(preferences.hideBalances ? 0 : 1).accessibilityHidden(true)
   HStack {
    Text(preferences.hideBalances ? "Net Worth ••••" : snapshot.value.map { DisplayFormat.compactMoney($0.value, currency: snapshot.reportingCurrency) + " Net Worth" } ?? "Valued assets")
    Spacer()
    Text(snapshot.coverage == .complete ? "100% Allocated" : "Available valuations")
   }.font(.inter(.caption2, size: 10)).foregroundStyle(HomeStyle.secondary).padding(.top, -8)
   VStack(spacing: 8) {
    ForEach(allocations) { allocation in
     NavigationLink {
      HoldingsView(assetClass: allocation.assetClass).toolbar(.visible, for: .navigationBar)
       .navigationTitle(HomeStyle.title(allocation.assetClass)).navigationBarTitleDisplayMode(.inline)
     } label: {
      HStack(spacing: 8) {
       Circle().fill(HomeStyle.allocationColor(allocation.assetClass)).frame(width: 8, height: 8)
       Text(HomeStyle.title(allocation.assetClass)).font(.inter(.caption, weight: .medium, size: 12)).lineLimit(1).truncationMode(.tail)
       Spacer(minLength: 4)
       Text(preferences.hideBalances ? "••••" : showMoney ? DisplayFormat.compactMoney(allocation.value.value, currency: snapshot.reportingCurrency) : DisplayFormat.decimal(allocation.percent.value, digits: 1) + "%")
        .font(.inter(.caption, weight: .bold, size: 12)).monospacedDigit()
      }.padding(10).frame(minHeight: 39).background(HomeStyle.fill, in: RoundedRectangle(cornerRadius: 12))
       .overlay(RoundedRectangle(cornerRadius: 12).stroke(HomeStyle.border, lineWidth: 1))
     }.buttonStyle(.plain).accessibilityIdentifier("allocation-\(allocation.assetClass.rawValue)")
    }
   }
  }.homeCard().foregroundStyle(HomeStyle.ink)
 }
 private func toggle(_ title: String, money: Bool) -> some View {
  Button { showMoney = money } label: {
   Text(title).font(.inter(.caption2, weight: .semibold, size: 11)).frame(width: 26, height: 22)
    .background(showMoney == money ? HomeStyle.card : .clear, in: RoundedRectangle(cornerRadius: 5))
    .foregroundStyle(showMoney == money ? HomeStyle.ink : HomeStyle.secondary)
  }.buttonStyle(.plain).accessibilityLabel(money ? "Allocation amounts" : "Allocation percentages").accessibilityAddTraits(showMoney == money ? .isSelected : [])
 }
}
