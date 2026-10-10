import SwiftUI

extension Appearance {
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

extension AssetClass {
    var color: Color {
        switch self {
        case .indianEquity: Color(red: 0.31, green: 0.27, blue: 0.90)
        case .usEquity: Color(red: 0.055, green: 0.65, blue: 0.91)
        case .mutualFund: Color(red: 0.02, green: 0.59, blue: 0.41)
        case .gold: Color(red: 0.96, green: 0.62, blue: 0.04)
        case .realEstate: Color(red: 0.64, green: 0.34, blue: 0.15)
        case .nps: Color(red: 0.86, green: 0.22, blue: 0.48)
        case .bond, .fixedDeposit: Color(red: 0.49, green: 0.23, blue: 0.93)
        }
    }
}

extension View {
    func portfolioCard() -> some View {
        padding(21)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.025), lineWidth: 1))
            .shadow(color: .black.opacity(0.025), radius: 2, y: 1)
    }
}

enum DashboardStyle {
    static let chart = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 165/255, green: 180/255, blue: 252/255, alpha: 1) : UIColor(red: 79/255, green: 70/255, blue: 229/255, alpha: 1) })
    static let positive = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 52/255, green: 211/255, blue: 153/255, alpha: 1) : UIColor(red: 5/255, green: 150/255, blue: 105/255, alpha: 1) })
    static let badge = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.20, green: 0.22, blue: 0.34, alpha: 1) : UIColor(red: 238/255, green: 242/255, blue: 1, alpha: 1) })
    static let ink = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .label : UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1) })
    static let secondary = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .secondaryLabel : UIColor(red: 100/255, green: 116/255, blue: 139/255, alpha: 1) })
}

extension Font {
    static func inter(_ style: Font.TextStyle, weight: Font.Weight = .regular, size: CGFloat? = nil) -> Font {
        let base: CGFloat
        switch style {
        case .largeTitle: base = 32
        case .title: base = 28
        case .title2: base = 22
        case .title3: base = 20
        case .headline: base = 16
        case .subheadline: base = 14.5
        case .callout: base = 16
        case .footnote: base = 13
        case .caption: base = 12
        case .caption2: base = 11
        default: base = 17
        }
        let name: String
        switch weight {
        case .ultraLight: name = "Inter-Regular_Thin"
        case .thin: name = "Inter-Regular_ExtraLight"
        case .light: name = "Inter-Regular_Light"
        case .medium: name = "Inter-Regular_Medium"
        case .semibold: name = "Inter-Regular_SemiBold"
        case .bold: name = "Inter-Regular_Bold"
        case .heavy: name = "Inter-Regular_ExtraBold"
        case .black: name = "Inter-Regular_Black"
        default: name = "Inter-Regular"
        }
        return .custom(name, size: size ?? base, relativeTo: style)
    }
}

enum DisplayFormat {
    static func compactMoney(_ value: Decimal, currency: String) -> String {
        guard currency == "INR" else { return money(value, currency: currency) }
        if abs(value) >= 10_000_000 { return "₹\(decimal(value / 10_000_000)) Cr" }
        if abs(value) >= 100_000 { return "₹\(decimal(value / 100_000)) L" }
        return money(value, currency: currency)
    }
    static func money(_ value: Decimal, currency: String, fractionDigits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale(identifier: currency == "INR" ? "en_IN" : "en_US")
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    static func decimal(_ value: Decimal, digits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_IN")
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    static func age(_ date: Date, relativeTo now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
