import Foundation
import Testing
@testable import Sumora

struct SessionKeychainTests {
    @Test func sessionPersistsOnlyForItsAPIAddressAndCanBeRemoved() throws {
        let address = "https://keychain-test-\(UUID().uuidString).example.com"
        defer { SessionKeychain.remove(address) }
        try SessionKeychain.write("session-token", address: address)
        #expect(SessionKeychain.read(address) == "session-token")
        #expect(SessionKeychain.read(address + "/other") == nil)
        SessionKeychain.remove(address)
        #expect(SessionKeychain.read(address) == nil)
    }
}
