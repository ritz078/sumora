import SwiftUI

/// Gold-specific presentation of recorded holdings; benchmark prices are not sell quotes.
struct GoldView: View {
 @Environment(PortfolioStore.self) private var store
 @Environment(AppDependencies.self) private var dependencies
 @Environment(AppPreferences.self) private var preferences
 @Environment(\.dismiss) private var dismiss
 @State private var history = HomeHistoryConnection(assetClass:.gold)
 @State private var ascending = false
 private var holdings: [Holding] { store.snapshot?.holdings.filter { $0.assetClass == .gold } ?? [] }
 private var value: DecimalValue? { !holdings.isEmpty && holdings.allSatisfy { $0.value != nil } ? DecimalValue(holdings.reduce(0) { $0 + $1.value!.value }) : nil }
 private var costKnown: Bool { !holdings.isEmpty && holdings.allSatisfy { $0.costBasisKnown != false } }
 private var cost: DecimalValue { DecimalValue(holdings.reduce(0) { $0 + ($1.costBasisKnown == false ? 0 : $1.invested.value) }) }
 private var gain: DecimalValue? { costKnown ? value.map { DecimalValue($0.value - cost.value) } : nil }
 private var percent: DecimalValue? { cost.value > 0 ? gain.map { DecimalValue($0.value / cost.value * 100) } : nil }
 private var scope: String { "\(dependencies.isLivePortfolio):\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "demo")" }
 private var sorted: [Holding] {
  holdings.sorted { left,right in
   switch (left.value?.value,right.value?.value) {
   case let (.some(a),.some(b)) where a != b: return ascending ? a < b : a > b
   case (.some,.none): return true
   case (.none,.some): return false
   default: return left.id < right.id
   }
  }
 }
 var body: some View {
  ScrollView {
   VStack(spacing:14) {
    if store.snapshot == nil { ProgressView("Loading gold…").goldCard() }
    else {
     valuation
     if let snapshot = store.snapshot { daily(snapshot) }
     HomeTrajectoryCard(history:dependencies.isLivePortfolio ? history.history : demoHistory,referenceDate:dependencies.demoDate,currency:currency,errorMessage:history.errorMessage,title:"Gold & Bullion Trajectory",instrumentStyle:true,roundedInstrumentCallout:true,goldStyle:true)
     positions
     footer
    }
   }.padding(16).padding(.bottom,24)
  }.background(GoldStyle.background).foregroundStyle(GoldStyle.ink)
   .safeAreaInset(edge:.top,spacing:0) { header }
   .toolbar(.hidden,for:.navigationBar).preference(key:InstrumentPageKey.self,value:true)
   .refreshable { await refresh() }
   .task(id:scope) {
    history.configure(address:dependencies.zerodha.address,token:dependencies.isLivePortfolio ? dependencies.zerodha.sessionToken : nil)
    await history.refresh()
   }
 }
 private var currency: String { store.snapshot?.reportingCurrency ?? "INR" }
 private var header: some View {
  HStack {
   Button { dismiss() } label: { Image(systemName:"chevron.left").font(.system(size:17,weight:.semibold)).frame(width:32,height:32) }.accessibilityLabel("Go back").accessibilityIdentifier("goldBack")
   Spacer(minLength:8)
   HStack(spacing:8) {
    Circle().fill(GoldStyle.amber).frame(width:8,height:8).overlay(Circle().stroke(GoldStyle.amber.opacity(0.2),lineWidth:4))
    Text("Gold & Bullion").font(.inter(.headline,weight:.semibold,size:16)).tracking(-0.3)
   }.foregroundStyle(GoldStyle.ink)
   Spacer(minLength:8)
   Button { Task { await refresh() } } label: {
    Group { if store.isRefreshing { ProgressView() } else { Image(systemName:"arrow.triangle.2.circlepath").font(.system(size:18)) } }.frame(width:32,height:32)
   }.disabled(store.isRefreshing).accessibilityLabel("Refresh gold values").accessibilityIdentifier("goldRefresh")
  }.foregroundStyle(GoldStyle.secondary).padding(.horizontal,16).padding(.vertical,12).background(HomeStyle.card)
   .overlay(alignment:.bottom) { Rectangle().fill(GoldStyle.border).frame(height:1) }
 }
 private var valuation: some View {
  VStack(alignment:.leading,spacing:8) {
   HStack {
    Text("VALUATION").font(.inter(.caption2,weight:.semibold,size:11)).tracking(0.8).foregroundStyle(GoldStyle.secondary)
    Spacer(minLength:4);ReturnBadge(percent:percent,label:"All-time")
   }
   MoneyText(amount:value,currency:currency).font(.inter(.largeTitle,weight:.bold,size:32)).tracking(-0.6).accessibilityIdentifier("goldValue")
   Rectangle().fill(GoldStyle.border).frame(height:1).padding(.top,4)
   HStack(alignment:.top,spacing:8) {
    VStack(alignment:.leading,spacing:2) {
     Text(costKnown ? "Invested" : "Known invested").foregroundStyle(GoldStyle.secondary)
     MoneyText(amount:cost,currency:currency).fontWeight(.semibold)
    }.frame(maxWidth:.infinity,alignment:.leading)
    VStack(alignment:.leading,spacing:2) {
     Text("Gain").foregroundStyle(GoldStyle.secondary)
     HomeSignedMoney(amount:gain,currency:currency).fontWeight(.semibold).foregroundStyle(gainColor(gain))
    }.frame(maxWidth:.infinity,alignment:.leading)
   }.font(.inter(.caption,size:13)).padding(.top,4)
   if value == nil && !holdings.isEmpty { Text("Some prices are unavailable. Recorded holdings are retained.").font(.inter(.caption2,size:11)).foregroundStyle(GoldStyle.secondary) }
  }.goldCard()
 }
 private func daily(_ snapshot:PortfolioSnapshot) -> some View {
  let metric = HomeDailyMetrics(snapshot:snapshot,asset:.gold)
  return VStack(alignment:.leading,spacing:6) {
   HStack(spacing:6) {
    Circle().fill(HomeStyle.brightGreen).frame(width:6,height:6)
    Text("DAILY PERFORMANCE").font(.inter(.caption2,weight:.semibold,size:11)).tracking(0.6).foregroundStyle(Color.white.opacity(0.8))
    Spacer(minLength:4)
    if let percent = metric.percent {
     Text(preferences.hideBalances ? "••••" : signed(percent.value)+"% today").font(.inter(.caption2,weight:.semibold,size:11)).lineLimit(1).fixedSize()
      .foregroundStyle(preferences.hideBalances || (metric.gain?.value ?? 0) >= 0 ? HomeStyle.brightGreen : Color.red)
      .padding(.horizontal,8).padding(.vertical,2).background(HomeStyle.emerald.opacity(0.15),in:Capsule()).overlay(Capsule().stroke(HomeStyle.emerald.opacity(0.3),lineWidth:1))
    }
   }
   HomeSignedMoney(amount:metric.gain,currency:currency).font(.inter(.title,weight:.bold,size:26)).tracking(-0.5).foregroundStyle(.white).accessibilityIdentifier("goldDailyGain")
   Label(metric.gain == nil ? "Daily baseline unavailable for recorded gold" : "Price movement on recorded gold holdings",systemImage:"info.circle")
    .font(.inter(.caption2,size:11)).foregroundStyle(HomeStyle.muted).padding(.top,4)
  }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
   .background {
    GeometryReader { geometry in
     ZStack(alignment:.topTrailing) {
     LinearGradient(colors:[Color(red:18/255,green:24/255,blue:38/255),Color(red:26/255,green:34/255,blue:52/255),Color(red:15/255,green:20/255,blue:31/255)],startPoint:.topLeading,endPoint:.bottomTrailing)
     Circle().fill(GoldStyle.amber.opacity(0.1)).frame(width:128,height:128).blur(radius:32).offset(x:32,y:-32)
     }.frame(width:geometry.size.width,height:geometry.size.height).clipped()
    }.clipShape(RoundedRectangle(cornerRadius:8))
   }.overlay(RoundedRectangle(cornerRadius:8).stroke(Color(red:43/255,green:53/255,blue:76/255),lineWidth:1)).shadow(color:.black.opacity(0.08),radius:4,y:2)
 }
 private var positions: some View {
  VStack(spacing:0) {
   HStack {
    VStack(alignment:.leading,spacing:3) {
     Text("Holdings").font(.inter(.headline,weight:.semibold,size:16))
     Text("\(holdings.count) Instruments · Recorded gold holdings").font(.inter(.caption2,size:11.5)).foregroundStyle(GoldStyle.secondary)
    }
    Spacer(minLength:4)
    Menu {
     Button("Value: High to Low") { ascending = false }
     Button("Value: Low to High") { ascending = true }
    } label: {
     HStack(spacing:4) { Text("Sort: Value");Image(systemName:"chevron.down").font(.system(size:10)) }.font(.inter(.caption2,weight:.medium,size:11)).padding(.horizontal,8).padding(.vertical,4).background(GoldStyle.fill,in:RoundedRectangle(cornerRadius:4)).overlay(RoundedRectangle(cornerRadius:4).stroke(GoldStyle.border,lineWidth:1))
    }.foregroundStyle(GoldStyle.secondary).accessibilityLabel("Sort gold holdings")
   }.padding(.horizontal,16).padding(.vertical,12)
   Rectangle().fill(GoldStyle.border).frame(height:1)
   ForEach(sorted) { holding in
    row(holding).accessibilityElement(children:.combine).accessibilityIdentifier("gold-holding-\(holding.id)")
    if holding.id != sorted.last?.id { Rectangle().fill(GoldStyle.border).frame(height:1) }
   }
   if holdings.isEmpty { Text("No gold holdings recorded yet").font(.inter(.caption,size:13)).foregroundStyle(GoldStyle.secondary).frame(maxWidth:.infinity).padding(24) }
  }.background(HomeStyle.card,in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(GoldStyle.border,lineWidth:1)).shadow(color:.black.opacity(0.04),radius:1,y:1)
 }
 private func row(_ holding:Holding) -> some View {
  let isSGB = holding.symbol.uppercased().hasPrefix("SGB") || holding.name.localizedCaseInsensitiveContains("sovereign gold")
  let isGullak = holding.accountID == "gullak"
  let tag = isSGB ? holding.symbol : isGullak ? "GULLAK" : holding.symbol == "DIGITAL_GOLD" ? "DIGITAL GOLD" : "BULLION"
  let grams = ["grams","gram","g"].contains(holding.unit.lowercased())
  return HStack(spacing:8) {
   VStack(alignment:.leading,spacing:4) {
    HStack(spacing:6) {
     Text(holding.name).font(.inter(.caption,weight:.semibold,size:13.5)).lineLimit(1).truncationMode(.tail)
     Text(tag).font(.inter(.caption2,weight:.semibold,size:9.5)).lineLimit(1).truncationMode(.tail).padding(.horizontal,4).padding(.vertical,1)
      .foregroundStyle(isSGB ? Color(red:120/255,green:53/255,blue:15/255) : GoldStyle.secondary)
      .background(isSGB ? GoldStyle.amber.opacity(0.14) : GoldStyle.fill,in:RoundedRectangle(cornerRadius:2)).overlay(RoundedRectangle(cornerRadius:2).stroke(isSGB ? GoldStyle.amber.opacity(0.3) : GoldStyle.border,lineWidth:1)).layoutPriority(1)
    }
    HStack(spacing:3) {
     Text("\(DisplayFormat.decimal(holding.quantity.value)) \(holding.unit) ·")
     MoneyText(amount:holding.quote,currency:holding.quoteCurrency)
     if grams { Text("/g").padding(.leading,-3) }
    }.font(.inter(.caption2,size:11.5)).foregroundStyle(GoldStyle.secondary).lineLimit(1).minimumScaleFactor(0.85)
   }.frame(maxWidth:.infinity,alignment:.leading)
   VStack(alignment:.trailing,spacing:3) {
    MoneyText(amount:holding.value,currency:currency).font(.inter(.caption,weight:.semibold,size:14))
    Text(returnLabel(holding)).font(.inter(.caption2,weight:.semibold,size:11)).foregroundStyle(gainColor(holding.costBasisKnown == false ? nil : holding.gain)).lineLimit(1)
   }.fixedSize(horizontal:true,vertical:false)
  }.padding(14)
 }
 private func returnLabel(_ holding:Holding) -> String {
  guard !preferences.hideBalances else { return "••••" }
  guard holding.costBasisKnown != false,holding.value != nil,let gain=holding.gain,let percent=holding.gainPercent else { return "Return unavailable" }
  return signed(percent.value)+"% ("+(gain.value >= 0 ? "+" : "−")+DisplayFormat.compactMoney(abs(gain.value),currency:currency)+")"
 }
 private var footer: some View {
  VStack(alignment:.leading,spacing:6) {
   Label("Sync baseline: Recorded quantities remain unchanged while available gold prices update daily.",systemImage:"checkmark.shield")
   Label(dependencies.isLivePortfolio ? "Recorded account balances · Bullion uses the IBJA daily benchmark via Snapdata, not a redemption quote." : "Sample portfolio · Illustrative values, not live prices.",systemImage:"building.columns")
  }.font(.inter(.caption2,size:10.5)).foregroundStyle(GoldStyle.secondary.opacity(0.8)).lineSpacing(3).padding(.horizontal,4).padding(.top,8)
 }
 private var demoHistory:[HistoryPoint] {
  guard let first=holdings.first else { return [] }
  let maps=holdings.map { Dictionary($0.history.map { ($0.date,$0.value.value) },uniquingKeysWith:{ _,new in new }) }
  return first.history.compactMap { point in
   let values=maps.compactMap { $0[point.date] }
   return values.count == holdings.count ? HistoryPoint(date:point.date,value:DecimalValue(values.reduce(0,+))) : nil
  }.sorted { $0.date < $1.date }
 }
 private func refresh() async { await store.refresh();await history.refresh() }
 private func signed(_ value:Decimal) -> String { (value >= 0 ? "+" : "")+DisplayFormat.decimal(value) }
 private func gainColor(_ value:DecimalValue?) -> Color { preferences.hideBalances || value == nil ? GoldStyle.secondary : value!.value >= 0 ? DashboardStyle.positive : .red }
}

private enum GoldStyle {
 static let amber=Color(red:245/255,green:158/255,blue:11/255)
 static let background=Color(uiColor:UIColor { $0.userInterfaceStyle == .dark ? .systemGroupedBackground : UIColor(red:247/255,green:249/255,blue:251/255,alpha:1) })
 static let ink=Color(uiColor:.label)
 static let secondary=Color(uiColor:UIColor { $0.userInterfaceStyle == .dark ? .secondaryLabel : UIColor(red:86/255,green:94/255,blue:116/255,alpha:1) })
 static let border=Color.primary.opacity(0.08)
 static let fill=Color(uiColor:.tertiarySystemGroupedBackground)
}
private extension View {
 func goldCard() -> some View {
  padding(16).frame(maxWidth:.infinity,alignment:.leading).background(HomeStyle.card,in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(GoldStyle.border,lineWidth:1)).shadow(color:.black.opacity(0.04),radius:1,y:1)
 }
}
