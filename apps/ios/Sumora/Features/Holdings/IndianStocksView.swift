import SwiftUI

/// Dedicated Indian-equity page. Values always come from the selected portfolio source.
struct IndianStocksView: View {
 @Environment(PortfolioStore.self) private var store
 @Environment(AppDependencies.self) private var dependencies
 @Environment(AppPreferences.self) private var preferences
 @Environment(\.dismiss) private var dismiss
 @State private var history = HomeHistoryConnection(assetClass: .indianEquity)
 @State private var sort: EquitySort = .valueDescending
 private var holdings: [Holding] { store.snapshot?.holdings.filter { $0.assetClass == .indianEquity } ?? [] }
 private var currency: String { store.snapshot?.reportingCurrency ?? "INR" }
 private var value: DecimalValue? { !holdings.isEmpty && holdings.allSatisfy { $0.value != nil } ? DecimalValue(holdings.reduce(0) { $0 + $1.value!.value }) : nil }
 private var invested: DecimalValue { DecimalValue(holdings.filter { $0.costBasisKnown != false }.reduce(0) { $0 + $1.invested.value }) }
 private var costKnown: Bool { !holdings.isEmpty && holdings.allSatisfy { $0.costBasisKnown != false } }
 private var gain: DecimalValue? { costKnown ? value.map { DecimalValue($0.value - invested.value) } : nil }
 private var percent: DecimalValue? { invested.value > 0 ? gain.map { DecimalValue($0.value / invested.value * 100) } : nil }
 private var scope: String { "\(dependencies.isLivePortfolio):\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "demo")" }

 var body: some View {
  ScrollView {
   VStack(spacing:16) {
    valuation
    if let snapshot = store.snapshot { daily(snapshot) }
    HomeTrajectoryCard(history: dependencies.isLivePortfolio ? history.history : demoHistory,
     referenceDate: dependencies.demoDate, currency: currency, errorMessage: history.errorMessage,
     title: "Equities Trajectory", instrumentStyle: true)
    positions
    VStack(spacing:4) {
     Text("Sync baseline: Quantities remain unchanged while prices update · \(syncTime) IST")
      .font(.inter(.caption2,weight:.medium,size:11))
     Text(dependencies.isLivePortfolio ? "Recorded Zerodha holdings · Prices may be delayed" : "Sample portfolio · Illustrative values, not live prices")
      .font(.inter(.caption2,size:10))
    }.foregroundStyle(HomeStyle.muted).multilineTextAlignment(.center).padding(.horizontal,8).padding(.vertical,4)
   }.padding(16).padding(.bottom,24)
  }.background(HomeStyle.background).foregroundStyle(HomeStyle.ink)
   .safeAreaInset(edge:.top,spacing:0) { header }
   .toolbar(.hidden,for:.navigationBar)
   .preference(key: InstrumentPageKey.self,value:true)
   .refreshable { await store.refresh(); await history.refresh() }
   .task(id:scope) {
    history.configure(address:dependencies.zerodha.address,token:dependencies.isLivePortfolio ? dependencies.zerodha.sessionToken : nil)
    await history.refresh()
   }
 }
 private var header: some View {
  HStack {
   Button { dismiss() } label: { Image(systemName:"chevron.left").font(.system(size:17,weight:.semibold)).frame(width:36,height:36) }
    .foregroundStyle(HomeStyle.indigo).accessibilityLabel("Go back").accessibilityIdentifier("equitiesBack")
   Spacer()
   Text("Indian Stocks").font(.inter(.headline,weight:.bold,size:17)).tracking(-0.425)
   Spacer()
   Color.clear.frame(width:36,height:36)
  }.padding(.horizontal,8).padding(.vertical,8).background(HomeStyle.background.opacity(0.95))
   .overlay(alignment:.bottom) { Rectangle().fill(HomeStyle.border).frame(height:1) }
 }
 private var valuation: some View {
  VStack(alignment:.leading,spacing:0) {
   HStack {
    Text("VALUATION").font(.inter(.caption2,weight:.semibold,size:11)).tracking(0.8).foregroundStyle(HomeStyle.muted)
    Spacer(minLength:4)
    ReturnBadge(percent:percent,label:"All-time")
   }.frame(minHeight:18)
   MoneyText(amount:value,currency:currency).font(.inter(.largeTitle,weight:.bold,size:32)).tracking(-0.8).padding(.vertical,8).accessibilityIdentifier("equityValue")
   Rectangle().fill(HomeStyle.border).frame(height:1)
   ViewThatFits(in:.horizontal) {
    HStack { investedLabel; Spacer(minLength:8); gainLabel }
    VStack(alignment:.leading,spacing:8) { investedLabel; gainLabel }
   }.padding(.top,8)
   if value == nil && !holdings.isEmpty {
    Text("Some prices are unavailable. Recorded holdings are retained.").font(.inter(.caption2,size:10)).foregroundStyle(.orange).padding(.top,8)
   }
  }.homeCard()
 }
 private var investedLabel: some View {
  HStack(spacing:6) {
   Text(costKnown ? "Invested:" : "Known invested:").foregroundStyle(HomeStyle.muted)
   MoneyText(amount:invested,currency:currency).fontWeight(.semibold)
  }.font(.inter(.caption,size:12))
 }
 private var gainLabel: some View {
  HStack(spacing:4) {
   Text("Gain:").foregroundStyle(HomeStyle.muted)
   HomeSignedMoney(amount:gain,currency:currency).fontWeight(.semibold).foregroundStyle(gainColor(gain))
  }.font(.inter(.caption,size:12))
 }
 private func daily(_ snapshot: PortfolioSnapshot) -> some View {
  let metric = HomeDailyMetrics(snapshot:snapshot,asset:.indianEquity)
  return VStack(alignment:.leading,spacing:12) {
   HStack(spacing:8) {
    Circle().fill(Color.blue).frame(width:8,height:8)
    Text("DAILY PERFORMANCE").font(.inter(.caption2,weight:.semibold,size:11)).tracking(0.8).foregroundStyle(HomeStyle.brightGreen)
   }
   HStack(alignment:.firstTextBaseline,spacing:8) {
    HomeSignedMoney(amount:metric.gain,currency:currency).font(.inter(.largeTitle,weight:.bold,size:32)).tracking(-0.8).foregroundStyle(.white)
    if let percent = metric.percent {
     Text(preferences.hideBalances ? "••••" : signed(percent.value)+"% today").font(.inter(.caption2,weight:.semibold,size:12))
      .lineLimit(1).fixedSize(horizontal:true,vertical:false)
      .foregroundStyle(gainColor(metric.gain)).padding(.horizontal,8).padding(.vertical,2)
      .background(HomeStyle.emerald.opacity(0.1),in:Capsule()).overlay(Capsule().stroke(HomeStyle.emerald.opacity(0.2),lineWidth:1))
    }
   }.frame(maxWidth:.infinity,minHeight:38,alignment:.leading)
   Rectangle().fill(HomeStyle.emerald.opacity(0.2)).frame(height:1)
   HStack(spacing:6) {
    Image(systemName:"info.circle").foregroundStyle(HomeStyle.brightGreen.opacity(0.8))
    Text(metric.gain == nil ? "Daily baseline unavailable for recorded shares" : "Price movement on recorded shares")
   }.font(.inter(.caption2,size:11)).foregroundStyle(Color(red:203/255,green:213/255,blue:225/255))
  }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
   .background(LinearGradient(colors:[Color(red:2/255,green:6/255,blue:23/255),Color(red:15/255,green:23/255,blue:42/255),Color(red:30/255,green:27/255,blue:75/255)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:16))
   .overlay(RoundedRectangle(cornerRadius:16).stroke(.white.opacity(0.6),lineWidth:1))
   .shadow(color:.black.opacity(0.12),radius:8,y:4)
 }
 private var positions: some View {
  VStack(alignment:.leading,spacing:14) {
   HStack {
    VStack(alignment:.leading,spacing:4) {
     Text("Holdings").font(.inter(.headline,weight:.bold,size:17)).tracking(-0.425)
     Text("\(holdings.count) Instruments · NSE/BSE Direct").font(.inter(.caption,size:12)).foregroundStyle(HomeStyle.secondary)
    }
    Spacer(minLength:4)
    Menu {
     Picker("Sort Indian stocks",selection:$sort) { ForEach(EquitySort.allCases) { Text($0.rawValue).tag($0) } }
    } label: {
     HStack(spacing:6) {
      Text("Sort:").foregroundStyle(HomeStyle.muted)
      Text(sort.isValue ? "Value" : "Profit").fontWeight(.semibold)
      Image(systemName:"chevron.down").font(.system(size:10)).foregroundStyle(HomeStyle.muted)
     }.font(.inter(.caption2,size:11)).padding(.horizontal,10).padding(.vertical,5)
      .background(Color(.tertiarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:8))
      .overlay(RoundedRectangle(cornerRadius:8).stroke(HomeStyle.border,lineWidth:1))
    }.accessibilityLabel("Sort Indian stocks")
   }
   VStack(spacing:0) {
    Rectangle().fill(HomeStyle.border).frame(height:1)
    ForEach(sortedHoldings) { holding in
     row(holding).accessibilityElement(children:.combine).accessibilityIdentifier("equity-holding-\(holding.id)")
     if holding.id != sortedHoldings.last?.id { Rectangle().fill(HomeStyle.border).frame(height:1) }
    }
    if holdings.isEmpty { Text("No Indian stocks recorded yet").font(.inter(.caption,size:12)).foregroundStyle(HomeStyle.secondary).padding(.vertical,24) }
   }
  }.homeCard()
 }
 private func row(_ holding: Holding) -> some View {
  HStack(spacing:12) {
   VStack(alignment:.leading,spacing:4) {
    HStack(spacing:6) {
     Text(holding.name).font(.inter(.caption,weight:.semibold,size:13)).lineLimit(1).truncationMode(.tail)
     Text(holding.symbol).font(.inter(.caption2,weight:.medium,size:10)).foregroundStyle(HomeStyle.secondary)
      .padding(.horizontal,6).padding(.vertical,1).background(HomeStyle.background,in:RoundedRectangle(cornerRadius:2)).lineLimit(1).fixedSize(horizontal:true,vertical:false)
    }
    HStack(spacing:3) {
     Text("\(DisplayFormat.decimal(holding.quantity.value)) shares ·")
     MoneyText(amount:holding.quote,currency:holding.quoteCurrency)
    }.font(.inter(.caption2,size:11)).foregroundStyle(HomeStyle.secondary)
   }.frame(maxWidth:.infinity,alignment:.leading)
   VStack(alignment:.trailing,spacing:4) {
    MoneyText(amount:holding.value,currency:currency).font(.inter(.caption,weight:.bold,size:13))
    Text(preferences.hideBalances ? "••••" : holding.gainPercent.map { signed($0.value)+"%"+(holding.gain.map { " ("+($0.value >= 0 ? "+" : "−")+DisplayFormat.compactMoney(abs($0.value),currency:currency)+")" } ?? "") } ?? "Return unavailable")
     .font(.inter(.caption2,weight:.medium,size:11)).foregroundStyle(gainColor(holding.gain)).multilineTextAlignment(.trailing).lineLimit(1)
   }.fixedSize(horizontal:true,vertical:false)
  }.padding(.vertical,12).contentShape(Rectangle())
 }
 private var sortedHoldings: [Holding] {
  holdings.sorted { left,right in
   let a = sort.isValue ? left.value?.value : left.gain?.value
   let b = sort.isValue ? right.value?.value : right.gain?.value
   switch (a,b) {
   case let (.some(a),.some(b)) where a != b: return sort.isAscending ? a < b : a > b
   case (.some,.none): return true
   case (.none,.some): return false
   default: return left.id < right.id
   }
  }
 }
 private var demoHistory: [HistoryPoint] {
  guard let first = holdings.first else { return [] }
  let maps = holdings.map { Dictionary($0.history.map { ($0.date,$0.value.value) },uniquingKeysWith: { _,new in new }) }
  return first.history.compactMap { point in
   let values = maps.compactMap { $0[point.date] }
   return values.count == holdings.count ? HistoryPoint(date:point.date,value:DecimalValue(values.reduce(0,+))) : nil
  }.sorted { $0.date < $1.date }
 }
 private var syncTime: String {
  guard let date = store.snapshot?.holdingsSyncAt else { return "—" }
  let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier:"Asia/Kolkata"); formatter.dateFormat = "HH:mm"
  return formatter.string(from:date)
 }
 private func signed(_ value: Decimal) -> String { (value >= 0 ? "+" : "")+DisplayFormat.decimal(value) }
 private func gainColor(_ value: DecimalValue?) -> Color { preferences.hideBalances || value == nil ? HomeStyle.secondary : value!.value >= 0 ? DashboardStyle.positive : .red }
 private enum EquitySort: String,CaseIterable,Identifiable {
  case valueDescending = "Value: High to Low",valueAscending = "Value: Low to High",profitDescending = "Profit: High to Low",profitAscending = "Profit: Low to High"
  var id:Self { self }
  var isValue:Bool { self == .valueAscending || self == .valueDescending }
  var isAscending:Bool { self == .valueAscending || self == .profitAscending }
 }
}

struct InstrumentPageKey: PreferenceKey {
 static let defaultValue = false
 static func reduce(value: inout Bool,nextValue: () -> Bool) { value = value || nextValue() }
}

struct InstrumentDestination: View {
 let assetClass: AssetClass
 var body: some View {
  if assetClass == .indianEquity { IndianStocksView() }
  else { HoldingsView(assetClass:assetClass).toolbar(.visible,for:.navigationBar).navigationTitle(HomeStyle.title(assetClass)).navigationBarTitleDisplayMode(.inline) }
 }
}
