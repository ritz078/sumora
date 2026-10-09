import XCTest

@MainActor
final class SumoraUITests: XCTestCase {
    private func launch(scenario: String = "complete") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--scenario=\(scenario)"]
        app.launch()
        return app
    }

    func testOverviewHoldingsAndDetailNavigation() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["portfolioValue"].waitForExistence(timeout: 10))
        app.buttons["tab-Holdings"].tap()
        let reliance = app.buttons["holding-reliance"]
        XCTAssertTrue(reliance.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Stitch Holdings tab"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        reliance.tap()
        XCTAssertTrue(app.staticTexts["holdingName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["holdingName"].label, "Reliance Industries")
    }

    func testPrivacyHidesAmountsAndRemovesChartAccessibility() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["portfolioValue"].waitForExistence(timeout: 10))
        app.buttons["tab-Holdings"].tap()
        app.buttons["balanceVisibility"].tap()
        app.buttons["tab-Overview"].tap()
        XCTAssertEqual(app.staticTexts["portfolioValue"].label, "Hidden amount")
        XCTAssertTrue(app.staticTexts["History hidden"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["portfolioHistory"].exists)
        app.buttons["tab-Holdings"].tap()
        for _ in 0..<4 where !app.buttons["holding-parag"].isHittable { app.swipeUp() }
        app.buttons["holding-parag"].tap()
        XCTAssertTrue(app.staticTexts["holdingName"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["₹9,00,000"].exists)
        XCTAssertTrue(app.staticTexts["Hidden amount"].firstMatch.exists)
    }

    func testSearchAndFilterCombine() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["portfolioValue"].waitForExistence(timeout: 10))
        app.buttons["tab-Holdings"].tap()
        let search = app.textFields["holdingsSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("HDFC\n")
        XCTAssertTrue(app.buttons["holding-hdfc"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["holding-reliance"].exists)
        app.buttons["US stocks"].tap()
        XCTAssertTrue(app.staticTexts["No matching holdings"].waitForExistence(timeout: 5))
    }

    func testRefreshFailurePreservesVisiblePortfolio() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["portfolioValue"].waitForExistence(timeout: 10))
        let value = app.staticTexts["portfolioValue"].label
        app.buttons["tab-Settings"].tap()
        app.swipeUp()
        let failure = app.buttons["scenario-failure"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        failure.tap()
        let toast = app.staticTexts["refreshError"]
        XCTAssertTrue(toast.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["dismissRefreshError"].exists)
        app.buttons["dismissRefreshError"].tap()
        app.buttons["tab-Overview"].tap()
        XCTAssertEqual(app.staticTexts["portfolioValue"].label, value)
        XCTAssertFalse(toast.exists)
        app.buttons["tab-Holdings"].tap()
        let reliance = app.buttons["holding-reliance"]
        XCTAssertTrue(reliance.waitForExistence(timeout: 5))
        reliance.tap()
        XCTAssertTrue(app.staticTexts["holdingName"].waitForExistence(timeout: 5))
    }

    func testEmptyPortfolioOffersSampleRecovery() {
        let app = launch(scenario: "empty")
        let recovery = app.buttons["Explore sample portfolio"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 10))
        recovery.tap()
        XCTAssertTrue(app.staticTexts["portfolioValue"].waitForExistence(timeout: 10))
    }
}
