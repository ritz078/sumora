import SwiftUI

struct SettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppPreferences.self) private var preferences
    @Environment(PortfolioStore.self) private var store

    var body: some View {
        @Bindable var preferences = preferences
        @Bindable var dependencies = dependencies
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "chart.pie.fill").font(.largeTitle).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sumora").font(.title2.bold())
                        Text("Your wealth, in one view.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                DemoBadge()
            }
            Section("Preferences") {
                Toggle("Hide balances", isOn: $preferences.hideBalances)
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Reporting currency", value: "INR · Indian rupee")
            }
            Section("Accounts") {
                NavigationLink { ConnectionsView() } label: { Label("Connections", systemImage: "link") }
            }
            Section("Manual assets") {
                NavigationLink { RealEstateView() } label: { Label("Real estate",systemImage:"house.fill") }
                if dependencies.zerodha.sessionToken == nil { Text("Sign in to add manual properties.").font(.footnote).foregroundStyle(.secondary) }
            }
            GmailDocumentsSection()
            GoldConnectionSection()
            HDFCConnectionSection()
            NPSConnectionSection()
            BondsConnectionSection()
            INDmoneyConnectionSection()
            Section {
                LabeledContent("Current source", value: dependencies.isLivePortfolio ? "Zerodha" : dependencies.usesRemoteAPI ? "Sample API" : "Offline samples")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Portfolio data source")
                    .accessibilityValue(dependencies.isLivePortfolio ? "Zerodha" : dependencies.usesRemoteAPI ? "Sample API" : "Offline samples")
                    .accessibilityIdentifier("portfolio-source")
                TextField("API address", text: $dependencies.apiAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .accessibilityIdentifier("api-address")
                Button("Connect to sample API") { Task { await dependencies.selectSource(remote: true) } }
                    .accessibilityIdentifier("connect-api").disabled(store.isRefreshing)
                Button("Use offline samples") { Task { await dependencies.selectSource(remote: false) } }
                    .disabled(store.isRefreshing)
                if let error = dependencies.configurationError { Text(error).foregroundStyle(.red).font(.footnote) }
            } header: { Text("Portfolio data") } footer: {
                Text("Both sources contain illustrative data. The API uses network requests; offline samples load from this device. API failures remain visible until a successful refresh.")
            }
            Section {
                ForEach(DemoScenario.allCases) { scenario in
                    Button {
                        Task { await dependencies.selectScenario(scenario) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(scenario.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                Text(scenario.explanation).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if dependencies.scenario == scenario {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                            }
                        }.padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("scenario-\(scenario.rawValue)")
                    .disabled(store.isRefreshing)
                }
            } header: {
                Text("Explore demo scenarios")
            } footer: {
                Text("Switch scenarios to explore complete, missing, outdated, empty, and failed data. Sample clock: 6 Oct 2026.")
            }
            Section("About") {
                LabeledContent("Version", value: "1.0 (1)")
                Text("Connect Zerodha under Connections to import your account. Demo mode uses illustrative data from the sample API or this device.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Settings")
    }
}
