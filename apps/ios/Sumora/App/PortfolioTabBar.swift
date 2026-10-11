import SwiftUI

struct PortfolioTabBar: View {
    @Binding var selection: AppTab
    let holdingsCount: Int
    private let items: [(AppTab, String, String)] = [
        (.overview, "Overview", "TabOverview"), (.holdings, "Holdings", "TabHoldings"),
        (.allocation, "Allocation", "TabAllocation"), (.analytics, "Analytics", "TabAnalytics")
    ]

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                Color.clear.background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().fill(Color(.systemBackground).opacity(0.75)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 1))
                tabs.padding(5)
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: selection)
        }
        .frame(maxWidth: 388)
        .frame(height: 59)
        .shadow(color: Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.14), radius: 8, y: 4)
        .accessibilityElement(children: .contain).accessibilityLabel("Tab Bar")
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { item in
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        selection = item.0
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(item.2).renderingMode(.template)
                            .overlay(alignment: .topTrailing) {
                                if item.0 == .holdings && holdingsCount > 0 {
                                    Text("\(holdingsCount)").font(.appFont(.caption2, weight: .bold, size: 9))
                                        .foregroundStyle(.white).padding(.horizontal, 4)
                                        .frame(minWidth: 16, minHeight: 14)
                                        .background(Color(red: 1, green: 0.23, blue: 0.19), in: Capsule())
                                        .overlay(Capsule().stroke(.white, lineWidth: 1))
                                        .offset(x: 9, y: -4)
                                }
                            }
                        Text(item.1).font(.appFont(.caption2, weight: selection == item.0 ? .medium : .regular, size: 10))
                            .tracking(-0.25).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 41)
                    .padding(.vertical, 4)
                    .contentShape(Capsule())
                    .foregroundStyle(selection == item.0 ? Color.accentColor : Color(.systemGray))
                }
                .buttonStyle(.plain).accessibilityLabel(item.1)
                .accessibilityIdentifier("tab-\(item.1)")
                .accessibilityAddTraits(selection == item.0 ? [.isSelected] : [])
                .accessibilityValue(item.0 == .holdings ? "\(holdingsCount) holdings" : "")
            }
        }
    }
}
