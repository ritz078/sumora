import SwiftUI

enum HomeStyle {
 static let background = Color(uiColor:UIColor {$0.userInterfaceStyle == .dark ? .systemGroupedBackground : UIColor(red:242/255,green:242/255,blue:247/255,alpha:1)})
 static let card = Color(uiColor:.secondarySystemGroupedBackground)
 static let ink = DashboardStyle.ink
 static let secondary = Color(uiColor:UIColor {$0.userInterfaceStyle == .dark ? .secondaryLabel : UIColor(red:100/255,green:116/255,blue:139/255,alpha:1)})
 static let muted = Color(red:148/255,green:163/255,blue:184/255)
 static let border = Color.primary.opacity(0.04)
 static let fill = Color(uiColor:UIColor {$0.userInterfaceStyle == .dark ? .tertiarySystemGroupedBackground : UIColor(red:248/255,green:250/255,blue:252/255,alpha:0.7)})
 static let emerald = Color(red:16/255,green:185/255,blue:129/255)
 static let brightGreen = Color(red:52/255,green:211/255,blue:153/255)
 static let indigo = Color(red:79/255,green:70/255,blue:229/255)
 static func allocationColor(_ asset:AssetClass)->Color {
  switch asset {
  case .realEstate: Color(red:37/255,green:99/255,blue:235/255)
  case .indianEquity: emerald
  case .usEquity: indigo
  case .mutualFund: Color(red:245/255,green:158/255,blue:11/255)
  case .gold: muted
  case .fixedDeposit: Color(red:139/255,green:92/255,blue:246/255)
  case .bond: Color(red:14/255,green:165/255,blue:233/255)
  case .nps: Color(red:236/255,green:72/255,blue:153/255)
  }
 }
 static func title(_ asset:AssetClass)->String {
  switch asset {
  case .realEstate: "Real Estate"
  case .indianEquity: "Indian Stocks"
  case .usEquity: "US Stocks"
  case .mutualFund: "Mutual Funds"
  case .gold: "Gold & Bullion"
  case .fixedDeposit: "Fixed Deposits"
  case .bond: "Bonds"
  case .nps: "NPS"
  }
 }
}
extension View {
 func homeCard(padding amount:CGFloat = 20,cornerRadius:CGFloat = 16) -> some View {
  padding(amount).frame(maxWidth:.infinity,alignment:.leading)
   .background(HomeStyle.card,in:RoundedRectangle(cornerRadius:cornerRadius))
   .overlay(RoundedRectangle(cornerRadius:cornerRadius).stroke(HomeStyle.border,lineWidth:1))
   .shadow(color:.black.opacity(0.04),radius:4,y:2)
 }
}
struct HomeSignedMoney:View {
 @Environment(AppPreferences.self) private var preferences
 let amount:DecimalValue?
 var currency="INR"
 var body:some View {
  Text(preferences.hideBalances ? "••••" : amount.map { ($0.value >= 0 ? "+" : "−")+DisplayFormat.money(abs($0.value),currency:currency) } ?? "—")
   .lineLimit(1).minimumScaleFactor(0.65)
   .accessibilityLabel(preferences.hideBalances ? "Hidden return" : amount.map { ($0.value >= 0 ? "Gain " : "Loss ")+DisplayFormat.money(abs($0.value),currency:currency) } ?? "Return unavailable")
 }
}
