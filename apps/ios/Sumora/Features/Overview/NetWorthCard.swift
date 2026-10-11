import SwiftUI

struct NetWorthCard:View {
 @Environment(AppPreferences.self) private var preferences
 @Environment(AppDependencies.self) private var dependencies
 let snapshot:PortfolioSnapshot
 private var costKnown:Bool { snapshot.costBasisKnown ?? snapshot.holdings.allSatisfy {$0.costBasisKnown != false} }
 var body:some View {
  VStack(alignment:.leading,spacing:0) {
   HStack(spacing:4) {
    Text("ESTIMATED NET WORTH").font(.appFont(.caption2,weight:.semibold,size:11)).tracking(0.8).foregroundStyle(HomeStyle.secondary).lineLimit(1).minimumScaleFactor(0.8)
    Spacer(minLength:4)
    ReturnBadge(percent:snapshot.gainPercent,label:"All-time")
   }.frame(minHeight:18)
   MoneyText(amount:snapshot.value,currency:snapshot.reportingCurrency)
    .font(.appFont(.largeTitle,weight:.bold,size:32)).tracking(-0.8).padding(.vertical,8)
    .accessibilityIdentifier("portfolioValue")
   Rectangle().fill(HomeStyle.border).frame(height:1).padding(.top,4)
   ViewThatFits(in:.horizontal) {
    HStack(spacing:8) { invested;Spacer(minLength:4);overallGain }
    VStack(alignment:.leading,spacing:8) { invested;overallGain }
   }.padding(.top,10)
   if snapshot.coverage != .complete {
    Text(snapshot.coverage == .partial ? "Partial valuation · Unpriced holdings are excluded." : "Prices unavailable · Your recorded holdings are retained.")
     .font(.appFont(.caption2, size: 10)).foregroundStyle(.orange).padding(.top, 10)
   }
   if dependencies.demoDate.timeIntervalSince(snapshot.capturedAt) > 86400 {
    Text("Outdated snapshot · Updated " + DisplayFormat.age(snapshot.capturedAt, relativeTo: dependencies.demoDate))
     .font(.appFont(.caption2, size: 10)).foregroundStyle(.orange).padding(.top, 6)
   }
  }.frame(minHeight:115,alignment:.center).homeCard()
 }
 private var invested:some View {
  HStack(spacing:6) {
   Text(costKnown ? "Invested" : "Known invested").foregroundStyle(HomeStyle.muted)
   MoneyText(amount:costKnown ? snapshot.invested:snapshot.coveredInvested,currency:snapshot.reportingCurrency).fontWeight(.semibold).foregroundStyle(HomeStyle.ink.opacity(0.85))
  }.font(.appFont(.caption,weight:.medium,size:12))
 }
 private var overallGain:some View {
  HStack(spacing:4) {
   Text("Overall Gain").foregroundStyle(HomeStyle.muted)
   HomeSignedMoney(amount:snapshot.gain,currency:snapshot.reportingCurrency).fontWeight(.semibold).foregroundStyle(preferences.hideBalances ? HomeStyle.secondary:(snapshot.gain?.value ?? 0)>=0 ? DashboardStyle.positive:.red)
  }.font(.appFont(.caption,weight:.medium,size:12))
 }
}

struct ReturnBadge:View {
 @Environment(AppPreferences.self) private var preferences
 let percent:DecimalValue?
 var label=""
 var body:some View {
  HStack(spacing:4) {
   if !preferences.hideBalances,let percent { Image(systemName:percent.value>=0 ? "arrow.up":"arrow.down").font(.system(size:11,weight:.semibold)) }
   Text(preferences.hideBalances ? "••••" : percent.map { ($0.value>=0 ? "+":"")+DisplayFormat.decimal($0.value)+"%" } ?? "—").font(.appFont(.caption2,weight:.semibold,size:11))
   if !label.isEmpty {Text(label).font(.appFont(.caption2,size:10)).opacity(0.7)}
  }.foregroundStyle(preferences.hideBalances || percent == nil ? HomeStyle.secondary:(percent?.value ?? 0)>=0 ? DashboardStyle.positive:.red)
   .padding(.horizontal,10).padding(.vertical,2)
   .background((percent == nil ? Color.secondary:HomeStyle.emerald).opacity(0.07),in:Capsule())
   .overlay(Capsule().stroke((percent == nil ? Color.secondary:HomeStyle.emerald).opacity(0.20),lineWidth:1)).fixedSize()
 }
}
