import SwiftUI

/// Statement-based instruments share the Stocks layout without intraday performance.
struct StatementInstrumentView: View {
 let assetClass: AssetClass
 init(assetClass:AssetClass) {
  self.assetClass=assetClass
  _history=State(initialValue:HomeHistoryConnection(assetClass:assetClass))
 }
 @Environment(PortfolioStore.self) private var store
 @Environment(AppDependencies.self) private var dependencies
 @Environment(AppPreferences.self) private var preferences
 @Environment(\.dismiss) private var dismiss
 @State private var history: HomeHistoryConnection
 @State private var ascending=false
 private var isFD:Bool { assetClass == .fixedDeposit }
 private var title:String { HomeStyle.title(assetClass) }
 private var currency:String { store.snapshot?.reportingCurrency ?? "INR" }
 private var holdings:[Holding] { store.snapshot?.holdings.filter { $0.assetClass == assetClass } ?? [] }
 private var value:DecimalValue? {
  guard !holdings.isEmpty,holdings.allSatisfy({ amount($0) != nil }) else { return nil }
  return DecimalValue(holdings.reduce(0) { $0 + amount($1)!.value })
 }
 private var npsSummaries:[NPSSummary] { (store.snapshot?.npsSummaries ?? []).filter { summary in holdings.contains { $0.id.hasPrefix("nps:\(summary.tier):") } } }
 private var npsCostKnown:Bool { !holdings.isEmpty && holdings.allSatisfy { h in npsSummaries.contains { h.id.hasPrefix("nps:\($0.tier):") } } }
 private var invested:DecimalValue? {
  guard !isFD,!holdings.isEmpty else { return nil }
  if npsCostKnown { return DecimalValue(npsSummaries.reduce(0) { $0 + $1.invested.value }) }
  guard holdings.allSatisfy({ $0.costBasisKnown != false }) else { return nil }
  return DecimalValue(holdings.reduce(0) { $0 + $1.invested.value })
 }
 private var gain:DecimalValue? { if !isFD,npsCostKnown { return DecimalValue(npsSummaries.reduce(0) { $0 + $1.gain.value }) };guard let value,let invested else { return nil };return DecimalValue(value.value-invested.value) }
 private var percent:DecimalValue? { guard let gain,let invested,invested.value > 0 else { return nil };return DecimalValue(gain.value/invested.value*100) }
 private var scope:String { "\(dependencies.isLivePortfolio):\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "demo")" }
 private var sorted:[Holding] {
  holdings.sorted { left,right in
   switch (amount(left)?.value,amount(right)?.value) {
   case let (.some(a),.some(b)) where a != b: return ascending ? a < b : a > b
   case (.some,.none): return true
   case (.none,.some): return false
   default: return left.id < right.id
   }
  }
 }
 var body:some View {
  ScrollView {
   VStack(spacing:16) {
    if store.snapshot == nil { ProgressView("Loading investments…").homeCard() }
    else {
     valuation
     HomeTrajectoryCard(history:dependencies.isLivePortfolio ? history.history : demoHistory,referenceDate:dependencies.demoDate,currency:currency,errorMessage:history.errorMessage,title:isFD ? "Fixed Deposit Trajectory" : "NPS Trajectory",instrumentStyle:true)
     positions
     VStack(spacing:4) {
      Text(isFD ? "Sync baseline: Statement maturity values include future interest." : "Sync baseline: Recorded units and NAV update when a new NPS statement arrives.")
       .font(.appFont(.caption2,weight:.medium,size:11))
      Text(dependencies.isLivePortfolio ? (isFD ? "Bank statement maturity amounts · Not a current withdrawal value" : "NPS statement valuation · No live NAV estimate") : "Sample portfolio · Illustrative statement values")
       .font(.appFont(.caption2,size:10))
     }.foregroundStyle(HomeStyle.muted).multilineTextAlignment(.center).padding(.horizontal,8).padding(.vertical,4)
    }
   }.padding(16).padding(.bottom,24)
  }.background(HomeStyle.background).foregroundStyle(HomeStyle.ink)
   .safeAreaInset(edge:.top,spacing:0) { header }
   .toolbar(.hidden,for:.navigationBar).preference(key:InstrumentPageKey.self,value:true)
   .refreshable { await store.refresh();await history.refresh() }
   .task(id:scope) {
    history.configure(address:dependencies.zerodha.address,token:dependencies.isLivePortfolio ? dependencies.zerodha.sessionToken : nil)
    await history.refresh()
   }
 }
 private var header:some View {
  HStack {
   Button { dismiss() } label: { Image(systemName:"chevron.left").font(.system(size:17,weight:.semibold)).frame(width:36,height:36) }.foregroundStyle(HomeStyle.indigo).accessibilityLabel("Go back").accessibilityIdentifier("statementBack")
   Spacer()
   Text(title).font(.appFont(.headline,weight:.bold,size:17)).tracking(-0.425)
   Spacer()
   Color.clear.frame(width:36,height:36)
  }.padding(.horizontal,8).padding(.vertical,8).background(HomeStyle.background.opacity(0.95)).overlay(alignment:.bottom) { Rectangle().fill(HomeStyle.border).frame(height:1) }
 }
 private var valuation:some View {
  VStack(alignment:.leading,spacing:0) {
   HStack {
    Text(isFD ? "MATURITY VALUE" : "VALUATION").font(.appFont(.caption2,weight:.semibold,size:11)).tracking(0.8).foregroundStyle(HomeStyle.muted)
    Spacer(minLength:4)
    if !isFD { ReturnBadge(percent:percent,label:"All-time") }
   }.frame(minHeight:18)
   MoneyText(amount:value,currency:currency).font(.appFont(.largeTitle,weight:.bold,size:32)).tracking(-0.8).padding(.vertical,8).accessibilityIdentifier("statementValue")
   if !isFD {
    Rectangle().fill(HomeStyle.border).frame(height:1)
    ViewThatFits(in:.horizontal) {
     HStack { investedLabel;Spacer(minLength:8);gainLabel }
     VStack(alignment:.leading,spacing:8) { investedLabel;gainLabel }
    }.padding(.top,8)
    ForEach(npsSummaries,id:\.tier) { summary in
     HStack(spacing:6) {
      Text(npsSummaries.count == 1 ? "XIRR (annualized):" : "Tier \(summary.tier) XIRR (annualized):").foregroundStyle(HomeStyle.muted)
      Text(preferences.hideBalances ? "••••" : summary.xirr.map { DisplayFormat.decimal($0.value)+"%" } ?? "—").fontWeight(.semibold).accessibilityIdentifier("npsXIRR-"+summary.tier)
     }.font(.appFont(.caption,size:12)).padding(.top,8)
    }
   }
   if isFD { Text("Statement maturity amount · counted toward net worth").font(.appFont(.caption2,size:10)).foregroundStyle(HomeStyle.secondary).padding(.top,4) }
   if value == nil && !holdings.isEmpty { Text("Some statement valuations are unavailable. Recorded holdings are retained.").font(.appFont(.caption2,size:10)).foregroundStyle(.orange).padding(.top,8) }
  }.homeCard()
 }
 private var investedLabel:some View {
  HStack(spacing:6) {
   Text("Invested:").foregroundStyle(HomeStyle.muted)
   MoneyText(amount:invested,currency:currency).fontWeight(.semibold).accessibilityIdentifier("statementPrincipal")
  }.font(.appFont(.caption,size:12))
 }
 private var gainLabel:some View {
  HStack(spacing:4) {
   Text("Gain:").foregroundStyle(HomeStyle.muted)
   HomeSignedMoney(amount:gain,currency:currency).fontWeight(.semibold).foregroundStyle(gainColor(gain)).accessibilityIdentifier("statementGain")
  }.font(.appFont(.caption,size:12))
 }
 private var positions:some View {
  VStack(alignment:.leading,spacing:14) {
   HStack {
    VStack(alignment:.leading,spacing:4) {
     Text("Holdings").font(.appFont(.headline,weight:.bold,size:17)).tracking(-0.425)
     Text("\(holdings.count) \(isFD ? "Deposits · Maturity values" : "Schemes · Statement NAV")").font(.appFont(.caption,size:12)).foregroundStyle(HomeStyle.secondary)
    }
    Spacer(minLength:4)
    Menu {
     Button("Value: High to Low") { ascending=false }
     Button("Value: Low to High") { ascending=true }
    } label: {
     HStack(spacing:6) { Text("Sort:").foregroundStyle(HomeStyle.muted);Text("Value").fontWeight(.semibold);Image(systemName:"chevron.down").font(.system(size:10)).foregroundStyle(HomeStyle.muted) }.font(.appFont(.caption2,size:11)).padding(.horizontal,10).padding(.vertical,5).background(Color(.tertiarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(HomeStyle.border,lineWidth:1))
    }.accessibilityLabel(isFD ? "Sort fixed deposits" : "Sort NPS holdings")
   }
   VStack(spacing:0) {
    Rectangle().fill(HomeStyle.border).frame(height:1)
    ForEach(sorted) { holding in
     Group { if isFD { depositRow(holding) } else { npsRow(holding) } }.accessibilityElement(children:.combine).accessibilityIdentifier("statement-holding-\(holding.id)")
     if holding.id != sorted.last?.id { Rectangle().fill(HomeStyle.border).frame(height:1) }
    }
    if holdings.isEmpty { Text(isFD ? "No fixed deposits recorded yet" : "No NPS schemes recorded yet").font(.appFont(.caption,size:12)).foregroundStyle(HomeStyle.secondary).padding(.vertical,24) }
   }
  }.homeCard()
 }
 private func npsRow(_ holding:Holding) -> some View {
  HStack(spacing:12) {
   VStack(alignment:.leading,spacing:4) {
    Text(holding.name).font(.appFont(.caption,weight:.semibold,size:13)).lineLimit(1).truncationMode(.tail)
    Text(holding.symbol).font(.appFont(.caption2,weight:.medium,size:10)).foregroundStyle(HomeStyle.secondary).lineLimit(1)
    HStack(spacing:3) {
     Text("\(DisplayFormat.decimal(holding.quantity.value,digits:4)) \(holding.unit) · NAV")
     MoneyText(amount:holding.quote,currency:holding.quoteCurrency,fractionDigits:2)
    }.font(.appFont(.caption2,size:11)).foregroundStyle(HomeStyle.secondary).lineLimit(1).minimumScaleFactor(0.8)
   }.frame(maxWidth:.infinity,alignment:.leading)
   VStack(alignment:.trailing,spacing:4) {
    MoneyText(amount:holding.value,currency:currency).font(.appFont(.caption,weight:.bold,size:13))
    Text(npsReturn(holding)).font(.appFont(.caption2,weight:.medium,size:11)).foregroundStyle(gainColor(holding.costBasisKnown == false ? nil : holding.gain)).lineLimit(1)
   }.fixedSize(horizontal:true,vertical:false)
  }.padding(.vertical,12)
 }
 private func depositRow(_ holding:Holding) -> some View {
  VStack(alignment:.leading,spacing:6) {
   HStack(spacing:8) {
    Text(holding.name).font(.appFont(.caption,weight:.semibold,size:13)).lineLimit(1).truncationMode(.tail)
    Spacer(minLength:0)
    MoneyText(amount:amount(holding),currency:currency).font(.appFont(.caption,weight:.bold,size:13))
   }
   if let terms=holding.depositTerms {
    Text("\(DisplayFormat.decimal(terms.rate.value))% p.a. · Matures \(dateLabel(terms.maturesOn))").font(.appFont(.caption2,size:11)).foregroundStyle(HomeStyle.secondary)
   } else { Text("Deposit terms unavailable").font(.appFont(.caption2,size:11)).foregroundStyle(HomeStyle.secondary) }
  }.padding(.vertical,12)
 }
 private func npsReturn(_ holding:Holding) -> String {
  guard !preferences.hideBalances else { return "••••" }
  guard holding.costBasisKnown != false,holding.value != nil,let percent=holding.gainPercent else { return "Return unavailable" }
  return (percent.value >= 0 ? "+" : "")+DisplayFormat.decimal(percent.value)+"%"
 }
 private func amount(_ holding:Holding) -> DecimalValue? { isFD ? holding.depositTerms?.maturityAmount ?? holding.value : holding.value }
 private func dateLabel(_ raw:String) -> String {
  guard let date=ISO8601DateFormatter().date(from:raw+"T00:00:00+05:30") else { return raw }
  let f=DateFormatter();f.locale=Locale(identifier:"en_IN");f.timeZone=TimeZone(identifier:"Asia/Kolkata");f.dateFormat="dd MMM yyyy";return f.string(from:date)
 }
 private var demoHistory:[HistoryPoint] {
  guard let first=holdings.first else { return [] }
  let maps=holdings.map { Dictionary($0.history.map { ($0.date,$0.value.value) },uniquingKeysWith:{ _,new in new }) }
  return first.history.compactMap { point in
   let values=maps.compactMap { $0[point.date] }
   return values.count == holdings.count ? HistoryPoint(date:point.date,value:DecimalValue(values.reduce(0,+))) : nil
  }.sorted { $0.date < $1.date }
 }
 private func gainColor(_ value:DecimalValue?) -> Color { preferences.hideBalances || value == nil ? HomeStyle.secondary : value!.value >= 0 ? DashboardStyle.positive : .red }
}
