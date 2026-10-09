import Foundation
import Testing
@testable import Sumora

struct PortfolioContractTests {
    @Test(arguments: [DemoScenario.complete, .partial, .stale, .empty, .unavailable])
    func valuationTotalsMatchCoveredHoldings(_ scenario: DemoScenario) throws {
        let snapshot = try MockPortfolioAPI.load(scenario)
        let valued = snapshot.holdings.filter { $0.value != nil }
        let total = valued.reduce(Decimal.zero) { $0 + $1.value!.value }
        #expect(snapshot.value?.value == (scenario == .unavailable ? nil : total))
        #expect(snapshot.coveredInvested.value == valued.reduce(Decimal.zero) { $0 + $1.invested.value })
        #expect(snapshot.allocation.reduce(Decimal.zero) { $0 + $1.value.value } == total)
        if let last = snapshot.history.last { #expect(last.value.value == total) }
    }

    @Test func missingPriceIsNotAZeroValueAndDoesNotCreateAFakeLoss() throws {
        let snapshot = try MockPortfolioAPI.load(.partial)
        let apple = try #require(snapshot.holding(id: "apple"))
        #expect(apple.value == nil)
        #expect(apple.gain == nil)
        #expect(snapshot.value?.value == 3910000)
        #expect(snapshot.gain?.value == 410000)
    }

    @Test func searchAndAssetFiltersIntersectAndUnknownValuesSortLast() throws {
        let snapshot = try MockPortfolioAPI.load(.partial)
        let filtered = HoldingsQuery(search: "  a  ", assetClass: .usEquity, sort: .value).apply(to: snapshot.holdings)
        #expect(filtered.map(\.id) == ["voo", "apple"])
        #expect(HoldingsQuery(search: "HDFC", assetClass: .gold).apply(to: snapshot.holdings).isEmpty)
        #expect(HoldingsQuery(search: "zerodha", sort: .name).apply(to: snapshot.holdings).map(\.id) == ["hdfc", "reliance"])
    }

    @Test func historyPeriodsUseSnapshotTimeRatherThanTheDeviceClock() throws {
        let snapshot = try MockPortfolioAPI.load(.stale)
        let points = HistoryPeriod.month.points(in: snapshot.history, relativeTo: snapshot.capturedAt)
        #expect(points.count == 31)
        #expect(points.last?.date == snapshot.capturedAt)
    }
}
