import SwiftUI

struct GmailConnectionSection: View {
 @Environment(AppDependencies.self) private var dependencies
 @State private var confirmDisconnect = false
 private var scope: String { "\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "signed-out")" }
 var body: some View {
  @Bindable var gmail = dependencies.gmail
  Section {
   if dependencies.zerodha.sessionToken == nil {
    Text("Connect Zerodha first to sign in to Sumora, then link Gmail.")
     .font(.footnote).foregroundStyle(.secondary)
    Button("Connect Gmail") {}.disabled(true).accessibilityIdentifier("connect-gmail")
   } else if let status = gmail.status, status.connected {
    Label(status.email ?? "Gmail connected", systemImage: "envelope")
    Text(status.status == "reconnect" ? "Reconnect Gmail to restore access." : "Connected")
     .font(.footnote).foregroundStyle(.secondary)
    if status.status == "reconnect" { Button("Reconnect Gmail") { Task { await gmail.connect() } } }
    Button("Refresh connection status") { Task { await gmail.refresh() } }
    Button("Disconnect Gmail", role: .destructive) { confirmDisconnect = true }
   } else {
    Button("Connect Gmail") { Task { await gmail.connect() } }.accessibilityIdentifier("connect-gmail")
    Button("Refresh connection status") { Task { await gmail.refresh() } }
   }
   if gmail.isBusy { ProgressView("Updating Gmail…") }
   if let error = gmail.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
  } header: { Text("Gmail") } footer: {
   Text("Read-only Gmail access for Gullak monthly statements. Configure gold decryption and sync in Settings. Stock contract-note collection is disabled.")
  }
  .disabled(gmail.isBusy)
  .task(id: scope) {
   gmail.configure(address: dependencies.zerodha.address, token: dependencies.zerodha.sessionToken)
   await gmail.refresh()
  }
  .confirmationDialog("Disconnect Gmail?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
   Button("Disconnect Gmail", role: .destructive) { Task { await gmail.disconnect() } }
  }
 }
}
