import SwiftUI
import Charts

struct AllocationSummary: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize
    let allocations: [Allocation]
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Asset Allocation").font(.appFont(.headline, weight: .bold, size: 17)).tracking(-0.425)
                    Text("Diversification across \(allocations.count) classes").font(.appFont(.caption)).foregroundStyle(DashboardStyle.secondary)
                }
                if compact {
                    Spacer(minLength: 0)
                    Text("Current mix").font(.appFont(.caption, weight: .semibold))
                        .foregroundStyle(DashboardStyle.chart).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(DashboardStyle.badge, in: Capsule())
                }
            }
            if preferences.hideBalances {
                Label("Allocation hidden", systemImage: "eye.slash").foregroundStyle(DashboardStyle.secondary)
            } else if allocations.isEmpty {
                Text("Allocation will appear when valuations are available.").foregroundStyle(DashboardStyle.secondary)
            } else if compact {
                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        ForEach(allocations) { item in
                            Rectangle().fill(item.assetClass.color)
                                .frame(width: max(0, geometry.size.width - CGFloat(allocations.count - 1)) * CGFloat(NSDecimalNumber(decimal: item.percent.value).doubleValue / 100))
                        }
                    }.clipShape(Capsule())
                }.frame(height: 12).accessibilityHidden(true)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    ForEach(allocations) { item in
                        HStack(spacing: 6) {
                            Circle().fill(item.assetClass.color).frame(width: 10, height: 10)
                            Text(item.assetClass.title).lineLimit(2)
                            Spacer(minLength: 0)
                            Text("\(DisplayFormat.decimal(item.percent.value, digits: 1))%")
                                .font(.appFont(.caption, weight: .bold)).fixedSize()
                        }.font(.appFont(.caption)).padding(10)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            } else {
                Chart(allocations) { item in
                    SectorMark(angle: .value("Value", NSDecimalNumber(decimal: item.value.value).doubleValue), innerRadius: .ratio(0.7), angularInset: 3)
                        .cornerRadius(4).foregroundStyle(item.assetClass.color)
                        .accessibilityLabel(item.assetClass.title)
                        .accessibilityValue("\(DisplayFormat.decimal(item.percent.value)) percent")
                }
                .frame(height: 170)
                .chartBackground { _ in
                    if !typeSize.isAccessibilitySize {
                        VStack(spacing: 2) {
                            Text("\(allocations.count)").font(.appFont(.title, weight: .bold))
                            Text("asset classes").font(.appFont(.caption)).foregroundStyle(DashboardStyle.secondary)
                        }
                    }
                }
                ForEach(allocations) { item in
                    HStack(spacing: 10) {
                        Circle().fill(item.assetClass.color).frame(width: 8, height: 8)
                        Text(item.assetClass.title).font(.appFont(.subheadline))
                        Spacer()
                        Text("\(DisplayFormat.decimal(item.percent.value, digits: 1))%")
                            .font(.appFont(.subheadline, weight: .semibold)).monospacedDigit().fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
    }
}
