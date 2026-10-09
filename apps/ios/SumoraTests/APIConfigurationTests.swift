import Foundation
import Testing
@testable import Sumora

struct APIConfigurationTests {
    @Test func oldTestLocalhostSettingMigratesToDeployedAPI() throws {
        try withDefaults { defaults in
            defaults.set("http://localhost:8787", forKey: "apiAddress")
            #expect(APIConfiguration.savedAddress(in: defaults) == APIConfiguration.defaultAddress)
            #expect(defaults.string(forKey: "apiAddress") == nil)
        }
    }

    @Test func explicitlyConfiguredLocalServerIsPreserved() throws {
        try withDefaults { defaults in
            defaults.set("http://localhost:8787", forKey: "apiAddress")
            defaults.set(true, forKey: "apiAddressConfigured")
            #expect(APIConfiguration.savedAddress(in: defaults) == "http://localhost:8787")
        }
    }

    @Test func customHTTPSAddressIsPreserved() throws {
        try withDefaults { defaults in
            defaults.set("https://custom.example.com", forKey: "apiAddress")
            #expect(APIConfiguration.savedAddress(in: defaults) == "https://custom.example.com")
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) throws {
        let name = "sumora.configuration-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }
}
