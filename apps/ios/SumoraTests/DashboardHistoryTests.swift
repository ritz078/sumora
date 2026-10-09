import Foundation
import Testing
@testable import Sumora

struct DashboardHistoryTests {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func futureValuationsAreExcludedFromEveryPeriod() {
        let now = date("2026-10-06T06:00:00Z")
        let history = [HistoryPoint(date: now, value: DecimalValue(100)), HistoryPoint(date: now.addingTimeInterval(86400), value: DecimalValue(200))]
        for period in HistoryPeriod.allCases {
            #expect(period.points(in: history, relativeTo: now).map(\.value.value) == [100])
        }
    }

    @Test func yearToDateIncludesTheIndianNewYearBoundary() {
        let now = date("2026-10-06T06:00:00Z")
        let before = date("2025-12-31T18:29:59Z")
        let boundary = date("2025-12-31T18:30:00Z")
        let history = [HistoryPoint(date: before, value: DecimalValue(90)), HistoryPoint(date: boundary, value: DecimalValue(100)), HistoryPoint(date: now, value: DecimalValue(200))]
        #expect(HistoryPeriod.yearToDate.points(in: history, relativeTo: now).map(\.value.value) == [100, 200])
    }

    @Test func yearPeriodsKeepTheLeapYearCalendarBoundary() {
        let now = date("2024-03-01T06:00:00Z")
        let history = [HistoryPoint(date: date("2023-03-01T06:00:00Z"), value: DecimalValue(100)), HistoryPoint(date: now, value: DecimalValue(200))]
        #expect(HistoryPeriod.year.points(in: history, relativeTo: now).count == 2)
    }
}
