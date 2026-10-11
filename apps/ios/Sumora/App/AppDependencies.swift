import Foundation
import Observation

@MainActor @Observable
final class AppDependencies {
    let portfolio: PortfolioStore
    let preferences: AppPreferences
    let auth: AppAuth
    let bypassLogin: Bool
    let zerodha: ZerodhaConnection
    let gmail: GmailConnection
    let gold = GoldConnection()
    let hdfc = HDFCConnection()
    let nps = NPSConnection()
    let bonds = BondsConnection()
    let properties = PropertiesConnection()
    let indmoney: INDmoneyConnection
    private(set) var isLivePortfolio = false
    private(set) var scenario: DemoScenario = .complete
    private(set) var usesRemoteAPI = true
    var apiAddress: String
    var configurationError: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let apiSession: URLSession
    // A fixed clock makes the sample history and freshness labels reproducible.
    var demoDate: Date { isLivePortfolio ? Date() : ISO8601DateFormatter().date(from: "2026-10-06T06:00:00Z")! }

    init(address requestedAddress: String? = nil, session: URLSession = .shared, defaults requestedDefaults: UserDefaults? = nil) {
        apiSession = session
        gmail = GmailConnection(session: session)
        indmoney = INDmoneyConnection(session: session)
        preferences = AppPreferences()
        let arguments = ProcessInfo.processInfo.arguments
        let isUITest = arguments.contains("--ui-testing")
        defaults = requestedDefaults ?? (isUITest ? UserDefaults(suiteName: "com.ritz078.sumora.ui-tests")! : .standard)
        let address = requestedAddress ?? (isUITest ? "http://localhost:8787" :
            APIConfiguration.savedAddress(in: defaults))
        apiAddress = address
        bypassLogin = (isUITest && !arguments.contains("--auth-testing")) || arguments.contains("--offline-demo")
        auth = AppAuth(address: address, restoreSession: !isUITest, session: session)
        let connection = ZerodhaConnection(address: address)
        zerodha = connection
        let initial = arguments.first(where: { $0.hasPrefix("--scenario=") })
            .flatMap { DemoScenario(rawValue: String($0.dropFirst("--scenario=".count))) } ?? .complete
        scenario = initial
        let remote = !arguments.contains("--ui-testing") && !arguments.contains("--offline-demo")
        usesRemoteAPI = remote
        let live = remote && auth.sessionToken != nil
        isLivePortfolio = live
        if remote, let url = APIConfiguration.baseURL(address) {
            portfolio = PortfolioStore(api: HTTPPortfolioAPI(baseURL: url, scenario: initial, session: session, sessionToken: live ? auth.sessionToken : nil))
        } else if remote {
            portfolio = PortfolioStore(api: UnconfiguredPortfolioAPI())
        } else {
            portfolio = PortfolioStore(api: MockPortfolioAPI(scenario: initial))
        }
    }

    var setupProgress: String?
    var setupError: String?
    private(set) var isFetchingHoldings = false

    func activateSession() async {
        guard auth.account != nil else { return }
        configureConnections(token: auth.sessionToken)
        await zerodha.refresh()
        await showZerodhaPortfolio()
    }

    func configureConnections(token: String?) {
        zerodha.configure(address: apiAddress, token: token)
        gmail.configure(address: apiAddress, token: token)
        gold.configure(address: apiAddress, token: token)
        hdfc.configure(address: apiAddress, token: token)
        nps.configure(address: apiAddress, token: token)
        bonds.configure(address: apiAddress, token: token)
        properties.configure(address: apiAddress, token: token)
        indmoney.configure(address: apiAddress, token: token)
    }

    func clearPrivateState() {
        configureConnections(token: nil)
        isLivePortfolio = false
        portfolio.replaceAPI(UnconfiguredPortfolioAPI(), clearSnapshot: true)
        setupProgress = nil; setupError = nil; isFetchingHoldings = false
    }

    func logout() async {
        if await auth.logout() { clearPrivateState() }
    }

    func fetchConsolidatedHoldings() async {
        guard !isFetchingHoldings, let token = auth.sessionToken else { return }
        isFetchingHoldings = true; setupError = nil
        defer { if auth.sessionToken == token { isFetchingHoldings = false; setupProgress = nil } }
        configureConnections(token: token)
        setupProgress = "Checking connected accounts…"
        await gmail.refresh(); await indmoney.refresh()
        guard auth.sessionToken == token else { return }
        if let error = gmail.errorMessage ?? indmoney.errorMessage { setupError = error; return }
        if gmail.status?.connected == true {
            setupProgress = "Importing Gmail documents…"
            await syncGmailDocuments()
            guard auth.sessionToken == token else { return }
            if let error = gmail.errorMessage { setupError = error; return }
            if gmail.syncResults.contains(where: { $0.status == "failed" || $0.pending || $0.error != nil }) {
                setupError = "Some documents need attention. Review the Gmail sync results and try again."; return
            }
        }
        if indmoney.status?.connected == true {
            setupProgress = "Fetching US holdings…"; await indmoney.sync()
            guard auth.sessionToken == token else { return }
            if let error = indmoney.errorMessage { setupError = error; return }
        }
        setupProgress = "Consolidating your holdings…"
        await showZerodhaPortfolio()
        guard auth.sessionToken == token else { return }
        if let error = portfolio.errorMessage { setupError = error; return }
        _ = await auth.completeOnboarding()
    }

    func syncGmailDocuments() async {
        gmail.configure(address: zerodha.address, token: auth.sessionToken)
        guard !gmail.isBusy else { return }
        await gmail.syncDocuments()
        gold.configure(address: zerodha.address, token: auth.sessionToken)
        hdfc.configure(address: zerodha.address, token: auth.sessionToken)
        nps.configure(address: zerodha.address, token: auth.sessionToken)
        bonds.configure(address: zerodha.address, token: auth.sessionToken)
        await gold.refresh()
        await hdfc.refresh()
        await nps.refresh()
        await bonds.refresh()
        if isLivePortfolio { await portfolio.refresh() }
    }

    func toggleDemoPortfolio() async {
        if isLivePortfolio {
            usesRemoteAPI = false
            await selectScenario(.complete)
        } else {
            await showZerodhaPortfolio()
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
            zerodha.configure(address: apiAddress, token: auth.sessionToken)
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
        zerodha.configure(address: apiAddress, token: auth.sessionToken)
        if await zerodha.connect() { await showZerodhaPortfolio() }
    }

    func showZerodhaPortfolio() async {
        zerodha.configure(address: apiAddress, token: auth.sessionToken)
        guard auth.sessionToken != nil else { return }
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
        if await zerodha.disconnect() { await portfolio.refresh() }
    }

    private func currentAPI() -> any PortfolioAPI {
        guard usesRemoteAPI else { return MockPortfolioAPI(scenario: scenario) }
        guard let url = APIConfiguration.baseURL(apiAddress) else { return UnconfiguredPortfolioAPI() }
        return HTTPPortfolioAPI(baseURL: url, scenario: scenario, session: apiSession, sessionToken: isLivePortfolio ? auth.sessionToken : nil)
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
