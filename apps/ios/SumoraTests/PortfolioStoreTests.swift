import Foundation
import Testing
@testable import Sumora

@MainActor
struct PortfolioStoreTests {
    @Test func refreshFailureRetainsTheLastSnapshot() async throws {
        let snapshot = try MockPortfolioAPI.load(.complete)
        let api = ScriptedAPI(snapshot: snapshot, failAfterFirst: true)
        let store = PortfolioStore(api: api)
        await store.refresh()
        await store.refresh()
        #expect(store.snapshot?.id == "demo-complete")
        #expect(store.snapshot?.value?.value == 4250000)
        #expect(store.errorMessage != nil)
        #expect(!store.isRefreshing)
    }

    @Test func simultaneousRefreshesShareOneRequest() async throws {
        let api = ScriptedAPI(snapshot: try MockPortfolioAPI.load(.complete))
        let store = PortfolioStore(api: api)
        let first = Task { await store.refresh() }
        await api.waitForRequest()
        let second = Task { await store.refresh() }
        await first.value
        await second.value
        #expect(await api.requestCount == 1)
        #expect(store.snapshot?.id == "demo-complete")
    }

    @Test func cancelledPreviousSourceCannotRepopulateClearedState() async throws {
        let oldAPI = ScriptedAPI(snapshot: try MockPortfolioAPI.load(.complete))
        let store = PortfolioStore(api: oldAPI)
        let oldRefresh = Task { await store.refresh() }
        await oldAPI.waitForRequest()
        store.replaceAPI(MockPortfolioAPI(scenario: .empty, delay: .zero), clearSnapshot: true)
        await store.refresh()
        await oldRefresh.value
        #expect(store.snapshot?.id == "demo-empty")
        #expect(store.snapshot?.holdings.isEmpty == true)
        #expect(!store.isRefreshing)
    }
}

private actor ScriptedAPI: PortfolioAPI {
    let snapshot: PortfolioSnapshot
    let failAfterFirst: Bool
    private(set) var requestCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(snapshot: PortfolioSnapshot, failAfterFirst: Bool = false) {
        self.snapshot = snapshot
        self.failAfterFirst = failAfterFirst
    }

    func fetchSnapshot() async throws -> PortfolioSnapshot {
        requestCount += 1
        let count = requestCount
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        // Models a provider that still completes a response after cancellation.
        try? await Task.sleep(for: .milliseconds(80))
        if failAfterFirst && count > 1 { throw PortfolioAPIError.demoFailure }
        return snapshot
    }

    func waitForRequest() async {
        if requestCount > 0 { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
