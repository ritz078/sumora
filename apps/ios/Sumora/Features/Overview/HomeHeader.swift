import SwiftUI

struct HomeHeader:View {
 @Environment(PortfolioStore.self) private var store
 @Environment(AppDependencies.self) private var dependencies
 let snapshot:PortfolioSnapshot
 @Environment(AppPreferences.self) private var preferences
 private var attentionCount:Int { snapshot.connections.filter {$0.status == .attention}.count }
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
      Text("Private Wealth").font(.inter(.caption2,weight:.semibold,size:9)).foregroundStyle(HomeStyle.indigo)
       .padding(.horizontal,6).padding(.vertical,1).background(HomeStyle.indigo.opacity(0.06),in:Capsule())
       .overlay(Capsule().stroke(HomeStyle.indigo.opacity(0.10),lineWidth:1))
     }.lineLimit(1).minimumScaleFactor(0.8)
     Text("Ritesh Kumar").font(.inter(.headline,weight:.bold,size:19)).tracking(-0.475).lineLimit(1)
    }
    Spacer(minLength:0)
    HStack(spacing:6) {
     Button { preferences.hideBalances.toggle() } label: { Image(systemName: preferences.hideBalances ? "eye.slash" : "eye").resizable().scaledToFit().frame(width:18,height:18) }.accessibilityIdentifier("balanceVisibility").accessibilityLabel(preferences.hideBalances ? "Show balances" : "Hide balances").frame(width:36,height:36).background(HomeStyle.card,in:Circle()).overlay(Circle().stroke(HomeStyle.border,lineWidth:1))
     NavigationLink { ConnectionsView().toolbar(.visible,for:.navigationBar) } label: {
      Image(systemName:"bell").resizable().scaledToFit().frame(width:18,height:18).frame(width:36,height:36)
       .background(HomeStyle.card,in:Circle()).overlay(Circle().stroke(HomeStyle.border,lineWidth:1))
       .overlay(alignment:.topTrailing) {
        if attentionCount>0 { Text("\(attentionCount)").font(.inter(.caption2,weight:.bold,size:10)).foregroundStyle(.white).frame(minWidth:16,minHeight:16).background(Color.red,in:Circle()).overlay(Circle().stroke(.white,lineWidth:1)).offset(x:3,y:-3) }
       }
     }.accessibilityLabel("Account alerts").accessibilityIdentifier("homeAlerts")
    }.foregroundStyle(HomeStyle.ink)
   }.frame(minHeight:52)
   HStack(spacing:6) {
    Circle().fill(HomeStyle.muted).frame(width:6,height:6)
    let broker=snapshot.connections.first {$0.id == "zerodha"}
    Text("Zerodha feed synced \(time(broker?.lastSyncAt ?? snapshot.holdingsSyncAt))" + (broker?.status == .attention ? " · Token expired" : ""))
     .font(.inter(.caption2,size:11)).foregroundStyle(HomeStyle.secondary).lineLimit(1).truncationMode(.tail)
    Spacer(minLength:4)
    Button { Task { await store.refresh() } } label: {
     HStack(spacing:2) { Image(systemName:"arrow.triangle.2.circlepath").font(.system(size:11));Text(store.isRefreshing ? "Refreshing" : "Refresh").font(.inter(.caption2,weight:.medium,size:11)) }
    }.disabled(store.isRefreshing).foregroundStyle(HomeStyle.indigo).accessibilityIdentifier("homeRefresh")
   }.padding(.horizontal,8).frame(minHeight:19).padding(.bottom,4)
  }
 }
 private func time(_ date:Date)->String {let formatter=DateFormatter();formatter.timeZone=TimeZone(identifier:"Asia/Kolkata");formatter.dateFormat="HH:mm";return formatter.string(from:date)}
}
