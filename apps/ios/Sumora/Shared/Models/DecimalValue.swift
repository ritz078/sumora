import Foundation

struct DecimalValue: Codable, Hashable, Sendable {
    let value: Decimal

    init(_ value: Decimal) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard string.range(of: "^-?[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
              let amount = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")),
              !amount.isNaN else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a decimal string")
        }
        value = amount
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NSDecimalNumber(decimal: value).stringValue)
    }
}
