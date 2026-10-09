import SwiftUI

struct ConnectionsView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(AppDependencies.self) private var dependencies
    @State private var selectedConnection: Connection?

    var body: some View {
        List {
            Section {
                Text("One view of your investments, wherever they live.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                Text(dependencies.zerodha.sessionToken == nil ? "Connect your Zerodha account to import equity holdings and Coin mutual funds." : "Your Zerodha account is linked. Kite sessions need periodic reconnection.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button(dependencies.zerodha.sessionToken == nil ? "Connect Zerodha" : "Reconnect Zerodha") {
                    Task { await dependencies.connectZerodha() }
                }.accessibilityIdentifier("connect-zerodha").disabled(dependencies.zerodha.isConnecting)
                if dependencies.zerodha.isConnecting { ProgressView("Opening Zerodha login…") }
                if dependencies.zerodha.sessionToken != nil {
                    Button("Show Zerodha portfolio") { Task { await dependencies.showZerodhaPortfolio() } }
                        .disabled(dependencies.zerodha.isConnecting)
                    Button("Disconnect Zerodha", role: .destructive) { Task { await dependencies.disconnectZerodha() } }
                        .disabled(dependencies.zerodha.isConnecting)
                }
            } header: { Text("Zerodha") } footer: {
                Text("Login opens Zerodha's secure page. Broker credentials stay on the server. Pledged and margin-funded holdings are not yet supported.")
            }
            GmailConnectionSection()
            Section("Your accounts") {
                if let connections = store.snapshot?.connections, !connections.isEmpty {
                    ForEach(connections) { connection in
                        Button { selectedConnection = connection } label: {
                            ConnectionRow(connection: connection)
                        }.buttonStyle(.plain)
                    }
                } else {
                    ContentUnavailableView("No accounts connected", systemImage: "link", description: Text("Explore a sample portfolio to see how your accounts come together."))
                }
            }
            Section {
                DemoBadge()
                Text(dependencies.isLivePortfolio ? "These holdings were imported from your Zerodha account. Prices are the latest values supplied by Kite; they are not streaming quotes." : "The accounts below are samples. Use Connect Zerodha above to import your account.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Connections")
        .sheet(item: $selectedConnection) { connection in
            NavigationStack {
                List {
                    Section { ConnectionRow(connection: connection) }
                    Section("Last successful sync") {
                        Text(connection.lastSyncAt.map { DisplayFormat.age($0, relativeTo: dependencies.demoDate) } ?? "Never synced")
                    }
                    Section("Connection status") {
                        Text(dependencies.isLivePortfolio ? connection.description : (connection.status == .attention ? "This sample account needs reconnection." : "This sample account is connected."))
                    }
                }
                .navigationTitle(connection.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedConnection = nil } } }
            }
        }
    }
}

struct ConnectionRow: View {
    @Environment(AppDependencies.self) private var dependencies
    let connection: Connection
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(connection.symbol).font(.headline)
                .frame(width: 40, height: 40)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(connection.name).font(.subheadline.weight(.semibold))
                Text(connection.description).font(.caption).foregroundStyle(.secondary)
                Text(connection.lastSyncAt.map { "Synced \(DisplayFormat.age($0, relativeTo: dependencies.demoDate))" } ?? "Not synced")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: connection.status == .connected ? "checkmark.circle.fill" : connection.status == .attention ? "exclamationmark.circle.fill" : "minus.circle")
                .foregroundStyle(connection.status == .connected ? Color.accentColor : .orange)
                .accessibilityLabel(connection.status == .connected ? "Connected" : connection.status == .attention ? "Needs reconnection" : "Disconnected")
        }.padding(.vertical, 4)
    }
}
