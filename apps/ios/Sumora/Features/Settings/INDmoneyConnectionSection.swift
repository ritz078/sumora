import SwiftUI

struct INDmoneyConnectionSection: View {
 @Environment(AppDependencies.self) private var dependencies
 @Environment(PortfolioStore.self) private var store
 @State private var confirmDisconnect = false
 private var scope: String { "\(dependencies.zerodha.address):\(dependencies.auth.sessionToken ?? "signed-out")" }
 var body: some View {
  @Bindable var indmoney = dependencies.indmoney
  Section {
   if dependencies.auth.sessionToken == nil {
    Text("Sign in to Sumora before connecting INDmoney.").font(.footnote).foregroundStyle(.secondary)
   } else {
    if let status = indmoney.status, status.connected {
     LabeledContent("Status",value:status.status == "reconnect" ? "Reconnect required" : "Connected")
     if let ms = status.lastSyncAt {
      Text("Last sync: \(Date(timeIntervalSince1970:ms/1000).formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)
     }
     if status.status == "reconnect" { Button("Reconnect INDmoney") { Task { await indmoney.connect(); if indmoney.status?.connected == true { await indmoney.sync(); if dependencies.isLivePortfolio { await store.refresh() } } } } }
     Button("Sync now") { Task { await indmoney.sync(); if dependencies.isLivePortfolio { await store.refresh() } } }
     Button("Disconnect INDmoney",role:.destructive) { confirmDisconnect = true }
    } else {
     Button("Connect INDmoney") { Task { await indmoney.connect(); if indmoney.status?.connected == true { await indmoney.sync(); if dependencies.isLivePortfolio { await store.refresh() } } } }.accessibilityIdentifier("connect-indmoney")
    }
   }
   if indmoney.isBusy { ProgressView("Updating INDmoney…") }
   if let error = indmoney.errorMessage ?? indmoney.status?.error { Text(error).font(.footnote).foregroundStyle(.orange) }
  } header: { Text("INDmoney · US stocks") } footer: {
   Text("Read-only access to US stocks held in your INDmoney account. Sign in on INDmoney’s page and approve access there. Credentials stay encrypted on the server.")
  }
  .disabled(indmoney.isBusy)
  .task(id:scope) {
   indmoney.configure(address:dependencies.zerodha.address,token:dependencies.auth.sessionToken)
   await indmoney.refresh()
  }
  .confirmationDialog("Disconnect INDmoney?",isPresented:$confirmDisconnect,titleVisibility:.visible) {
   Button("Disconnect",role:.destructive) { Task { await indmoney.disconnect(); if dependencies.isLivePortfolio { await store.refresh() } } }
  } message: { Text("INDmoney holdings will be removed from Sumora. Your INDmoney account is unchanged.") }
 }
}
