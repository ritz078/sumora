import SwiftUI

/// Shared stock-page layout. Values always come from the selected instrument and portfolio source.
struct StocksView: View {
 let assetClass: AssetClass
 init(assetClass: AssetClass) {
  self.assetClass = assetClass
  _history = State(initialValue: HomeHistoryConnection(assetClass: assetClass))
 }
 private var isUS: Bool { assetClass == .usEquity }
 private var isFund: Bool { assetClass == .mutualFund }
 private var title: String { HomeStyle.title(assetClass) }
 private var sortLabel: String { isFund ? "Sort mutual funds" : isUS ? "Sort US stocks" : "Sort Indian stocks" }
 @Environment(PortfolioStore.self) private var store
 @Environment(AppDependencies.self) private var dependencies
 @Environment(AppPreferences.self) private var preferences
 @Environment(\.dismiss) private var dismiss
 @State private var history: HomeHistoryConnection
 @State private var sort: EquitySort = .valueDescending
 @State private var usesUSD = false
 private var holdings: [Holding] { store.snapshot?.holdings.filter { $0.assetClass == assetClass } ?? [] }
 private var presentation: StockCurrencyPresentation { StockCurrencyPresentation(holdings: holdings, reportingCurrency: store.snapshot?.reportingCurrency ?? "INR", usesUSD: isUS && usesUSD) }
 private var currency: String { presentation.currency }
 private var value: DecimalValue? { !holdings.isEmpty && holdings.allSatisfy { selectedValue($0) != nil } ? DecimalValue(holdings.reduce(0) { $0 + selectedValue($1)!.value }) : nil }
 private var invested: DecimalValue { DecimalValue(holdings.reduce(0) { $0 + (usesUSD ? $1.investedUSD?.value ?? 0 : $1.costBasisKnown != false ? $1.invested.value : 0) }) }
 private var costKnown: Bool { !holdings.isEmpty && holdings.allSatisfy { usesUSD ? $0.investedUSD != nil : $0.costBasisKnown != false } }
 private var gain: DecimalValue? { costKnown ? value.map { DecimalValue($0.value - invested.value) } : nil }
 private var percent: DecimalValue? { invested.value > 0 ? gain.map { DecimalValue($0.value / invested.value * 100) } : nil }
 private var scope: String { "\(dependencies.isLivePortfolio):\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "demo")" }

 var body: some View {
  ScrollView {
   VStack(spacing:16) {
    valuation
    if let snapshot = store.snapshot { daily(snapshot) }
    HomeTrajectoryCard(history: dependencies.isLivePortfolio ? (usesUSD ? history.usdHistory : history.history) : presentation.history(demoHistory),
     referenceDate: dependencies.demoDate, currency: currency, errorMessage: history.errorMessage,
     title: isFund ? "Portfolio Trajectory" : "Equities Trajectory", instrumentStyle: true, roundedInstrumentCallout: isFund)
    positions
    VStack(spacing:4) {
     Text(isFund ? "Sync baseline: Units remain unchanged while NAV updates daily · \(syncTime) IST" : "Sync baseline: Quantities remain unchanged while prices update · \(syncTime) IST")
      .font(.appFont(.caption2,weight:.medium,size:11))
     Text(isUS && usesUSD ? "Recorded USD values · History starts when USD snapshots are saved" : dependencies.isLivePortfolio ? (isUS ? "Recorded US holdings · Prices and exchange rates may be delayed" : (isFund ? "Recorded fund units · AMFI daily NAV" : "Recorded Zerodha holdings · Prices may be delayed")) : "Sample portfolio · Illustrative values, not live prices")
      .font(.appFont(.caption2,size:10))
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
   Text(title).font(.appFont(.headline,weight:.bold,size:17)).tracking(-0.425)
   Spacer()
   if isUS {
    Button { usesUSD.toggle() } label: {
     Text(usesUSD ? "$" : "₹").font(.appFont(.headline,weight:.semibold,size:17)).frame(width:36,height:36)
      .background(HomeStyle.card,in:Circle()).overlay(Circle().stroke(HomeStyle.border,lineWidth:1))
    }.foregroundStyle(HomeStyle.indigo).accessibilityIdentifier("stockCurrencyToggle")
     .accessibilityLabel(usesUSD ? "Switch to Indian rupees" : "Switch to US dollars")
   } else { Color.clear.frame(width:36,height:36) }
  }.padding(.horizontal,8).padding(.vertical,8).background(HomeStyle.background.opacity(0.95))
   .overlay(alignment:.bottom) { Rectangle().fill(HomeStyle.border).frame(height:1) }
 }
 private var valuation: some View {
  VStack(alignment:.leading,spacing:0) {
   HStack {
    Text("VALUATION").font(.appFont(.caption2,weight:.semibold,size:11)).tracking(0.8).foregroundStyle(HomeStyle.muted)
    Spacer(minLength:4)
    ReturnBadge(percent:percent,label:"All-time")
   }.frame(minHeight:18)
   MoneyText(amount:value,currency:currency).font(.appFont(.largeTitle,weight:.bold,size:32)).tracking(-0.8).padding(.vertical,8).accessibilityIdentifier("equityValue")
   Rectangle().fill(HomeStyle.border).frame(height:1)
   ViewThatFits(in:.horizontal) {
    HStack { investedLabel; Spacer(minLength:8); gainLabel }
    VStack(alignment:.leading,spacing:8) { investedLabel; gainLabel }
   }.padding(.top,8)
   if value == nil && !holdings.isEmpty {
    Text("Some prices are unavailable. Recorded holdings are retained.").font(.appFont(.caption2,size:10)).foregroundStyle(.orange).padding(.top,8)
   }
  }.homeCard()
 }
 private var investedLabel: some View {
  HStack(spacing:6) {
   Text(costKnown ? "Invested:" : "Known invested:").foregroundStyle(HomeStyle.muted)
   MoneyText(amount:invested,currency:currency).fontWeight(.semibold)
  }.font(.appFont(.caption,size:12))
 }
 private var gainLabel: some View {
  HStack(spacing:4) {
   Text("Gain:").foregroundStyle(HomeStyle.muted)
   HomeSignedMoney(amount:gain,currency:currency).fontWeight(.semibold).foregroundStyle(gainColor(gain))
  }.font(.appFont(.caption,size:12))
 }
 private func daily(_ snapshot: PortfolioSnapshot) -> some View {
  let metric = HomeDailyMetrics(snapshot:snapshot,asset:assetClass)
  return VStack(alignment:.leading,spacing:12) {
   HStack(spacing:8) {
    Circle().fill(isFund ? HomeStyle.allocationColor(.mutualFund) : Color.blue).frame(width:8,height:8)
    Text("DAILY PERFORMANCE").font(.appFont(.caption2,weight:.semibold,size:11)).tracking(0.8).foregroundStyle(HomeStyle.brightGreen)
   }
   HStack(alignment:.firstTextBaseline,spacing:8) {
    HomeSignedMoney(amount:presentation.amount(metric.gain),currency:currency).font(.appFont(.largeTitle,weight:.bold,size:32)).tracking(-0.8).foregroundStyle(.white)
    if let percent = metric.percent {
     Text(preferences.hideBalances ? "••••" : signed(percent.value)+"% today").font(.appFont(.caption2,weight:.semibold,size:12))
      .lineLimit(1).fixedSize(horizontal:true,vertical:false)
      .foregroundStyle(gainColor(metric.gain)).padding(.horizontal,8).padding(.vertical,2)
      .background(HomeStyle.emerald.opacity(0.1),in:Capsule()).overlay(Capsule().stroke(HomeStyle.emerald.opacity(0.2),lineWidth:1))
    }
   }.frame(maxWidth:.infinity,minHeight:38,alignment:.leading)
   Rectangle().fill(HomeStyle.emerald.opacity(0.2)).frame(height:1)
   HStack(spacing:6) {
    Image(systemName:"info.circle").foregroundStyle(HomeStyle.brightGreen.opacity(0.8))
    Text(metric.gain == nil ? (isFund ? "Daily baseline unavailable for recorded units" : "Daily baseline unavailable for recorded shares") : isFund ? "Price movement on recorded units based on AMFI daily NAV" : "Price movement on recorded shares")
   }.font(.appFont(.caption2,size:11)).foregroundStyle(Color(red:203/255,green:213/255,blue:225/255))
  }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
   .background(LinearGradient(colors:[Color(red:2/255,green:6/255,blue:23/255),Color(red:15/255,green:23/255,blue:42/255),Color(red:30/255,green:27/255,blue:75/255)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:16))
   .overlay(RoundedRectangle(cornerRadius:16).stroke(.white.opacity(0.6),lineWidth:1))
   .shadow(color:.black.opacity(0.12),radius:8,y:4)
 }
 private var positions: some View {
  VStack(alignment:.leading,spacing:14) {
   HStack {
    VStack(alignment:.leading,spacing:4) {
     Text("Holdings").font(.appFont(.headline,weight:.bold,size:17)).tracking(-0.425)
     Text("\(holdings.count) Instruments · \(isFund ? "Recorded fund units" : isUS ? "US Markets" : "NSE/BSE Direct")").font(.appFont(.caption,size:12)).foregroundStyle(HomeStyle.secondary)
    }
    Spacer(minLength:4)
    Menu {
     Picker(sortLabel,selection:$sort) { ForEach(EquitySort.allCases) { Text($0.rawValue).tag($0) } }
    } label: {
     HStack(spacing:6) {
      Text("Sort:").foregroundStyle(HomeStyle.muted)
      Text(sort.isValue ? "Value" : "Profit").fontWeight(.semibold)
      Image(systemName:"chevron.down").font(.system(size:10)).foregroundStyle(HomeStyle.muted)
     }.font(.appFont(.caption2,size:11)).padding(.horizontal,10).padding(.vertical,5)
      .background(Color(.tertiarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:8))
      .overlay(RoundedRectangle(cornerRadius:8).stroke(HomeStyle.border,lineWidth:1))
    }.accessibilityLabel(sortLabel)
   }
   VStack(spacing:0) {
    Rectangle().fill(HomeStyle.border).frame(height:1)
    ForEach(sortedHoldings) { holding in
     Group { if isFund { fundRow(holding) } else { row(holding) } }.accessibilityElement(children:.combine).accessibilityIdentifier("equity-holding-\(holding.id)")
     if holding.id != sortedHoldings.last?.id { Rectangle().fill(HomeStyle.border).frame(height:1) }
    }
    if holdings.isEmpty { Text(isFund ? "No mutual funds recorded yet" : isUS ? "No US stocks recorded yet" : "No Indian stocks recorded yet").font(.appFont(.caption,size:12)).foregroundStyle(HomeStyle.secondary).padding(.vertical,24) }
   }
  }.homeCard()
 }
 private func row(_ holding: Holding) -> some View {
  HStack(spacing:12) {
   VStack(alignment:.leading,spacing:4) {
    HStack(spacing:6) {
     Text(holding.name).font(.appFont(.caption,weight:.semibold,size:13)).lineLimit(1).truncationMode(.tail)
     Text(holding.symbol).font(.appFont(.caption2,weight:.medium,size:10)).foregroundStyle(HomeStyle.secondary)
      .padding(.horizontal,6).padding(.vertical,1).background(HomeStyle.background,in:RoundedRectangle(cornerRadius:2)).lineLimit(1).fixedSize(horizontal:true,vertical:false)
    }
    HStack(spacing:3) {
     Text("\(DisplayFormat.decimal(holding.quantity.value)) shares ·")
     MoneyText(amount:quoteAmount(holding),currency:isUS ? currency : holding.quoteCurrency)
    }.font(.appFont(.caption2,size:11)).foregroundStyle(HomeStyle.secondary)
   }.frame(maxWidth:.infinity,alignment:.leading)
   VStack(alignment:.trailing,spacing:4) {
    MoneyText(amount:selectedValue(holding),currency:currency).font(.appFont(.caption,weight:.bold,size:13))
    Text(preferences.hideBalances ? "••••" : (usesUSD ? holding.gainPercentUSD : holding.gainPercent).map { signed($0.value)+"%"+((usesUSD ? holding.gainUSD : holding.gain).map { " ("+($0.value >= 0 ? "+" : "−")+DisplayFormat.compactMoney(abs($0.value),currency:currency)+")" } ?? "") } ?? "Return unavailable")
     .font(.appFont(.caption2,weight:.medium,size:11)).foregroundStyle(gainColor(usesUSD ? holding.gainUSD : holding.gain)).multilineTextAlignment(.trailing).lineLimit(1)
   }.fixedSize(horizontal:true,vertical:false)
  }.padding(.vertical,12).contentShape(Rectangle())
 }
 private func fundRow(_ holding: Holding) -> some View {
  VStack(alignment:.leading,spacing:6) {
   Text(holding.name).font(.appFont(.caption,weight:.semibold,size:14)).lineLimit(1).truncationMode(.tail)
   HStack(alignment:.bottom,spacing:8) {
    HStack(spacing:4) {
     Text("\(DisplayFormat.decimal(holding.quantity.value,digits:2)) units ·")
     Text("NAV").foregroundStyle(HomeStyle.muted)
     MoneyText(amount:holding.quote,currency:holding.quoteCurrency,fractionDigits:2)
    }.font(.appFont(.caption2,size:11)).foregroundStyle(HomeStyle.secondary).lineLimit(1).minimumScaleFactor(0.8)
    Spacer(minLength:0)
    VStack(alignment:.trailing,spacing:2) {
     MoneyText(amount:holding.value,currency:currency).font(.appFont(.caption,weight:.bold,size:14))
     Text(preferences.hideBalances ? "••••" : holding.gainPercent.map { signed($0.value)+"%"+(holding.gain.map { " ("+($0.value >= 0 ? "+" : "−")+DisplayFormat.money(abs($0.value),currency:currency)+")" } ?? "") } ?? "Return unavailable")
      .font(.appFont(.caption2,weight:.semibold,size:11)).foregroundStyle(gainColor(holding.gain)).lineLimit(1)
    }.fixedSize(horizontal:true,vertical:false)
   }
  }.padding(.vertical,14)
 }
 private func quoteAmount(_ holding: Holding) -> DecimalValue? {
  guard isUS && !usesUSD else { return holding.quote }
  guard let quote = holding.quote, let fx = holding.fxRate, fx.value > 0 else { return nil }
  return DecimalValue(quote.value * fx.value)
 }
 private func selectedValue(_ holding: Holding) -> DecimalValue? { usesUSD ? holding.valueUSD : holding.value }
 private var sortedHoldings: [Holding] {
  holdings.sorted { left,right in
   let a = sort.isValue ? selectedValue(left)?.value : (usesUSD ? left.gainUSD : left.gain)?.value
   let b = sort.isValue ? selectedValue(right)?.value : (usesUSD ? right.gainUSD : right.gain)?.value
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
  guard let date = isUS ? store.snapshot?.capturedAt : store.snapshot?.holdingsSyncAt else { return "—" }
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
  if assetClass == .fixedDeposit || assetClass == .nps { StatementInstrumentView(assetClass:assetClass) }
  else if assetClass == .gold { GoldView() }
  else if assetClass == .realEstate { RealEstateView() }
  else if assetClass == .indianEquity || assetClass == .usEquity || assetClass == .mutualFund { StocksView(assetClass:assetClass) }
  else { HoldingsView(assetClass:assetClass).toolbar(.visible,for:.navigationBar).navigationTitle(HomeStyle.title(assetClass)).navigationBarTitleDisplayMode(.inline) }
 }
}
