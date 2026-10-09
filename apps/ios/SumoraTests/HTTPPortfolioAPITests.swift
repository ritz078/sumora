import Foundation
import Testing
@testable import Sumora

@Suite(.serialized)
struct HTTPPortfolioAPITests {
    @Test func decodesHTTPResponseWithoutLosingDecimalPrecision() async throws {
        let url = try #require(Bundle.main.url(forResource: "complete", withExtension: "json"))
        let data = try Data(contentsOf: url)
        TestURLProtocol.response = (200, data)
        let snapshot = try await client().fetchSnapshot()
        #expect(snapshot.value?.value == Decimal(4250000))
        #expect(snapshot.holdings.count == 8)
        #expect(TestURLProtocol.request?.url?.path == "/v1/demo/portfolio")
        #expect(TestURLProtocol.request?.url?.query == "scenario=partial")
    }

    @Test func serverErrorNeverDecodesASuccessBody() async throws {
        let url = try #require(Bundle.main.url(forResource: "complete", withExtension: "json"))
        TestURLProtocol.response = (503, try Data(contentsOf: url))
        do {
            _ = try await client().fetchSnapshot()
            Issue.record("Expected a server error")
        } catch {
            #expect(error.localizedDescription.contains("503"))
        }
    }

    @Test func personalPortfolioUsesProtectedRouteAndAuthorizationHeader() async throws {
        let url = try #require(Bundle.main.url(forResource: "complete", withExtension: "json"))
        TestURLProtocol.response = (200, try Data(contentsOf: url))
        var client = client()
        client.sessionToken = String(repeating: "a", count: 64)
        _ = try await client.fetchSnapshot()
        #expect(TestURLProtocol.request?.url?.path == "/v1/zerodha/portfolio")
        #expect(TestURLProtocol.request?.url?.query == nil)
        #expect(TestURLProtocol.request?.value(forHTTPHeaderField: "Authorization") == "Bearer " + String(repeating: "a", count: 64))
    }

    @Test func malformedResponseIsReadableError() async {
        TestURLProtocol.response = (200, Data("{}".utf8))
        do {
            _ = try await client().fetchSnapshot()
            Issue.record("Expected a decoding error")
        } catch {
            #expect(error.localizedDescription == PortfolioAPIError.invalidSnapshot.localizedDescription)
        }
    }

    @Test func transportFailureReachesTheStoreWithoutOfflineFallback() async {
        TestURLProtocol.response = (-1, Data())
        let store = await PortfolioStore(api: client())
        await store.refresh()
        #expect(await store.snapshot == nil)
        #expect(await store.errorMessage != nil)
        #expect(await store.isRefreshing == false)
    }

    @MainActor
    @Test(arguments: [401, 403, 409, 429, 500, 503, 200, -1])
    func refreshErrorsKeepLoadedHoldingsAndRecover(status: Int) async throws {
        let url = try #require(Bundle.main.url(forResource: "complete", withExtension: "json"))
        let data = try Data(contentsOf: url)
        TestURLProtocol.response = (200, data)
        let store = PortfolioStore(api: client())
        await store.refresh()
        let oldSnapshot = try #require(store.snapshot)
        TestURLProtocol.response = (status, Data("{}".utf8))
        await store.refresh()
        #expect(store.snapshot?.id == oldSnapshot.id)
        #expect(store.snapshot?.holdings.count == oldSnapshot.holdings.count)
        #expect(store.snapshot?.value == oldSnapshot.value)
        let toast = try #require(store.errorToast)
        store.dismissErrorToast(id: toast.id)
        await store.refresh()
        #expect(store.errorToast == nil)
        #expect(!store.isRefreshing)
        TestURLProtocol.response = (200, data)
        await store.refresh()
        #expect(store.errorMessage == nil)
        #expect(store.errorToast == nil)
        TestURLProtocol.response = (status, Data("{}".utf8))
        await store.refresh()
        #expect(store.errorToast != nil)
    }

    @Test func APIAddressRejectsInsecureRemoteHostsAndCredentials() {
        #expect(APIConfiguration.baseURL("https://sumora.example.com") != nil)
        #expect(APIConfiguration.baseURL("http://localhost:8787") != nil)
        #expect(APIConfiguration.baseURL("http://sumora.example.com") == nil)
        #expect(APIConfiguration.baseURL("https://user:password@example.com") == nil)
        #expect(APIConfiguration.baseURL("https://example.com?scenario=empty") == nil)
        #expect(APIConfiguration.baseURL("https://example.com/v2") == nil)
        #expect(APIConfiguration.baseURL("") == nil)
    }

    private func client() -> HTTPPortfolioAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return HTTPPortfolioAPI(baseURL: URL(string: "https://example.com")!, scenario: .partial,
                                session: URLSession(configuration: configuration))
    }
}

private final class TestURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: (Int, Data) = (200, Data())
    nonisolated(unsafe) static var request: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.request = request
        if Self.response.0 == -1 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.response.0,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.response.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
