import SwiftUI

struct GmailDocumentSyncControls: View {
 @Environment(AppDependencies.self) private var dependencies
 var body: some View {
  @Bindable var gmail = dependencies.gmail
  Button("Sync Gmail documents") { Task { await dependencies.syncGmailDocuments() } }
   .disabled(gmail.isBusy || gmail.status?.status != "connected")
   .accessibilityIdentifier("sync-gmail-documents")
  if let progress = gmail.syncProgress { ProgressView(progress).font(.footnote) }
  if let message = gmail.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
  ForEach(gmail.syncResults) { result in
   LabeledContent(result.source.title, value: result.error != nil ? "Needs attention" : result.pending ? "More remaining" : result.status == "busy" ? "Already syncing" : "\(result.imported) imported")
    .font(.footnote)
  }
 }
}
struct GmailDocumentsSection: View {
 @Environment(AppDependencies.self) private var dependencies
 private var scope: String { "\(dependencies.zerodha.address):\(dependencies.zerodha.sessionToken ?? "signed-out")" }
 var body: some View {
  Section {
   GmailDocumentSyncControls()
   if dependencies.gmail.status?.status != "connected" {
    Text("Connect Gmail under Connections, then configure your document sources below.").font(.footnote).foregroundStyle(.secondary)
   }
   if let error = dependencies.gmail.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
  } header: { Text("Gmail documents") } footer: {
   Text("One sync updates all enabled Gullak, HDFC, NPS and CDSL bond sources. Failed imports retain your previous balances.")
  }
  .task(id:scope) {
   dependencies.gmail.configure(address:dependencies.zerodha.address,token:dependencies.zerodha.sessionToken)
   await dependencies.gmail.refresh()
  }
 }
}
