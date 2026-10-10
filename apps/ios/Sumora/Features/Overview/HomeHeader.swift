import SwiftUI

struct HomeHeader:View {
 @Environment(PortfolioStore.self) private var store
 @Environment(AppDependencies.self) private var dependencies
 let snapshot:PortfolioSnapshot
 @Environment(AppPreferences.self) private var preferences
 private var greeting:String {
  var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:"Asia/Kolkata")!
  switch calendar.component(.hour,from:dependencies.demoDate) {
  case 0..<12: return "Good morning,"
  case 12..<17: return "Good afternoon,"
  default: return "Good evening,"
  }
 }
 var body:some View {
  VStack(spacing:16) {
   HStack(spacing:12) {
    NavigationLink { SettingsView().toolbar(.visible,for:.navigationBar) } label: {
     Text("RK").font(.inter(.subheadline,weight:.semibold,size:15)).tracking(-0.35)
      .foregroundStyle(.white).frame(width:44,height:44).background(Color(red:15/255,green:23/255,blue:42/255),in:Circle())
      .overlay(alignment:.bottomTrailing) { Circle().fill(HomeStyle.emerald).frame(width:12,height:12).overlay(Circle().stroke(.white,lineWidth:1)) }
    }.accessibilityLabel("Profile and settings").accessibilityIdentifier("homeSettings")
    VStack(alignment:.leading,spacing:2) {
     HStack(spacing:6) {
      Text(greeting).font(.inter(.caption2,weight:.medium,size:11)).foregroundStyle(HomeStyle.secondary).tracking(-0.25)
     }.lineLimit(1).minimumScaleFactor(0.8)
     Text("Ritesh Kumar").font(.inter(.headline,weight:.bold,size:19)).tracking(-0.475).lineLimit(1)
    }
    Spacer(minLength:0)
    HStack(spacing:6) {
     Button { preferences.hideBalances.toggle() } label: { Image(systemName: preferences.hideBalances ? "eye.slash" : "eye").resizable().scaledToFit().frame(width:18,height:18) }.accessibilityIdentifier("balanceVisibility").accessibilityLabel(preferences.hideBalances ? "Show balances" : "Hide balances").frame(width:36,height:36).background(HomeStyle.card,in:Circle()).overlay(Circle().stroke(HomeStyle.border,lineWidth:1))
     Button {
      Task { await dependencies.toggleDemoPortfolio() }
     } label: {
      HStack(spacing:4) {
       Image(systemName:"flask").font(.system(size:15))
       Text("Demo").font(.inter(.caption2,weight:.semibold,size:11)).tracking(-0.25)
       if !dependencies.isLivePortfolio { Circle().fill(HomeStyle.indigo).frame(width:6,height:6) }
      }.padding(.horizontal,10).frame(height:36)
       .foregroundStyle(HomeStyle.indigo).background(HomeStyle.indigo.opacity(dependencies.isLivePortfolio ? 0.04 : 0.10),in:Capsule())
       .overlay(Capsule().stroke(HomeStyle.border,lineWidth:1))
     }.accessibilityLabel("Portfolio data source").accessibilityValue(dependencies.isLivePortfolio ? "Linked portfolio" : "Demo active").accessibilityIdentifier("homeDemo")
    }.foregroundStyle(HomeStyle.ink)
   }.frame(minHeight:52)
   let broker=snapshot.connections.first {$0.id == "zerodha"}
   let needsAttention=broker?.status == .attention
   HStack(spacing:8) {
    HStack(spacing:6) {
     Circle().fill(needsAttention ? Color.orange : HomeStyle.emerald).frame(width:8,height:8)
     Text("Zerodha").font(.inter(.caption2,weight:.medium,size:11)).foregroundStyle(HomeStyle.ink).tracking(-0.25)
    }.fixedSize()
    Text("•").foregroundStyle(HomeStyle.muted.opacity(0.5))
    Text("\(time(broker?.lastSyncAt ?? snapshot.holdingsSyncAt)) sync")
     .font(.inter(.caption2,size:11)).foregroundStyle(HomeStyle.muted).lineLimit(1)
    if needsAttention {
     Text("Token expired").font(.inter(.caption2,weight:.medium,size:10)).foregroundStyle(Color(red:180/255,green:83/255,blue:9/255))
      .padding(.horizontal,6).padding(.vertical,2).background(Color.orange.opacity(0.10),in:RoundedRectangle(cornerRadius:4))
      .overlay(RoundedRectangle(cornerRadius:4).stroke(Color.orange.opacity(0.2),lineWidth:1)).fixedSize()
    }
    Spacer(minLength:0)
    Button { Task { await store.refresh() } } label: {
     HStack(spacing:4) { Image(systemName:"arrow.triangle.2.circlepath").font(.system(size:11));Text(store.isRefreshing ? "Refreshing" : "Refresh").font(.inter(.caption2,weight:.medium,size:11)) }
      .padding(.horizontal,10).padding(.vertical,4).background(HomeStyle.indigo.opacity(0.06),in:RoundedRectangle(cornerRadius:8))
      .overlay(RoundedRectangle(cornerRadius:8).stroke(HomeStyle.indigo.opacity(0.15),lineWidth:1))
    }.disabled(store.isRefreshing).foregroundStyle(HomeStyle.indigo).accessibilityIdentifier("homeRefresh").fixedSize()
   }.padding(.horizontal,12).padding(.vertical,8)
    .background(HomeStyle.card.opacity(0.7),in:RoundedRectangle(cornerRadius:12))
    .overlay(RoundedRectangle(cornerRadius:12).stroke(HomeStyle.border,lineWidth:1))
  }
 }
 private func time(_ date:Date)->String {let formatter=DateFormatter();formatter.timeZone=TimeZone(identifier:"Asia/Kolkata");formatter.dateFormat="HH:mm";return formatter.string(from:date)}
}
