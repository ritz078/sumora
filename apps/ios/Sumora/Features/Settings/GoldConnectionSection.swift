import SwiftUI

struct GoldConnectionSection: View {
 @Environment(AppDependencies.self) private var dependencies
 @Environment(AppPreferences.self) private var preferences
 @Environment(PortfolioStore.self) private var store
 @State private var mobile = ""
 @State private var confirmRemove = false
 private var scope: String { "\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "signed-out")" }
 var body: some View {
  @Bindable var gold = dependencies.gold
  Section {
   if dependencies.zerodha.sessionToken == nil {
    Text("Connect Zerodha to sign in, then connect Gmail under Connections to import Gullak gold.")
     .font(.footnote).foregroundStyle(.secondary)
   } else {
    if let quote = gold.status?.quote {
     LabeledContent("24K gold · India") { MoneyText(amount: quote.price, currency: "INR", fractionDigits: 2) }
     Text("Per gram · price dated \(quote.date)").font(.caption).foregroundStyle(.secondary)
    }
    if let balance = gold.status?.balance {
     LabeledContent("Recorded gold") { Text(preferences.hideBalances ? "••••" : "\(DisplayFormat.decimal(balance.grams.value,digits:4)) g") }
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
    Button("Sync Gullak") { Task { await gold.sync(); if dependencies.isLivePortfolio { await store.refresh() } } }
     .disabled(gold.status?.configured != true || gold.status?.gmailConnected != true)
     .accessibilityIdentifier("sync-gullak")
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
  } header: { Text("Gullak gold") } footer: {
   Text("Your mobile number derives the statement password; only the encrypted password is stored. Gold value uses the daily Snapdata / IBJA Indian benchmark, which may be provisional. It is an estimate, not Gullak’s sell quote. Monthly statements update recorded grams; daily prices do not update the balance.")
  }
  .disabled(gold.isBusy)
  .task(id:scope) {
   mobile = ""
   gold.configure(address:dependencies.zerodha.address,token:dependencies.zerodha.sessionToken)
   await gold.refresh()
  }
  .confirmationDialog("Remove the decryption password?",isPresented:$confirmRemove,titleVisibility:.visible) {
   Button("Remove password",role:.destructive) { Task { await gold.removePassword() } }
  } message: { Text("Automatic Gullak imports will stop. Your recorded gold balance will remain visible.") }
 }
}
