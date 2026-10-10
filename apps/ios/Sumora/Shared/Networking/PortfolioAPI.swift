import Foundation

protocol PortfolioAPI: Sendable {
    func fetchSnapshot() async throws -> PortfolioSnapshot
}

enum DemoScenario: String, CaseIterable, Identifiable, Sendable {
    case complete, partial, stale, empty, unavailable, failure
    var id: Self { self }
    var title: String {
        switch self {
        case .complete: "Complete portfolio"
        case .partial: "One missing price"
        case .stale: "Outdated prices"
        case .empty: "Empty portfolio"
        case .unavailable: "All prices unavailable"
        case .failure: "Refresh failure"
        }
    }
    var explanation: String {
        switch self {
        case .complete: "Eight holdings across five asset classes."
        case .partial: "Apple has no price. Totals include only valued holdings."
        case .stale: "Prices and account data are three days old."
        case .empty: "An account with no holdings yet."
        case .unavailable: "Holdings are available, but none can be valued."
        case .failure: "Refresh fails while your previous snapshot stays visible."
        }
    }
}

enum PortfolioAPIError: LocalizedError {
    case demoFailure, missingFixture, invalidSnapshot
    var errorDescription: String? {
        switch self {
        case .demoFailure: "Couldn't refresh your portfolio."
        case .missingFixture: "The portfolio sample couldn't be loaded."
        case .invalidSnapshot: "The portfolio response couldn't be read."
        }
    }
}

struct MockPortfolioAPI: PortfolioAPI {
    let scenario: DemoScenario
    var delay: Duration = .milliseconds(450)

    func fetchSnapshot() async throws -> PortfolioSnapshot {
        try await Task.sleep(for: delay)
        if scenario == .failure { throw PortfolioAPIError.demoFailure }
        return try Self.load(scenario)
    }

    static func load(_ scenario: DemoScenario) throws -> PortfolioSnapshot {
        let arguments = ProcessInfo.processInfo.arguments
        let resource = arguments.contains("--ui-testing") && arguments.contains("--gold-fixture") ? "gold" : arguments.contains("--ui-testing") && arguments.contains("--real-estate-fixture") ? "real-estate" : scenario.rawValue
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            throw PortfolioAPIError.missingFixture
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PortfolioSnapshot.self, from: Data(contentsOf: url))
    }
}
