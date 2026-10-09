import XCTest

/// Requires `npm run dev` in apps/api. Ordinary offline tests do not need a server.
@MainActor
final class SumoraAPIIntegrationTests: XCTestCase {
    func testConnectToSampleAPIAndKeepSnapshotOnHTTPFailure() async throws {
        let healthURL = URL(string: "http://localhost:8787/health")!
        do {
            let (_, response) = try await URLSession.shared.data(from: healthURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw XCTSkip("Start apps/api with npm run dev for the API integration test.")
            }
        } catch is URLError {
            throw XCTSkip("Start apps/api with npm run dev for the API integration test.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["portfolioValue"].waitForExistence(timeout: 10))
        app.buttons["tab-Settings"].tap()
        let connect = app.buttons["connect-api"]
        for _ in 0..<4 where !connect.isHittable { app.swipeUp() }
        XCTAssertTrue(connect.isHittable)
        connect.tap()
        let source = app.descendants(matching: .any)["portfolio-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        XCTAssertEqual(source.value as? String, "Sample API")
        app.buttons["tab-Overview"].tap()
        XCTAssertTrue(app.staticTexts["portfolioValue"].waitForExistence(timeout: 10))
        let value = app.staticTexts["portfolioValue"].label
        XCTAssertFalse(app.staticTexts["refreshError"].exists)
        app.buttons["tab-Settings"].tap()
        let failure = app.buttons["scenario-failure"]
        for _ in 0..<5 where !failure.isHittable { app.swipeUp() }
        XCTAssertTrue(failure.isHittable)
        failure.tap()
        app.buttons["tab-Overview"].tap()
        XCTAssertTrue(app.staticTexts["refreshError"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["refreshError"].label.contains("503"))
        XCTAssertEqual(app.staticTexts["portfolioValue"].label, value)
    }
}
