import SwiftUI

struct PropertiesView: View {
 @Environment(AppDependencies.self) private var dependencies
 @Environment(AppPreferences.self) private var preferences
 @State private var editing: PropertyDraft?
 @State private var removal: PropertyEntry?
 @State private var confirmRemove = false
 private var connection: PropertiesConnection { dependencies.properties }
 private var scope:String { "\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "signed-out")" }
 var body: some View {
  List {
   Section {
    ForEach(connection.properties) { property in
     Button { connection.errorMessage = nil; editing = PropertyDraft(id:property.id,entry:property) } label: {
      VStack(alignment:.leading,spacing:6) {
       HStack { Text(property.name).foregroundStyle(.primary); Spacer(); MoneyText(amount:DecimalValue(property.ownedValue)) }
       Text("\(DisplayFormat.decimal(property.ownershipPercent.value))% ownership · manually entered").font(.caption).foregroundStyle(.secondary)
       Text("Valued \(property.valuationDate)").font(.caption).foregroundStyle(.secondary)
      }
     }.swipeActions { Button("Remove",role:.destructive) { removal = property; confirmRemove = true } }
    }
    if connection.properties.isEmpty { Text("Add a property to include your ownership share in net worth.").foregroundStyle(.secondary) }
    Button { connection.errorMessage = nil; editing = PropertyDraft(id:UUID().uuidString.lowercased(),entry:nil) } label: { Label("Add property",systemImage:"plus") }
     .accessibilityIdentifier("add-property")
   } footer: { Text("Net worth uses estimated property value × your ownership percentage. Values remain as entered until you update them. No automatic appreciation is applied.") }
   if connection.isBusy { ProgressView("Updating properties…") }
   if let error = connection.errorMessage { Text(error).foregroundStyle(.orange).font(.footnote) }
  }.navigationTitle("Real estate")
   .disabled(connection.isBusy || dependencies.zerodha.sessionToken == nil)
   .onChange(of:scope) { _,_ in editing = nil; removal = nil;confirmRemove = false }
   .task(id:scope) { connection.configure(address:dependencies.zerodha.address,token:dependencies.zerodha.sessionToken);await connection.refresh() }
   .refreshable { await connection.refresh() }
   .sheet(item:$editing) { draft in PropertyEditor(id:draft.id,property:draft.entry,scope:scope) }
   .confirmationDialog("Remove property?",isPresented:$confirmRemove,presenting:removal) { property in
    Button("Remove property",role:.destructive) { Task { if await connection.remove(id:property.id),dependencies.isLivePortfolio { await dependencies.portfolio.refresh() } } }
   } message: { property in Text("\(property.name) will be removed from net worth. Sale proceeds are not added automatically.") }
 }
 private struct PropertyDraft:Identifiable { let id:String;let entry:PropertyEntry? }
}

struct PropertyEditor: View {
 @Environment(AppDependencies.self) private var dependencies
 @Environment(\.dismiss) private var dismiss
 let id:String
 let scope:String
 let property:PropertyEntry?
 @State private var name:String
 @State private var value:String
 @State private var ownership:String
 @State private var cost:String
 @State private var date:Date
 init(id:String,property:PropertyEntry?,scope:String) {
  self.id=id;self.property=property;self.scope=scope
  _name=State(initialValue:property?.name ?? "")
  _value=State(initialValue:property.map { NSDecimalNumber(decimal:$0.estimatedValue.value).stringValue } ?? "")
  _ownership=State(initialValue:property.map { NSDecimalNumber(decimal:$0.ownershipPercent.value).stringValue } ?? "100")
  _cost=State(initialValue:property?.purchaseCost.map { NSDecimalNumber(decimal:$0.value).stringValue } ?? "")
  _date=State(initialValue:property.flatMap { Self.dateFormatter.date(from:$0.valuationDate) } ?? Date())
 }
 private static var dateFormatter:DateFormatter { let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=TimeZone(identifier:"Asia/Kolkata");f.dateFormat="yyyy-MM-dd";return f }
 private func clean(_ text:String)->String { text.replacingOccurrences(of:",",with:"").trimmingCharacters(in:.whitespacesAndNewlines) }
 private var valid:Bool {
  guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count<=80,
   let amount=Decimal(string:clean(value)),amount>=0,
   let share=Decimal(string:clean(ownership)),share>0,share<=100 else { return false }
  return clean(cost).isEmpty || (Decimal(string:clean(cost)).map { $0>=0 } ?? false)
 }
 var body: some View {
  NavigationStack {
   Form {
    Section("Property") { TextField("Property name",text:$name).accessibilityIdentifier("property-name") }
    Section {
     TextField("Full property value (INR)",text:$value).keyboardType(.decimalPad).accessibilityIdentifier("property-value")
     TextField("Your ownership (%)",text:$ownership).keyboardType(.decimalPad).accessibilityIdentifier("property-ownership")
     DatePicker("Valuation date",selection:$date,in:...Date(),displayedComponents:.date)
     if let amount=Decimal(string:clean(value)),let share=Decimal(string:clean(ownership)),amount>=0,share>0,share<=100 {
      LabeledContent("Your value in net worth") { MoneyText(amount:DecimalValue(amount*share/100)) }
     }
    } header: { Text("Valuation") } footer: { Text("Enter the full property value; your ownership share is calculated automatically. This is your estimate, not a live market valuation.") }
    Section { TextField("Full purchase cost (optional, INR)",text:$cost).keyboardType(.decimalPad) } footer: { Text("For reference only; purchase cost does not change net worth.") }
    if let error=dependencies.properties.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
   }.navigationTitle(property == nil ? "Add property" : "Edit property")
    .toolbar {
     ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
     ToolbarItem(placement:.confirmationAction) { Button("Save") { Task {
      guard scope == "\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "signed-out")" else { dismiss();return }
      if await dependencies.properties.save(id:id,name:name.trimmingCharacters(in:.whitespacesAndNewlines),value:clean(value),ownership:clean(ownership),date:Self.dateFormatter.string(from:date),cost:clean(cost)) {
       if dependencies.isLivePortfolio { await dependencies.portfolio.refresh() };dismiss()
      }
     } }.disabled(!valid || dependencies.properties.isBusy).accessibilityIdentifier("save-property") }
    }.disabled(dependencies.properties.isBusy).interactiveDismissDisabled(dependencies.properties.isBusy)
  }
 }
}
