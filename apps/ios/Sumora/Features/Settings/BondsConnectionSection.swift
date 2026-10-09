import SwiftUI

struct BondsConnectionSection: View {
 @Environment(AppDependencies.self) private var dependencies
 @State private var password = ""
 @State private var confirmRemove = false
 private var scope: String { "\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "signed-out")" }
 private var validPAN: Bool { password.range(of: "^[A-Z]{5}[0-9]{4}[A-Z]$",options:.regularExpression) != nil }
 var body: some View {
  @Bindable var bonds = dependencies.bonds
  Section {
   if dependencies.zerodha.sessionToken == nil {
    Text("Sign in to Sumora and connect Gmail to import bond statements.").font(.footnote).foregroundStyle(.secondary)
   } else {
    if let balance = bonds.status?.balance {
     LabeledContent("CAS bond value") { MoneyText(amount:balance.total,currency:"INR",fractionDigits:2) }
     Text("\(balance.count) bonds · valued as of \(balance.statement_date)").font(.caption).foregroundStyle(.secondary)
     if balance.redemptionChecks > 0 {
      Label("Maturity passed for \(balance.redemptionChecks) bond(s). Verify redemption; the last statement balance is retained.",systemImage:"exclamationmark.circle").font(.footnote).foregroundStyle(.orange)
     }
    }
    if bonds.status?.gmailConnected == false { Text("Connect Gmail under Connections first.").font(.footnote).foregroundStyle(.secondary) }
    SecureField("First holder’s PAN",text:$password).textInputAutocapitalization(.characters).autocorrectionDisabled()
     .onChange(of:password) { _,value in password = value.uppercased() }
     .accessibilityIdentifier("bonds-pan")
    Button(bonds.status?.configured == true ? "Update decryption PAN" : "Enable bond imports") {
     Task { if await bonds.save(password:password) { password = "" } }
    }.disabled(!validPAN || bonds.status?.gmailConnected != true).accessibilityIdentifier("save-bonds-pan")
    Button("Refresh bond status") { Task { await bonds.refresh() } }
    if bonds.status?.configured == true { Button("Stop bond imports",role:.destructive) { confirmRemove = true } }
    if let ms = bonds.status?.lastSyncAt {
     Text("Last sync attempt: \(Date(timeIntervalSince1970:ms/1000).formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)
    }
   }
   if bonds.isBusy { ProgressView("Updating bonds…") }
   if let message = bonds.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
   if let error = bonds.errorMessage ?? bonds.status?.error { Text(error).font(.footnote).foregroundStyle(.orange) }
  } header: { Text("Bonds · CDSL CAS") } footer: {
   Text("Imports NSDL bond closing balances from CDSL CAS emails. Your PAN is encrypted on the server and used only for decryption. Tap Sync Gmail documents after saving. Values use the statement’s price or face value, not live quotes. Coupon interest and returns are not estimated. Unsupported statements retain the last balances.")
  }
  .disabled(bonds.isBusy || dependencies.gmail.isBusy)
  .task(id:scope) {
   password = ""
   bonds.configure(address:dependencies.zerodha.address,token:dependencies.zerodha.sessionToken)
   await bonds.refresh()
  }
  .confirmationDialog("Stop bond imports?",isPresented:$confirmRemove,titleVisibility:.visible) {
   Button("Stop imports",role:.destructive) { Task { await bonds.disconnect() } }
  } message: { Text("Automatic bond imports will stop. Your recorded balances will remain visible.") }
 }
}
