import SwiftUI

struct HoldingRow: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize
    let holding: Holding
    let currency: String
    var compact = false

    var body: some View {
        if compact {
            Group {
                if !typeSize.isAccessibilitySize {
                    HStack(alignment: .top, spacing: 12) {
                        compactIcon
                        compactIdentity.frame(maxWidth: .infinity, alignment: .leading)
                        compactValuation.fixedSize(horizontal: true, vertical: false).padding(.top, 2)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 12) { compactIcon; compactIdentity }
                        compactValuation
                    }
                }
            }
        } else if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) { identity; valuation }
                .padding(.vertical, 8)
        } else {
            HStack(alignment: .center, spacing: 12) {
                identity
                Spacer(minLength: 8)
                valuation
            }.padding(.vertical, 8)
        }
    }

    private var compactIdentity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(holding.name).font(.inter(.subheadline, weight: .semibold, size: 14)).lineLimit(1).truncationMode(.tail)
            Text("\(holding.assetClass.title) · \(DisplayFormat.decimal(holding.quantity.value)) \(holding.unit)")
                .font(.inter(.caption2)).foregroundStyle(DashboardStyle.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var compactValuation: some View {
        VStack(alignment: .trailing, spacing: 2) {
            MoneyText(amount: holding.value, currency: currency).font(.inter(.subheadline, weight: .bold, size: 14))
            if holding.value == nil { Text("Price unavailable").font(.inter(.caption2)).foregroundStyle(DashboardStyle.secondary) }
            else if let percent = holding.gainPercent {
                Text(preferences.hideBalances ? "••••" : "\(percent.value >= 0 ? "+" : "")\(DisplayFormat.decimal(percent.value, digits: 1))%")
                    .font(.inter(.caption2, weight: .semibold))
                    .foregroundStyle(preferences.hideBalances ? Color.secondary : percent.value >= 0 ? DashboardStyle.positive : .red)
            }
        }
    }

    private var compactIcon: some View {
        let style: (name: String, color: Color) = switch holding.assetClass {
        case .indianEquity: ("HoldingIndianEquity", Color(red: 37/255, green: 99/255, blue: 235/255))
        case .usEquity: ("HoldingUSEquity", Color(red: 2/255, green: 132/255, blue: 199/255))
        case .mutualFund: ("HoldingMutualFund", DashboardStyle.positive)
        case .gold: ("HoldingGold", Color(red: 217/255, green: 119/255, blue: 6/255))
        case .bond: ("HoldingBond", Color(red: 126/255, green: 34/255, blue: 206/255))
        }
        return Image(style.name).renderingMode(.template).resizable().frame(width: 19, height: 19)
            .foregroundStyle(style.color)
            .frame(width: 36, height: 36)
            .background(style.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.color.opacity(0.12), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var identity: some View {
        HStack(spacing: 12) {
            Image(systemName: holding.assetClass.symbol)
                .font(.inter(.body, weight: .semibold)).foregroundStyle(holding.assetClass.color)
                .frame(width: 42, height: 42)
                .background(holding.assetClass.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(holding.name).font(.inter(.subheadline, weight: .semibold)).lineLimit(2)
                Text("\(holding.symbol) · \(holding.assetClass.title)").font(.inter(.caption)).foregroundStyle(DashboardStyle.secondary)
                FreshnessBadge(quoteAt: holding.quoteAt)
            }
        }
    }

    private var valuation: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 5) {
            MoneyText(amount: holding.value, currency: currency).font(.inter(.subheadline, weight: .semibold))
            if holding.value == nil {
                Text("Price unavailable").font(.inter(.caption)).foregroundStyle(.orange)
            } else {
                GainLossLabel(gain: holding.gain, percent: nil, currency: currency).font(.inter(.caption))
            }
        }
    }
}
