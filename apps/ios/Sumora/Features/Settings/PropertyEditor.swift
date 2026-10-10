import SwiftUI

struct PropertyInput {
 static func clean(_ text:String) -> String { text.replacingOccurrences(of:",",with:"").trimmingCharacters(in:.whitespacesAndNewlines) }
 static func amount(_ text:String,max:Decimal = 1_000_000_000_000) -> Decimal? {
  let text = clean(text)
  guard text.range(of:"^[0-9]{1,13}(?:\\.[0-9]{1,4})?$",options:.regularExpression) != nil,
   let number = Decimal(string:text,locale:Locale(identifier:"en_US_POSIX")),number >= 0,number <= max else { return nil }
  return number
 }
 static var dateFormatter:DateFormatter { let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=TimeZone(identifier:"Asia/Kolkata");f.dateFormat="yyyy-MM-dd";return f }
}

struct PropertyEditor: View {
 @Environment(AppDependencies.self) private var dependencies
 @Environment(AppPreferences.self) private var preferences
 @Environment(\.dismiss) private var dismiss
 let id:String
 let scope:String
 let property:PropertyEntry?
 @State private var name:String
 @State private var value:String
 @State private var cost:String
 @State private var date:Date
 @State private var classification:String
 @State private var location:String
 @State private var confirmRemove = false
 init(id:String,property:PropertyEntry?,scope:String) {
  self.id=id;self.property=property;self.scope=scope
  _name=State(initialValue:property?.name ?? "")
  _value=State(initialValue:property.map { DisplayFormat.decimal($0.estimatedValue.value,digits:4) } ?? "")
  _cost=State(initialValue:property?.purchaseCost.map { DisplayFormat.decimal($0.value,digits:4) } ?? "")
  _date=State(initialValue:property.flatMap { PropertyInput.dateFormatter.date(from:$0.valuationDate) } ?? Date())
  _classification=State(initialValue:property?.classification ?? "apartment")
  _location=State(initialValue:property?.location ?? "")
 }
 private var canSave:Bool {
  !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && name.count <= 80 && !name.unicodeScalars.contains { $0.value < 32 } && location.count <= 100 && !location.unicodeScalars.contains { $0.value < 32 } && PropertyInput.amount(value) != nil && (PropertyInput.clean(cost).isEmpty || PropertyInput.amount(cost) != nil)
 }
 private var authorized:Bool { dependencies.isLivePortfolio && dependencies.zerodha.sessionToken != nil }
 private var metrics:PropertyValuation? {
  guard let amount=PropertyInput.amount(value) else { return nil }
  return PropertyValuation(properties:[PropertyEntry(id:id,name:name,estimatedValue:DecimalValue(amount),valuationDate:PropertyInput.dateFormatter.string(from:date),purchaseCost:PropertyInput.amount(cost).map { DecimalValue($0) },updatedAt:0)])
 }
 var body: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:20) {
    HStack(alignment:.top,spacing:8) {
     VStack(alignment:.leading,spacing:4) {
      Text(property == nil ? "Add Real Estate Property" : "Edit Real Estate Property").font(.inter(.title2,weight:.bold,size:22)).tracking(-0.5).accessibilityIdentifier("property-editor-title")
      Text("Manual asset appraisal entry").font(.inter(.caption,size:13)).foregroundStyle(HomeStyle.secondary)
     }
     Spacer(minLength:0)
     Button { dismiss() } label: { Image(systemName:"xmark").font(.system(size:16,weight:.semibold)).frame(width:32,height:32).background(HomeStyle.fill,in:RoundedRectangle(cornerRadius:12)) }.foregroundStyle(HomeStyle.secondary).accessibilityLabel("Close property editor")
    }
    Rectangle().fill(HomeStyle.border).frame(height:1)
    VStack(alignment:.leading,spacing:8) {
     label("Property Classification")
     LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
      classificationButton("apartment","Residential Apartment","building.2")
      classificationButton("house","Villa / House","house")
      classificationButton("commercial","Commercial Plot","building")
      classificationButton("land","Agricultural Land","leaf")
     }
    }
    input("Property Name",placeholder:"e.g. Prestige Falcon City, Tower 4",text:$name,identifier:"property-name")
    moneyInput("Estimated Current Value",text:$value,identifier:"property-value",help:"Latest independent or circle-rate appraisal")
    moneyInput("Purchase / Invested Cost Basis",text:$cost,identifier:"property-cost",help:"Optional · Total procurement capital inclusive of registration")
    ViewThatFits(in:.horizontal) {
     HStack(alignment:.top,spacing:12) { valuationDate;locationField }
     VStack(alignment:.leading,spacing:16) { valuationDate;locationField }
    }
    projectedGain
    if !authorized { Text("Switch to your connected portfolio to save properties.").font(.inter(.caption,size:12)).foregroundStyle(HomeStyle.secondary) }
    if let error=dependencies.properties.errorMessage { Text(error).font(.inter(.caption,size:12)).foregroundStyle(.orange).accessibilityIdentifier("property-error") }
    if property != nil {
     Button("Remove Property",role:.destructive) { confirmRemove = true }.font(.inter(.caption,weight:.semibold,size:13)).disabled(!authorized).accessibilityIdentifier("remove-property")
    }
   }.padding(16).padding(.top,16)
  }.background(HomeStyle.card).foregroundStyle(HomeStyle.ink)
   .safeAreaInset(edge:.bottom,spacing:0) { footer }
   .disabled(dependencies.properties.isBusy).interactiveDismissDisabled(dependencies.properties.isBusy)
   .presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(28)
   .confirmationDialog("Remove property?",isPresented:$confirmRemove) {
    Button("Remove property",role:.destructive) { Task { if await dependencies.properties.remove(id:id) { await dependencies.portfolio.refresh();dismiss() } } }
   } message: { Text("Removing a property does not create cash proceeds.") }
 }
 private func label(_ text:String) -> some View { Text(text).font(.inter(.caption,weight:.medium,size:13)) }
 private func classificationButton(_ key:String,_ title:String,_ symbol:String) -> some View {
  Button { classification=key } label: {
   Label(title,systemImage:symbol).font(.inter(.caption,weight:.medium,size:13)).lineLimit(1).truncationMode(.tail).frame(maxWidth:.infinity,alignment:.leading).padding(12)
    .background(classification == key ? HomeStyle.indigo.opacity(0.04) : HomeStyle.card,in:RoundedRectangle(cornerRadius:8))
    .overlay(RoundedRectangle(cornerRadius:8).stroke(classification == key ? HomeStyle.indigo : Color.primary.opacity(0.12),lineWidth:1))
  }.foregroundStyle(classification == key ? HomeStyle.indigo : HomeStyle.secondary).accessibilityAddTraits(classification == key ? .isSelected : []).accessibilityIdentifier("property-class-\(key)")
 }
 private func input(_ title:String,placeholder:String,text:Binding<String>,identifier:String,numeric:Bool=false) -> some View {
  VStack(alignment:.leading,spacing:8) {
   label(title)
   TextField(placeholder,text:text).font(.inter(.caption,size:14)).keyboardType(numeric ? .decimalPad : .default).padding(12).background(HomeStyle.card,in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(Color.primary.opacity(0.12),lineWidth:1)).accessibilityIdentifier(identifier)
  }
 }
 private func moneyInput(_ title:String,text:Binding<String>,identifier:String,help:String) -> some View {
  VStack(alignment:.leading,spacing:8) {
   HStack {
    label(title);Spacer(minLength:4)
    if let amount=PropertyInput.amount(text.wrappedValue),!preferences.hideBalances {
     Text(DisplayFormat.compactMoney(amount,currency:"INR")).font(.inter(.caption2,size:11)).foregroundStyle(HomeStyle.indigo).padding(.horizontal,8).padding(.vertical,2).background(HomeStyle.indigo.opacity(0.04),in:Capsule())
    }
   }
   HStack {
    Text("₹").foregroundStyle(HomeStyle.secondary)
    TextField("0",text:text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier(identifier)
   }.font(.inter(.caption,size:14)).padding(12).overlay(RoundedRectangle(cornerRadius:8).stroke(Color.primary.opacity(0.12),lineWidth:1))
   Text(help).font(.inter(.caption2,size:12)).foregroundStyle(HomeStyle.secondary)
  }
 }
 private var valuationDate: some View {
  VStack(alignment:.leading,spacing:8) {
   label("Valuation Date")
   DatePicker("Valuation date",selection:$date,in:...Date(),displayedComponents:.date).labelsHidden().datePickerStyle(.compact).tint(HomeStyle.indigo).padding(8).frame(maxWidth:.infinity,alignment:.leading).overlay(RoundedRectangle(cornerRadius:8).stroke(Color.primary.opacity(0.12),lineWidth:1)).accessibilityIdentifier("property-date")
  }
 }
 private var locationField: some View { input("Location / City",placeholder:"e.g. Bengaluru, KA",text:$location,identifier:"property-location") }
 private var projectedGain: some View {
  VStack(alignment:.leading,spacing:10) {
   HStack {
    Label("PROJECTED GAIN",systemImage:"chart.line.uptrend.xyaxis").font(.inter(.caption2,weight:.semibold,size:11)).tracking(0.5)
    Spacer(minLength:4)
    HomeSignedMoney(amount:metrics?.gain).font(.inter(.caption,weight:.semibold,size:13)).foregroundStyle(metrics?.gain.map { $0.value < 0 ? Color.red : DashboardStyle.positive } ?? HomeStyle.secondary)
   }
   if let metrics,metrics.value.value > 0,metrics.costKnown {
    GeometryReader { geometry in
     HStack(spacing:0) {
      Rectangle().fill(HomeStyle.secondary).frame(width:geometry.size.width*CGFloat(truncating:NSDecimalNumber(decimal:min(1,metrics.cost.value/metrics.value.value))))
      Rectangle().fill(HomeStyle.indigo)
     }.clipShape(Capsule())
    }.frame(height:8)
    HStack { Text("Basis: \(preferences.hideBalances ? "••••" : DisplayFormat.compactMoney(metrics.cost.value,currency:"INR"))");Spacer();Text("Unrealized: \(preferences.hideBalances ? "••••" : DisplayFormat.compactMoney(metrics.gain!.value,currency:"INR"))").foregroundStyle(HomeStyle.indigo) }.font(.inter(.caption2,weight:.medium,size:11))
   }
   Rectangle().fill(HomeStyle.border).frame(height:1)
   Label("Values remain unchanged until the next manual update.",systemImage:"info.circle").font(.inter(.caption2,size:12)).foregroundStyle(HomeStyle.secondary)
  }.padding(12).background(HomeStyle.fill,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(Color.primary.opacity(0.08),lineWidth:1))
 }
 private var footer: some View {
  VStack(spacing:12) {
   Button { Task { await save() } } label: {
    HStack { if dependencies.properties.isBusy { ProgressView() };Label(property == nil ? "Save Property to Portfolio" : "Save Property Changes",systemImage:"plus.circle") }.font(.inter(.headline,weight:.semibold,size:16)).frame(maxWidth:.infinity).padding(.vertical,16).background(HomeStyle.indigo,in:RoundedRectangle(cornerRadius:8)).foregroundStyle(.white)
   }.disabled(!canSave || !authorized).opacity(canSave && authorized ? 1 : 0.5).accessibilityIdentifier("save-property")
   Button("Discard") { dismiss() }.font(.inter(.caption,size:14)).foregroundStyle(HomeStyle.secondary).accessibilityIdentifier("discard-property")
  }.padding(16).background(HomeStyle.card).overlay(alignment:.top) { Rectangle().fill(HomeStyle.border).frame(height:1) }
 }
 private func save() async {
  guard canSave,authorized,scope == "\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "signed-out")" else { return }
  dependencies.properties.configure(address:dependencies.zerodha.address,token:dependencies.zerodha.sessionToken)
  if await dependencies.properties.save(id:id,name:name.trimmingCharacters(in:.whitespacesAndNewlines),value:PropertyInput.clean(value),date:PropertyInput.dateFormatter.string(from:date),cost:PropertyInput.clean(cost),classification:classification,location:location.trimmingCharacters(in:.whitespacesAndNewlines)) {
   await dependencies.portfolio.refresh();dismiss()
  }
 }
}
