import SwiftUI

struct GoldConnectionSection: View {
 @Environment(AppDependencies.self) private var dependencies
 @Environment(AppPreferences.self) private var preferences
 @Environment(PortfolioStore.self) private var store
 @State private var mobile = ""
 @State private var confirmRemove = false
 private var scope: String { "\(dependencies.zerodha.address):\(dependencies.auth.sessionToken ?? "signed-out")" }
 var body: some View {
  @Bindable var gold = dependencies.gold
  Section {
   if dependencies.auth.sessionToken == nil {
    Text("Sign in to Sumora, then connect Gmail to import Gullak gold.")
     .font(.footnote).foregroundStyle(.secondary)
   } else {
    if let quote = gold.status?.quote {
     LabeledContent("24K gold · India") { MoneyText(amount: quote.price, currency: "INR", fractionDigits: 2) }
     Text("Per gram · price dated \(quote.date)").font(.caption).foregroundStyle(.secondary)
    }
    if let balance = gold.status?.balance {
     LabeledContent("Recorded gold") { Text(preferences.hideBalances ? "••••" : "\(DisplayFormat.decimal(balance.grams.value,digits:4)) g") }
     if let silver = balance.silver_grams {
      LabeledContent("Recorded silver") { Text(preferences.hideBalances ? "••••" : "\(DisplayFormat.decimal(silver.value,digits:4)) g") }
     } else {
      Text("Silver balance has not been imported. Sync Gullak to update it.").font(.caption).foregroundStyle(.secondary)
     }
     Text("Balance dated \(balance.balance_date) · statement ending \(balance.period_end)")
      .font(.caption).foregroundStyle(.secondary)
    }
    if gold.status?.gmailConnected == false {
     Text("Connect Gmail under Connections before syncing Gullak.").font(.footnote).foregroundStyle(.secondary)
    }
    SecureField("Gullak mobile number", text: $mobile)
     .keyboardType(.numberPad).textContentType(.telephoneNumber)
     .accessibilityIdentifier("gullak-mobile")
    Button(gold.status?.configured == true ? "Update decryption password" : "Save decryption password") {
     Task { if await gold.save(mobile: mobile) { mobile = "" } }
    }.disabled(mobile.count != 10).accessibilityIdentifier("save-gullak-password")
    Button("Refresh gold status") { Task { await gold.refresh() } }
    if gold.status?.configured == true {
     Button("Remove decryption password",role:.destructive) { confirmRemove = true }
    }
    if let milliseconds = gold.status?.lastSyncAt {
     Text("Last sync attempt: \(Date(timeIntervalSince1970:milliseconds/1000).formatted(date:.abbreviated,time:.shortened))")
      .font(.caption).foregroundStyle(.secondary)
    }
   }
   if gold.isBusy { ProgressView("Updating gold…") }
   if let message = gold.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
   if let error = gold.errorMessage ?? gold.status?.error { Text(error).font(.footnote).foregroundStyle(.orange) }
   if let error = gold.status?.priceError { Text(error).font(.footnote).foregroundStyle(.orange) }
  } header: { Text("Gullak gold & silver") } footer: {
   Text("Your mobile number derives the statement password; only the encrypted password is stored. Gold value uses the daily Snapdata / IBJA Indian benchmark, which may be provisional. It is an estimate, not Gullak’s sell quote. Monthly statements update recorded gold and silver grams. Silver is recorded without a market valuation; daily gold prices do not update either balance.")
  }
  .disabled(gold.isBusy || dependencies.gmail.isBusy)
  .task(id:scope) {
   mobile = ""
   gold.configure(address:dependencies.zerodha.address,token:dependencies.auth.sessionToken)
   await gold.refresh()
  }
  .confirmationDialog("Remove the decryption password?",isPresented:$confirmRemove,titleVisibility:.visible) {
   Button("Remove password",role:.destructive) { Task { await gold.removePassword() } }
  } message: { Text("Automatic Gullak imports will stop. Your recorded gold balance will remain visible.") }
 }
}
