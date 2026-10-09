import SwiftUI

struct MoneyText: View {
    @Environment(AppPreferences.self) private var preferences
    let amount: DecimalValue?
    var currency: String = "INR"
    var fractionDigits = 0

    private var text: String {
        preferences.hideBalances ? "••••" : amount.map {
            DisplayFormat.money($0.value, currency: currency, fractionDigits: fractionDigits)
        } ?? "—"
    }

    var body: some View {
        Text(text).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            .accessibilityLabel(preferences.hideBalances ? "Hidden amount" : amount == nil ? "Value unavailable" : text)
    }
}

struct GainLossLabel: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize
    let gain: DecimalValue?
    let percent: DecimalValue?
    var currency = "INR"

    var body: some View {
        if let gain {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        MoneyText(amount: gain, currency: currency)
                        if let percent {
                            Text(preferences.hideBalances ? "••••" : "\(gain.value >= 0 ? "+" : "−")\(DisplayFormat.decimal(abs(percent.value)))%")
                                .lineLimit(1).minimumScaleFactor(0.65)
                        }
                    }
                } else {
                    HStack(spacing: 4) {
                        if !preferences.hideBalances {
                            Image(systemName: gain.value >= 0 ? "arrow.up.right" : "arrow.down.right")
                        }
                        MoneyText(amount: DecimalValue(abs(gain.value)), currency: currency)
                        if let percent {
                            Text(preferences.hideBalances ? "(••••)" : "(\(DisplayFormat.decimal(abs(percent.value)))%)")
                                .lineLimit(1).minimumScaleFactor(0.65)
                        }
                    }
                }
            }
            .foregroundStyle(preferences.hideBalances ? Color.secondary : gain.value >= 0 ? DashboardStyle.positive : .red)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(preferences.hideBalances ? "Hidden return" : "\(gain.value >= 0 ? "Gain" : "Loss") \(DisplayFormat.money(abs(gain.value), currency: currency)), \(DisplayFormat.decimal(abs(percent?.value ?? 0))) percent")
        } else {
            Text("Return unavailable").foregroundStyle(DashboardStyle.secondary)
        }
    }
}

struct BalanceVisibilityButton: View {
    @Environment(AppPreferences.self) private var preferences
    var body: some View {
        Button { preferences.hideBalances.toggle() } label: {
            Image(systemName: preferences.hideBalances ? "eye.slash" : "eye")
        }
        .accessibilityLabel(preferences.hideBalances ? "Show balances" : "Hide balances")
        .accessibilityIdentifier("balanceVisibility")
    }
}
