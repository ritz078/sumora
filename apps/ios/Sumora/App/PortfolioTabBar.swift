import SwiftUI

struct PortfolioTabBar: View {
    @Binding var selection: AppTab
    let holdingsCount: Int
    private let items: [(AppTab, String, String)] = [
        (.overview, "Overview", "TabOverview"), (.holdings, "Holdings", "TabHoldings"),
        (.allocation, "Allocation", "TabAllocation"), (.analytics, "Analytics", "TabAnalytics"),
        (.settings, "Settings", "TabSettings")
    ]

    var body: some View {
        GeometryReader { geometry in
            let tabWidth = (geometry.size.width - 10) / CGFloat(items.count)
            ZStack(alignment: .topLeading) {
                Color.clear.modifier(TabBarGlass())
                Capsule().fill(Color.clear)
                    .modifier(SelectionGlass())
                    .frame(width: tabWidth, height: 49)
                    .offset(x: 5 + CGFloat(selectedIndex) * tabWidth, y: 5)
                    .allowsHitTesting(false)
                tabs.padding(5)
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: selection)
        }
        .frame(maxWidth: 388)
        .frame(height: 59)
        .shadow(color: Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.14), radius: 8, y: 4)
        .accessibilityElement(children: .contain).accessibilityLabel("Tab Bar")
    }

    private var selectedIndex: Int {
        items.firstIndex { $0.0 == selection } ?? 0
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
                                    Text("\(holdingsCount)").font(.inter(.caption2, weight: .bold, size: 9))
                                        .foregroundStyle(.white).padding(.horizontal, 4)
                                        .frame(minWidth: 14, minHeight: 14)
                                        .background(Color(red: 1, green: 0.23, blue: 0.19), in: Capsule())
                                        .offset(x: 9, y: -4)
                                }
                            }
                        Text(item.1).font(.inter(.caption2, weight: selection == item.0 ? .medium : .regular, size: 10))
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

private struct TabBarGlass: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.clear.tint((colorScheme == .dark ? Color.black : Color.white).opacity(0.22)).interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
        }
    }
}

private struct SelectionGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.clear.tint(Color.accentColor.opacity(0.14)).interactive(), in: Capsule())
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().fill(Color.accentColor.opacity(0.12)))
        }
    }
}
