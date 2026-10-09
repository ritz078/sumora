import Foundation
import Testing
@testable import Sumora

struct ZerodhaCallbackTests {
    @Test func acceptsOnlyExpectedStateAndScheme() throws {
        let code = String(repeating: "a", count: 64)
        let url = URL(string: "sumora://zerodha?state=expected&code=\(code)")!
        #expect(try ZerodhaCallback.code(from: url, expectedState: "expected") == code)
        #expect(throws: (any Error).self) { try ZerodhaCallback.code(from: url, expectedState: "other") }
        #expect(throws: (any Error).self) {
            try ZerodhaCallback.code(from: URL(string: "https://zerodha?state=expected&code=\(code)")!, expectedState: "expected")
        }
    }
    @Test func failedOrIncompleteLoginNeverReturnsACode() {
        for value in ["sumora://zerodha?state=expected&error=ACCOUNT_NOT_ALLOWED", "sumora://zerodha?state=expected", "sumora://zerodha?state=expected&code=short"] {
            #expect(throws: (any Error).self) { try ZerodhaCallback.code(from: URL(string: value)!, expectedState: "expected") }
        }
    }
}
