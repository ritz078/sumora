import SwiftUI

struct NPSConnectionSection: View {
 @Environment(AppDependencies.self) private var dependencies
 @Environment(PortfolioStore.self) private var store
 @State private var password = ""
 @State private var confirmRemove = false
 private var scope: String { "\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "signed-out")" }
 var body: some View {
  @Bindable var nps = dependencies.nps
  Section {
   if dependencies.zerodha.sessionToken == nil {
    Text("Sign in to Sumora and connect Gmail to import NPS statements.").font(.footnote).foregroundStyle(.secondary)
   } else {
    if let balance = nps.status?.balance {
     LabeledContent("NPS statement value") { MoneyText(amount:balance.total,currency:"INR",fractionDigits:2) }
     Text("\(balance.count) schemes · valued as of \(balance.statement_date)").font(.caption).foregroundStyle(.secondary)
    }
    if nps.status?.gmailConnected == false {
     Text("Connect Gmail under Connections before syncing NPS.").font(.footnote).foregroundStyle(.secondary)
    }
    if nps.status?.configured != true {
     Button("Enable NPS imports") { Task { await nps.enable() } }
      .disabled(nps.status?.gmailConnected != true).accessibilityIdentifier("enable-nps")
    }
    DisclosureGroup("Decryption password override") {
    SecureField("12-digit PRAN",text:$password).keyboardType(.numberPad)
     .accessibilityIdentifier("nps-password")
    Button(nps.status?.configured == true ? "Update decryption password" : "Save decryption password") {
     Task { if await nps.save(password:password) { password = "" } }
    }.disabled(password.count != 12 || !password.allSatisfy(\.isNumber)).accessibilityIdentifier("save-nps-password")
    }
    Button("Sync NPS") { Task { await nps.sync(); if dependencies.isLivePortfolio { await store.refresh() } } }
     .disabled(nps.status?.configured != true || nps.status?.gmailConnected != true).accessibilityIdentifier("sync-nps")
    Button("Refresh NPS status") { Task { await nps.refresh() } }
    if nps.status?.configured == true { Button("Stop NPS imports",role:.destructive) { confirmRemove = true } }
    if let ms = nps.status?.lastSyncAt {
     Text("Last sync attempt: \(Date(timeIntervalSince1970:ms/1000).formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)
    }
   }
   if nps.isBusy { ProgressView("Updating NPS…") }
   if let message = nps.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
   if let error = nps.errorMessage ?? nps.status?.error { Text(error).font(.footnote).foregroundStyle(.orange) }
  } header: { Text("NPS schemes") } footer: {
   Text("Imports KFintech NPS statements from connected Gmail. When available, the verified email supplies the PRAN used to decrypt its PDF; it is stored encrypted. Net worth uses scheme balances as of the statement’s valuation date. No live NAV or daily gain is estimated. Failed imports retain the last balance.")
  }
  .disabled(nps.isBusy)
  .task(id:scope) {
   password = ""
   nps.configure(address:dependencies.zerodha.address,token:dependencies.zerodha.sessionToken)
   await nps.refresh()
  }
  .confirmationDialog("Stop NPS imports?",isPresented:$confirmRemove,titleVisibility:.visible) {
   Button("Stop imports",role:.destructive) { Task { await nps.disconnect() } }
  } message: { Text("Automatic NPS imports will stop. Your recorded NPS balances will remain visible.") }
 }
}
