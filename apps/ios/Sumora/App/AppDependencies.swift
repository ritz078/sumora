import Foundation
import Observation

@MainActor @Observable
final class AppDependencies {
    let portfolio: PortfolioStore
    let preferences: AppPreferences
    let zerodha: ZerodhaConnection
    let gmail = GmailConnection()
    private(set) var isLivePortfolio = false
    private(set) var scenario: DemoScenario = .complete
    private(set) var usesRemoteAPI = true
    var apiAddress: String
    var configurationError: String?
    @ObservationIgnored private let defaults: UserDefaults
    // A fixed clock makes the sample history and freshness labels reproducible.
    var demoDate: Date { isLivePortfolio ? Date() : ISO8601DateFormatter().date(from: "2026-10-06T06:00:00Z")! }

    init() {
        preferences = AppPreferences()
        let arguments = ProcessInfo.processInfo.arguments
        let isUITest = arguments.contains("--ui-testing")
        defaults = isUITest ? UserDefaults(suiteName: "com.ritz078.sumora.ui-tests")! : .standard
        let address = isUITest ? "http://localhost:8787" :
            APIConfiguration.savedAddress(in: defaults)
        apiAddress = address
        let connection = ZerodhaConnection(address: address, restoreSession: !isUITest)
        zerodha = connection
        let initial = arguments.first(where: { $0.hasPrefix("--scenario=") })
            .flatMap { DemoScenario(rawValue: String($0.dropFirst("--scenario=".count))) } ?? .complete
        scenario = initial
        let remote = !arguments.contains("--ui-testing") && !arguments.contains("--offline-demo")
        usesRemoteAPI = remote
        let live = remote && connection.sessionToken != nil && (defaults.object(forKey: "useZerodhaPortfolio") as? Bool ?? true)
        isLivePortfolio = live
        if remote, let url = APIConfiguration.baseURL(address) {
            portfolio = PortfolioStore(api: HTTPPortfolioAPI(baseURL: url, scenario: initial, sessionToken: live ? connection.sessionToken : nil))
        } else if remote {
            portfolio = PortfolioStore(api: UnconfiguredPortfolioAPI())
        } else {
            portfolio = PortfolioStore(api: MockPortfolioAPI(scenario: initial))
        }
    }

    func selectScenario(_ scenario: DemoScenario) async {
        let wasLive = isLivePortfolio
        isLivePortfolio = false
        defaults.set(false, forKey: "useZerodhaPortfolio")
        self.scenario = scenario
        portfolio.replaceAPI(currentAPI(), clearSnapshot: wasLive || scenario != .failure)
        await portfolio.refresh()
    }

    func selectSource(remote: Bool) async {
        if remote && APIConfiguration.baseURL(apiAddress) == nil {
            configurationError = HTTPPortfolioError.configuration.localizedDescription
            return
        }
        configurationError = nil
        usesRemoteAPI = remote
        isLivePortfolio = false
        defaults.set(false, forKey: "useZerodhaPortfolio")
        if remote {
            zerodha.configure(address: apiAddress)
            defaults.set(apiAddress, forKey: "apiAddress")
            defaults.set(true, forKey: "apiAddressConfigured")
        }
        portfolio.replaceAPI(currentAPI(), clearSnapshot: true)
        await portfolio.refresh()
    }

    func connectZerodha() async {
        guard APIConfiguration.baseURL(apiAddress) != nil else {
            zerodha.errorMessage = HTTPPortfolioError.configuration.localizedDescription
            return
        }
        zerodha.configure(address: apiAddress)
        if await zerodha.connect() { await showZerodhaPortfolio() }
    }

    func showZerodhaPortfolio() async {
        zerodha.configure(address: apiAddress)
        guard zerodha.sessionToken != nil else { return }
        let wasLive = isLivePortfolio
        isLivePortfolio = true
        defaults.set(true, forKey: "useZerodhaPortfolio")
        usesRemoteAPI = true
        defaults.set(apiAddress, forKey: "apiAddress")
        defaults.set(true, forKey: "apiAddressConfigured")
        portfolio.replaceAPI(currentAPI(), clearSnapshot: !wasLive)
        await portfolio.refresh()
    }

    func disconnectZerodha() async {
        if await zerodha.disconnect() { await selectSource(remote: true) }
    }

    private func currentAPI() -> any PortfolioAPI {
        guard usesRemoteAPI else { return MockPortfolioAPI(scenario: scenario) }
        guard let url = APIConfiguration.baseURL(apiAddress) else { return UnconfiguredPortfolioAPI() }
        return HTTPPortfolioAPI(baseURL: url, scenario: scenario, sessionToken: isLivePortfolio ? zerodha.sessionToken : nil)
    }
}

private struct UnconfiguredPortfolioAPI: PortfolioAPI {
    func fetchSnapshot() async throws -> PortfolioSnapshot { throw HTTPPortfolioError.configuration }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

@MainActor @Observable
final class AppPreferences {
    var hideBalances: Bool { didSet { defaults.set(hideBalances, forKey: "hideBalances") } }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    @ObservationIgnored private let defaults: UserDefaults

    init() {
        let isUITest = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        defaults = isUITest ? UserDefaults(suiteName: "com.ritz078.sumora.ui-tests")! : .standard
        if isUITest { defaults.removePersistentDomain(forName: "com.ritz078.sumora.ui-tests") }
        hideBalances = defaults.bool(forKey: "hideBalances")
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "system") ?? .system
    }
}
