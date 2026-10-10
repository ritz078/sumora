import Foundation

enum AssetClass: String, Codable, CaseIterable, Identifiable, Sendable {
    case indianEquity, usEquity, mutualFund, gold, bond, fixedDeposit, nps
    var id: Self { self }
    var title: String {
        switch self {
        case .indianEquity: "Indian stocks"
        case .usEquity: "US stocks"
        case .mutualFund: "Mutual funds"
        case .gold: "Gold"
        case .bond: "Bonds"
        case .fixedDeposit: "Fixed deposits"
        case .nps: "NPS"
        }
    }
    var symbol: String {
        switch self {
        case .indianEquity, .usEquity: "chart.line.uptrend.xyaxis"
        case .mutualFund: "square.stack.3d.up.fill"
        case .gold: "sparkles"
        case .bond, .fixedDeposit, .nps: "building.columns.fill"
        }
    }
}

enum Coverage: String, Codable, Sendable { case complete, partial, unavailable }

struct HistoryPoint: Codable, Identifiable, Sendable {
    let date: Date
    let value: DecimalValue
    var id: Date { date }
}

struct DepositTerms: Codable, Sendable {
 let originalPrincipal: DecimalValue
 let currentAmount: DecimalValue
 let maturityAmount: DecimalValue
 let rate: DecimalValue
 let openedOn: String
 let maturesOn: String
 let lien: DecimalValue
}

struct BondTerms: Codable, Sendable {
 let coupon: DecimalValue?
 let maturesOn: String?
 let redemptionCheck: Bool
 let investedAmount: DecimalValue?
 let accruedAtPurchase: DecimalValue?
 let interestGross: DecimalValue?
 let interestNet: DecimalValue?
 let tds: DecimalValue?
 let principalReceived: DecimalValue?
 let nextPayout: String?
 let frequency: String?
 let repayment: String?
 let ytm: DecimalValue?
 let projectedMaturityValue: DecimalValue?
 let projectionUsesOrderDate: Bool?
 let quotedCoupon: DecimalValue?
 let valuationBasis: String?
 let reconciliationNote: String?
 let payoutDifference: DecimalValue?
}

struct Holding: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let symbol: String
    let assetClass: AssetClass
    let accountID: String
    let quantity: DecimalValue
    let unit: String
    let invested: DecimalValue
    var costBasisKnown: Bool? = nil
    var depositTerms: DepositTerms? = nil
    var bondTerms: BondTerms? = nil
    let value: DecimalValue?
    let gain: DecimalValue?
    let gainPercent: DecimalValue?
    var dailyGain: DecimalValue? = nil
    var dailyGainPercent: DecimalValue? = nil
    let quote: DecimalValue?
    let quoteCurrency: String
    let fxRate: DecimalValue?
    let fxAt: Date?
    let quoteAt: Date?
    let source: String
    let priceBasis: String
    let history: [HistoryPoint]
}

struct Allocation: Codable, Identifiable, Sendable {
    let assetClass: AssetClass
    let value: DecimalValue
    let percent: DecimalValue
    var id: AssetClass { assetClass }
}

enum ConnectionStatus: String, Codable, Sendable { case connected, attention, disconnected }

struct Connection: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let symbol: String
    let status: ConnectionStatus
    let lastSyncAt: Date?
    let description: String
}

struct PortfolioSnapshot: Codable, Sendable {
    let id: String
    let reportingCurrency: String
    let capturedAt: Date
    let holdingsSyncAt: Date
    let coverage: Coverage
    let value: DecimalValue?
    let invested: DecimalValue
    let coveredInvested: DecimalValue
    let gain: DecimalValue?
    let gainPercent: DecimalValue?
    var dailyGain: DecimalValue? = nil
    var dailyGainPercent: DecimalValue? = nil
    let holdings: [Holding]
    let allocation: [Allocation]
    let history: [HistoryPoint]
    let connections: [Connection]
    var dailyBaselineDate: String? = nil

    func holding(id: String) -> Holding? { holdings.first { $0.id == id } }
}

enum HistoryPeriod: String, CaseIterable, Identifiable {
    case month = "1M", quarter = "3M", halfYear = "6M", yearToDate = "YTD", year = "1Y", threeYears = "3Y", all = "All"
    var id: Self { self }
    func points(in history: [HistoryPoint], relativeTo date: Date) -> [HistoryPoint] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let start: Date?
        switch self {
        case .month: start = date.addingTimeInterval(-30 * 86400)
        case .quarter: start = date.addingTimeInterval(-90 * 86400)
        case .halfYear: start = date.addingTimeInterval(-180 * 86400)
        case .yearToDate: start = calendar.dateInterval(of: .year, for: date)?.start
        case .year: start = calendar.date(byAdding: .year, value: -1, to: date)
        case .threeYears: start = calendar.date(byAdding: .year, value: -3, to: date)
        case .all: start = nil
        }
        return history.filter { $0.date <= date && (start == nil || $0.date >= start!) }
    }
}
