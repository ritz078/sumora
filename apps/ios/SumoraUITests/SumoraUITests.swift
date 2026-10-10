import XCTest

@MainActor
final class SumoraUITests: XCTestCase {
    private func launch(scenario: String = "complete") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--scenario=\(scenario)"]
        app.launch()
        return app
    }

    func testOverviewStockRowsStayInHoldings() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["portfolioValue"].waitForExistence(timeout: 10))
        app.buttons["tab-Holdings"].tap()
        let reliance = app.descendants(matching: .any)["holding-reliance"].firstMatch
        XCTAssertTrue(reliance.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Stitch Holdings tab"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        reliance.tap()
        XCTAssertFalse(app.staticTexts["holdingName"].exists)
        XCTAssertTrue(app.textFields["holdingsSearch"].exists)
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
        XCTAssertTrue(app.descendants(matching: .any)["holding-hdfc"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["holding-reliance"].firstMatch.exists)
        app.buttons["US stocks"].tap()
        XCTAssertTrue(app.staticTexts["No matching holdings"].waitForExistence(timeout: 5))
    }

    func testRefreshFailurePreservesVisiblePortfolio() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["portfolioValue"].waitForExistence(timeout: 10))
        let value = app.staticTexts["portfolioValue"].label
        app.buttons["homeSettings"].tap()
        let failure = app.buttons["scenario-failure"]
        for _ in 0..<10 where !failure.isHittable { app.swipeUp() }
        XCTAssertTrue(failure.isHittable)
        failure.tap()
        let toast = app.staticTexts["refreshError"]
        XCTAssertTrue(toast.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["dismissRefreshError"].exists)
        app.buttons["dismissRefreshError"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertEqual(app.staticTexts["portfolioValue"].label, value)
        XCTAssertFalse(toast.exists)
        app.buttons["tab-Holdings"].tap()
        let reliance = app.descendants(matching: .any)["holding-reliance"].firstMatch
        XCTAssertTrue(reliance.waitForExistence(timeout: 5))
        reliance.tap()
        XCTAssertFalse(app.staticTexts["holdingName"].exists)
        XCTAssertTrue(app.textFields["holdingsSearch"].exists)
    }

    func testEmptyPortfolioOffersSampleRecovery() {
        let app = launch(scenario: "empty")
        let recovery = app.buttons["Explore sample portfolio"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 10))
        recovery.tap()
        XCTAssertTrue(app.staticTexts["portfolioValue"].waitForExistence(timeout: 10))
    }
}
