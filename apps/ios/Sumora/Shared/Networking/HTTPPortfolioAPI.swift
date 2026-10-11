import Foundation

struct HTTPPortfolioAPI: PortfolioAPI {
    let baseURL: URL
    var scenario: DemoScenario = .complete
    var session: URLSession = .shared
    var sessionToken: String? = nil

    func fetchSnapshot() async throws -> PortfolioSnapshot {
        var components = URLComponents(url: baseURL.appendingPathComponent(sessionToken == nil ? "v1/demo/portfolio" : "v1/zerodha/portfolio"), resolvingAgainstBaseURL: false)
        if sessionToken == nil { components?.queryItems = [URLQueryItem(name: "scenario", value: scenario.rawValue)] }
        guard let url = components?.url else { throw PortfolioAPIError.invalidSnapshot }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let sessionToken { request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PortfolioAPIError.invalidSnapshot }
        checkAppSession(http, data: data, token: sessionToken)
  guard (200..<300).contains(http.statusCode) else {
            if let error = try? JSONDecoder().decode(APIErrorResponse.self, from: data) { throw ZerodhaError.message(error.error.message + " (HTTP \(http.statusCode))") }
            throw HTTPPortfolioError.status(http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(PortfolioSnapshot.self, from: data) }
        catch { throw PortfolioAPIError.invalidSnapshot }
    }
}

enum HTTPPortfolioError: LocalizedError {
    case status(Int), configuration
    var errorDescription: String? {
        switch self {
        case .status(let code): "Couldn't refresh your portfolio (HTTP \(code))."
        case .configuration: "Configure a valid HTTPS API address in Settings."
        }
    }
}

enum APIConfiguration {
    static func savedAddress(in defaults: UserDefaults) -> String {
        let saved = defaults.string(forKey: "apiAddress")
        // Early integration builds accidentally saved the test server in the normal app domain.
        if saved == "http://localhost:8787", !defaults.bool(forKey: "apiAddressConfigured") {
            defaults.removeObject(forKey: "apiAddress")
            return defaultAddress
        }
        return saved ?? defaultAddress
    }

    static var defaultAddress: String {
        "https://sumora-api.rkritesh078.workers.dev"
    }

    static func baseURL(_ address: String) -> URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else { return nil }
        if components.scheme == "https" { return url }
        #if DEBUG
        if components.scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(host) { return url }
        #endif
        return nil
    }
}
