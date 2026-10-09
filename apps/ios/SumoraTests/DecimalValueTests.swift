import Foundation
import Testing
@testable import Sumora

struct DecimalValueTests {
    @Test func preservesFractionalPrecisionAcrossJSONRoundTrip() throws {
        let json = Data("\"123456789012345.123456789\"".utf8)
        let decoded = try JSONDecoder().decode(DecimalValue.self, from: json)
        #expect(decoded.value == Decimal(string: "123456789012345.123456789"))
        let encoded = try JSONEncoder().encode(decoded)
        #expect(try JSONDecoder().decode(String.self, from: encoded) == "123456789012345.123456789")
    }

    @Test(arguments: ["not-a-price", "1.2abc", "", "NaN"])
    func rejectsMalformedFinancialAmounts(_ input: String) throws {
        let json = try JSONEncoder().encode(input)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DecimalValue.self, from: json)
        }
    }
}
