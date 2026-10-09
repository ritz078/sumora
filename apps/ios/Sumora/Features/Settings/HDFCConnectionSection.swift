import SwiftUI

struct HDFCConnectionSection: View {
 @Environment(AppDependencies.self) private var dependencies
 @Environment(PortfolioStore.self) private var store
 @State private var password = ""
 @State private var confirmRemove = false
 private var scope: String { "\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "signed-out")" }
 var body: some View {
  @Bindable var hdfc = dependencies.hdfc
  Section {
   if dependencies.zerodha.sessionToken == nil {
    Text("Sign in to Sumora and connect Gmail to import HDFC statements.").font(.footnote).foregroundStyle(.secondary)
   } else {
    if let balance = hdfc.status?.balance {
     LabeledContent("FD maturity value") { MoneyText(amount:balance.total,currency:"INR",fractionDigits:2) }
     Text("\(balance.count) fixed deposits · statement dated \(balance.statement_date)").font(.caption).foregroundStyle(.secondary)
    }
    if hdfc.status?.gmailConnected == false {
     Text("Connect Gmail under Connections before syncing HDFC.").font(.footnote).foregroundStyle(.secondary)
    }
    SecureField("HDFC Customer ID",text:$password).keyboardType(.numberPad)
     .accessibilityIdentifier("hdfc-password")
    Button(hdfc.status?.configured == true ? "Update decryption password" : "Save decryption password") {
     Task { if await hdfc.save(password:password) { password = "" } }
    }.disabled(password.count < 6 || password.count > 20).accessibilityIdentifier("save-hdfc-password")
    Button("Refresh HDFC status") { Task { await hdfc.refresh() } }
    if hdfc.status?.configured == true { Button("Remove decryption password",role:.destructive) { confirmRemove = true } }
    if let ms = hdfc.status?.lastSyncAt {
     Text("Last sync attempt: \(Date(timeIntervalSince1970:ms/1000).formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)
    }
   }
   if hdfc.isBusy { ProgressView("Updating fixed deposits…") }
   if let message = hdfc.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
   if let error = hdfc.errorMessage ?? hdfc.status?.error { Text(error).font(.footnote).foregroundStyle(.orange) }
  } header: { Text("HDFC fixed deposits") } footer: {
   Text("Your Customer ID decrypts the monthly combined statement and is stored encrypted. Net worth includes the bank’s stated FD maturity amounts, including future interest. These are future payouts, not amounts available to withdraw today. Daily interest is not estimated. New statements replace the recorded FD list; failed imports retain the last balance.")
  }
  .disabled(hdfc.isBusy || dependencies.gmail.isBusy)
  .task(id:scope) {
   password = ""
   hdfc.configure(address:dependencies.zerodha.address,token:dependencies.zerodha.sessionToken)
   await hdfc.refresh()
  }
  .confirmationDialog("Remove the decryption password?",isPresented:$confirmRemove,titleVisibility:.visible) {
   Button("Remove password",role:.destructive) { Task { await hdfc.removePassword() } }
  } message: { Text("Automatic HDFC imports will stop. Your recorded FD balances will remain visible.") }
 }
}
