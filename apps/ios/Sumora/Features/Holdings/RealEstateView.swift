import SwiftUI

struct PropertyValuation {
 let properties: [PropertyEntry]
 var value: DecimalValue { DecimalValue(properties.reduce(0) { $0 + $1.estimatedValue.value }) }
 var cost: DecimalValue { DecimalValue(properties.reduce(0) { $0 + ($1.purchaseCost?.value ?? 0) }) }
 var costKnown: Bool { !properties.isEmpty && properties.allSatisfy { $0.purchaseCost != nil } }
 var gain: DecimalValue? { costKnown ? DecimalValue(value.value - cost.value) : nil }
 var percent: DecimalValue? { cost.value > 0 ? gain.map { DecimalValue($0.value / cost.value * 100) } : nil }
}

struct RealEstateView: View {
 @Environment(PortfolioStore.self) private var store
 @Environment(AppDependencies.self) private var dependencies
 @Environment(AppPreferences.self) private var preferences
 @Environment(\.dismiss) private var dismiss
 @State private var history = HomeHistoryConnection(assetClass:.realEstate)
 @State private var editing: PropertyDraft?
 @State private var descending = true
 private var scope: String { "\(dependencies.isLivePortfolio):\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "demo")" }
 private var editorScope: String { "\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "signed-out")" }
 private var properties: [PropertyEntry] { store.snapshot?.holdings.filter { $0.assetClass == .realEstate }.compactMap(\.propertyTerms) ?? [] }
 private var valuation: PropertyValuation { PropertyValuation(properties:properties) }
 private var sorted: [PropertyEntry] { properties.sorted { $0.estimatedValue.value == $1.estimatedValue.value ? $0.id < $1.id : descending ? $0.estimatedValue.value > $1.estimatedValue.value : $0.estimatedValue.value < $1.estimatedValue.value } }
 var body: some View {
  ScrollView {
   VStack(spacing:16) {
    if store.snapshot == nil { ProgressView("Loading properties…").homeCard() }
    else if properties.isEmpty { emptyState }
    else {
     summary
     baseline
     HomeTrajectoryCard(history:dependencies.isLivePortfolio ? history.history : demoHistory,referenceDate:dependencies.demoDate,currency:"INR",errorMessage:history.errorMessage,title:"Real Estate Trajectory",instrumentStyle:true,roundedInstrumentCallout:true,showsPeriodSelector:false)
     registry
    }
    VStack(spacing:6) {
     Text("Sync baseline: Values remain unchanged until manually edited")
     Text("Net worth reflects the full property valuation. Removing a property does not create cash proceeds.").font(.appFont(.caption2,size:10))
    }.font(.appFont(.caption2,size:11)).foregroundStyle(HomeStyle.muted).multilineTextAlignment(.center).padding(.horizontal,8).padding(.vertical,8)
   }.padding(16).padding(.bottom,24)
  }.background(HomeStyle.background).foregroundStyle(HomeStyle.ink)
   .safeAreaInset(edge:.top,spacing:0) { header }
   .toolbar(.hidden,for:.navigationBar).preference(key:InstrumentPageKey.self,value:true)
   .refreshable { await store.refresh(); await history.refresh() }
   .task(id:scope) {
    history.configure(address:dependencies.zerodha.address,token:dependencies.isLivePortfolio ? dependencies.zerodha.sessionToken : nil)
    dependencies.properties.configure(address:dependencies.zerodha.address,token:dependencies.zerodha.sessionToken)
    await history.refresh()
   }
   .onChange(of:scope) { _,_ in editing = nil }
   .sheet(item:$editing) { draft in PropertyEditor(id:draft.id,property:draft.property,scope:editorScope) }
 }
 private var header: some View {
  HStack {
   Button { dismiss() } label: { Image(systemName:"chevron.left").font(.system(size:17,weight:.semibold)).frame(width:36,height:36) }.accessibilityLabel("Go back").accessibilityIdentifier("realEstateBack")
   Spacer()
   Text("Real Estate").font(.appFont(.headline,weight:.bold,size:17)).tracking(-0.425).foregroundStyle(HomeStyle.ink)
   Spacer()
   Button { add() } label: { Image(systemName:"plus.circle").font(.system(size:21,weight:.semibold)).frame(width:36,height:36) }.accessibilityLabel("Add property").accessibilityIdentifier("realEstateAdd")
  }.foregroundStyle(HomeStyle.indigo).padding(.horizontal,8).padding(.vertical,8).background(HomeStyle.background.opacity(0.95))
   .overlay(alignment:.bottom) { Rectangle().fill(HomeStyle.border).frame(height:1) }
 }
 private var summary: some View {
  VStack(alignment:.leading,spacing:12) {
   HStack {
    Text("VALUATION").font(.appFont(.caption2,weight:.semibold,size:11)).tracking(0.8).foregroundStyle(HomeStyle.muted)
    Spacer(minLength:4);ReturnBadge(percent:valuation.percent,label:"All-time")
   }
   MoneyText(amount:valuation.value).font(.appFont(.largeTitle,weight:.bold,size:32)).tracking(-0.8).accessibilityIdentifier("realEstateValue")
   Text("Total portfolio asset value across \(properties.count) properties").font(.appFont(.caption2,size:11)).foregroundStyle(HomeStyle.muted)
   Rectangle().fill(HomeStyle.border).frame(height:1).padding(.vertical,6)
   HStack(alignment:.top) {
    VStack(alignment:.leading,spacing:2) {
     Text(valuation.costKnown ? "Invested Cost" : "Known Invested Cost").foregroundStyle(HomeStyle.muted)
     MoneyText(amount:valuation.cost).fontWeight(.semibold)
    }
    Spacer(minLength:8)
    VStack(alignment:.trailing,spacing:2) {
     Text("Unrealized Gain").foregroundStyle(HomeStyle.muted)
     HomeSignedMoney(amount:valuation.gain).fontWeight(.semibold).foregroundStyle(valuation.gain.map { $0.value < 0 ? Color.red : DashboardStyle.positive } ?? HomeStyle.secondary)
    }
   }.font(.appFont(.caption,size:12))
  }.homeCard()
 }
 private var baseline: some View {
  VStack(alignment:.leading,spacing:12) {
   HStack(spacing:8) {
    Circle().fill(Color.purple).frame(width:8,height:8)
    Text("VALUATION BASELINE").font(.appFont(.caption2,weight:.semibold,size:10)).tracking(0.8).foregroundStyle(Color.purple.opacity(0.8))
    Spacer(minLength:0)
    Text("Manual Registry").font(.appFont(.caption2,size:10)).padding(.horizontal,8).padding(.vertical,3).background(.white.opacity(0.1),in:Capsule())
   }
   VStack(alignment:.leading,spacing:6) {
    Text("Stable Periodic Valuation").font(.appFont(.headline,weight:.bold,size:17)).tracking(-0.4)
    Text("Net worth contribution reflects manual appraisal values").font(.appFont(.caption,size:12)).foregroundStyle(.white.opacity(0.7))
   }
   Rectangle().fill(.white.opacity(0.08)).frame(height:1)
   Label("Values remain static until edited · No automated market ticks",systemImage:"info.circle").font(.appFont(.caption2,size:11)).foregroundStyle(.white.opacity(0.6))
  }.padding(20).foregroundStyle(.white).frame(maxWidth:.infinity,alignment:.leading)
   .background(LinearGradient(colors:[Color(red:15/255,green:23/255,blue:42/255),Color(red:30/255,green:27/255,blue:75/255)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:16))
   .shadow(color:.black.opacity(0.08),radius:4,y:2)
 }
 private var registry: some View {
  VStack(spacing:16) {
   HStack {
    Circle().fill(Color.purple).frame(width:8,height:8)
    VStack(alignment:.leading,spacing:4) {
     Text("Properties").font(.appFont(.headline,weight:.bold,size:16))
     Text("\(properties.count) Assets").font(.appFont(.caption2,size:11)).foregroundStyle(HomeStyle.muted)
    }
    Spacer()
    Menu {
     Button("Value: High to Low") { descending = true }
     Button("Value: Low to High") { descending = false }
    } label: { HStack(spacing:6) { Text("Sort: Value");Image(systemName:"chevron.down") }.font(.appFont(.caption2,size:11)).foregroundStyle(HomeStyle.secondary).padding(8).background(HomeStyle.fill,in:RoundedRectangle(cornerRadius:6)) }.accessibilityLabel("Sort properties")
   }
   ForEach(sorted) { property in
    Button { edit(property) } label: { propertyCard(property) }.buttonStyle(.plain).accessibilityIdentifier("property-card-\(property.id)")
   }
   Button { add() } label: {
    Label("Add New Real Estate Property",systemImage:"plus.circle").font(.appFont(.caption,weight:.semibold,size:12)).frame(maxWidth:.infinity).padding(.vertical,10)
     .background(HomeStyle.indigo.opacity(0.025),in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(HomeStyle.indigo.opacity(0.2),style:StrokeStyle(lineWidth:1,dash:[3,3])))
   }.foregroundStyle(HomeStyle.indigo).accessibilityIdentifier("add-property")
  }.homeCard()
 }
 private func propertyCard(_ property: PropertyEntry) -> some View {
  let metrics = PropertyValuation(properties:[property])
  return VStack(alignment:.leading,spacing:16) {
   HStack {
    Text(property.name).font(.appFont(.headline,weight:.bold,size:14)).lineLimit(1).truncationMode(.tail)
    Spacer(minLength:4);Image(systemName:"chevron.right").font(.system(size:12,weight:.bold)).foregroundStyle(HomeStyle.muted)
   }
   HStack(alignment:.firstTextBaseline,spacing:8) {
    MoneyText(amount:metrics.value).font(.appFont(.title3,weight:.bold,size:20)).tracking(-0.5)
    Spacer(minLength:0)
    if let percent = metrics.percent {
     Text(preferences.hideBalances ? "••••" : "\(percent.value >= 0 ? "+" : "")\(DisplayFormat.decimal(percent.value))% (\(metrics.gain!.value >= 0 ? "+" : "−")\(DisplayFormat.money(abs(metrics.gain!.value),currency:"INR")))")
      .font(.appFont(.caption2,weight:.semibold,size:10)).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(percent.value >= 0 ? DashboardStyle.positive : .red).padding(.horizontal,6).padding(.vertical,3).background(HomeStyle.emerald.opacity(0.07),in:RoundedRectangle(cornerRadius:4))
    }
   }
   Rectangle().fill(HomeStyle.border).frame(height:1)
   ViewThatFits(in:.horizontal) {
    HStack(spacing:6) { propertyCost(property);Text("·");Text("Valued: \(valuationDate(property.valuationDate))") }
    VStack(alignment:.leading,spacing:4) { propertyCost(property);Text("Valued: \(valuationDate(property.valuationDate))") }
   }.font(.appFont(.caption2,size:10)).foregroundStyle(HomeStyle.secondary)
  }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(HomeStyle.fill,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(HomeStyle.border,lineWidth:1))
 }
 private func valuationDate(_ raw:String) -> String {
  guard let date=PropertyInput.dateFormatter.date(from:raw) else { return raw }
  let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_IN");formatter.timeZone=TimeZone(identifier:"Asia/Kolkata");formatter.dateFormat="dd MMM yyyy";return formatter.string(from:date)
 }
 private func propertyCost(_ property:PropertyEntry) -> some View {
  HStack(spacing:3) { Text("Cost:");MoneyText(amount:property.purchaseCost) }
 }
 private var emptyState: some View {
  VStack(spacing:20) {
   Image(systemName:"building.2.fill").font(.system(size:30)).foregroundStyle(HomeStyle.indigo).frame(width:80,height:80).background(HomeStyle.background,in:RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(HomeStyle.indigo.opacity(0.2),lineWidth:1)).padding(.top,4)
   VStack(spacing:8) {
    Text("No Real Estate Assets Recorded").font(.appFont(.title3,weight:.bold,size:20)).multilineTextAlignment(.center).accessibilityIdentifier("realEstateEmpty")
    Text("Sumora tracks land, residential, and commercial properties via manual appraisal. Real estate values are static and do not fluctuate with intraday market ticks.").font(.appFont(.caption,size:13)).foregroundStyle(HomeStyle.secondary).multilineTextAlignment(.center).lineSpacing(5)
   }
   Button { add() } label: { Label("+ Add Your First Property",systemImage:"house.badge.plus").font(.appFont(.headline,weight:.semibold,size:16)).frame(maxWidth:.infinity).padding(.vertical,16).background(HomeStyle.indigo,in:RoundedRectangle(cornerRadius:12)).foregroundStyle(.white) }.accessibilityIdentifier("first-property")
   Rectangle().fill(HomeStyle.border).frame(height:1)
   VStack(spacing:8) {
    benefit("Private portfolio registry",symbol:"checkmark.shield")
    benefit("Custom Valuation Dates",symbol:"calendar")
    benefit("No Debt / Loan Liabilities tracked",symbol:"shield")
   }
  }.homeCard()
 }
 private func benefit(_ label:String,symbol:String) -> some View {
  Label(label,systemImage:symbol).font(.appFont(.caption,size:13)).frame(maxWidth:.infinity,alignment:.leading).padding(10).background(HomeStyle.fill,in:RoundedRectangle(cornerRadius:4))
 }
 private var demoHistory: [HistoryPoint] {
  let holdings = store.snapshot?.holdings.filter { $0.assetClass == .realEstate } ?? []
  guard let first = holdings.first else { return [] }
  let maps = holdings.map { Dictionary($0.history.map { ($0.date,$0.value.value) },uniquingKeysWith:{ _,new in new }) }
  return first.history.compactMap { point in let values = maps.compactMap { $0[point.date] };return values.count == holdings.count ? HistoryPoint(date:point.date,value:DecimalValue(values.reduce(0,+))) : nil }
 }
 private func add() { dependencies.properties.errorMessage = nil;editing = PropertyDraft(id:UUID().uuidString.lowercased(),property:nil) }
 private func edit(_ property:PropertyEntry) { dependencies.properties.errorMessage = nil;editing = PropertyDraft(id:property.id,property:property) }
 private struct PropertyDraft:Identifiable { let id:String;let property:PropertyEntry? }
}
