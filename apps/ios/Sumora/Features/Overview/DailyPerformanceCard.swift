import SwiftUI

struct DailyPerformanceCard:View {
 @Environment(AppPreferences.self) private var preferences
 let snapshot:PortfolioSnapshot
 private let classes:[AssetClass]=[.indianEquity,.usEquity,.mutualFund,.gold]
 var body:some View {
  VStack(alignment:.leading,spacing:0) {
   HStack(spacing:8) {
    Circle().fill(HomeStyle.brightGreen).frame(width:8,height:8)
    Text("DAILY PERFORMANCE").font(.inter(.caption2,weight:.semibold,size:11)).tracking(0.8).foregroundStyle(HomeStyle.muted)
   }.frame(height:14).padding(.bottom,12)
   let total=HomeDailyMetrics(snapshot:snapshot)
   HStack(alignment:.firstTextBaseline,spacing:8) {
    HomeSignedMoney(amount:total.gain,currency:snapshot.reportingCurrency).font(.inter(.largeTitle,weight:.bold,size:32)).tracking(-0.8)
    if let percent=total.percent {
     Text(preferences.hideBalances ? "••••" : "\(percent.value>=0 ? "+":"")\(DisplayFormat.decimal(percent.value))% today")
      .font(.inter(.caption2,weight:.semibold,size:12)).padding(.horizontal,8).padding(.vertical,2)
      .background(HomeStyle.emerald.opacity(0.10),in:Capsule()).overlay(Capsule().stroke(HomeStyle.emerald.opacity(0.20),lineWidth:1))
    } else { Text("Daily change unavailable").font(.inter(.caption2,size:11)).foregroundStyle(HomeStyle.muted).lineLimit(2) }
   }.foregroundStyle(preferences.hideBalances ? HomeStyle.muted:(total.gain?.value ?? 0)>=0 ? HomeStyle.brightGreen:.red).frame(minHeight:38).padding(.bottom,20)
   LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
    ForEach(classes) { asset in
     NavigationLink { HoldingsView(assetClass:asset).toolbar(.visible,for:.navigationBar).navigationTitle(HomeStyle.title(asset)).navigationBarTitleDisplayMode(.inline) } label: { performanceTile(asset) }
      .buttonStyle(.plain).accessibilityIdentifier("home-instrument-\(asset.rawValue)")
    }
   }
  }.padding(20).frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(.white)
   .background {
    RoundedRectangle(cornerRadius:16).fill(LinearGradient(stops:[.init(color:Color(red:11/255,green:19/255,blue:41/255),location:0),.init(color:Color(red:9/255,green:21/255,blue:43/255),location:0.5),.init(color:Color(red:13/255,green:30/255,blue:61/255),location:1)],startPoint:.topLeading,endPoint:.bottomTrailing))
     .overlay(alignment:.topTrailing) {Circle().fill(HomeStyle.indigo.opacity(0.10)).frame(width:144,height:144).blur(radius:24).offset(x:48,y:-48)}
     .overlay(alignment:.bottomLeading) {Circle().fill(HomeStyle.emerald.opacity(0.10)).frame(width:128,height:128).blur(radius:24).offset(x:-40,y:40)}
     .clipShape(RoundedRectangle(cornerRadius:16))
   }
   .overlay(RoundedRectangle(cornerRadius:16).stroke(Color(red:51/255,green:65/255,blue:85/255).opacity(0.5),lineWidth:1))
   .shadow(color:.black.opacity(0.12),radius:12,y:8)
 }
 private func performanceTile(_ asset:AssetClass)->some View {
  let metric=HomeDailyMetrics(snapshot:snapshot,asset:asset)
  return VStack(alignment:.leading,spacing:0) {
   HStack(spacing:4) {
    Text(asset == .indianEquity ? "Indian Equities" : asset == .usEquity ? "US Equities" : HomeStyle.title(asset)).font(.inter(.caption2,weight:.medium,size:11)).foregroundStyle(Color(red:203/255,green:213/255,blue:225/255)).lineLimit(1)
    Spacer(minLength:0)
    Text(preferences.hideBalances ? "••••" : metric.percent.map {($0.value>=0 ? "+":"")+DisplayFormat.decimal($0.value)+"%"} ?? "—")
     .font(.inter(.caption2,weight:.bold,size:10)).padding(.horizontal,6).padding(.vertical,2).background(HomeStyle.emerald.opacity(0.10),in:RoundedRectangle(cornerRadius:4))
     .foregroundStyle(preferences.hideBalances ? HomeStyle.muted:(metric.gain?.value ?? 0)>=0 ? HomeStyle.brightGreen:.red).fixedSize()
   }
   Spacer(minLength:8)
   HomeSignedMoney(amount:metric.gain,currency:snapshot.reportingCurrency).font(.inter(.subheadline,weight:.bold,size:14)).tracking(-0.35)
   Spacer(minLength:8)
   Rectangle().fill(Color(red:51/255,green:65/255,blue:85/255).opacity(0.4)).frame(height:1)
   HStack {
    Text("Holding").font(.inter(.caption2,size:10)).foregroundStyle(HomeStyle.secondary)
    Spacer(minLength:2)
    Text(preferences.hideBalances ? "••••" : metric.value.map {DisplayFormat.compactMoney($0.value,currency:snapshot.reportingCurrency)} ?? "—")
     .font(.inter(.caption2,weight:.medium,size:11)).foregroundStyle(Color(red:203/255,green:213/255,blue:225/255)).lineLimit(1).minimumScaleFactor(0.8)
   }.padding(.top,6)
  }.padding(12).frame(maxWidth:.infinity).frame(height:104,alignment:.leading)
   .background(Color(red:30/255,green:41/255,blue:59/255).opacity(0.6),in:RoundedRectangle(cornerRadius:12))
   .overlay(RoundedRectangle(cornerRadius:12).stroke(Color(red:51/255,green:65/255,blue:85/255).opacity(0.5),lineWidth:1))
 }
}
