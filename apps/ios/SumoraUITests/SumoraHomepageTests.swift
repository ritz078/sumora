import XCTest

@MainActor
final class SumoraHomepageTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["portfolioValue"].waitForExistence(timeout: 10))
        return app
    }

    func testTrajectoryLabelsMatchReferencePlacement() {
        let app = launch()
        app.swipeUp()
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Trajectory label placement"
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Trajectory accessibility geometry"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        before.lifetime = .keepAlways
        add(before)
        let today = app.staticTexts["Today"]
        XCTAssertTrue(today.exists, "The final date belongs in a dedicated footer as Today, matching Stitch")
        guard today.exists else { return }
        for index in 0..<3 {
            let price = app.staticTexts["home-y-label-\(index)"]
            XCTAssertTrue(price.exists)
            guard price.exists else { return }
            XCTAssertEqual(price.frame.maxX, today.frame.maxX, accuracy: 1, "Prices must align inside the plot with the final date")
        }
        XCTAssertGreaterThan(today.frame.minY, app.staticTexts["home-y-label-2"].frame.maxY + 20, "Dates belong below the plot, separated from its price labels")
        let first = app.staticTexts["home-x-label-0"]
        XCTAssertTrue(first.exists)
        XCTAssertEqual(first.frame.midY, today.frame.midY, accuracy: 1, "First and last dates share a separate footer row")
        XCTAssertLessThan(first.frame.minX, today.frame.minX)
        let latest = app.descendants(matching: .any)["home-latest-value"].firstMatch
        XCTAssertTrue(latest.exists)
        XCTAssertLessThan(latest.frame.maxY, app.staticTexts["home-y-label-0"].frame.minY)
    }

    func testSettingsRemainReachableWhenPortfolioCannotLoad() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--scenario=failure"]
        app.launch()
        XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 10))
        app.buttons["homeSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    func testPartialValuationDisclosesExcludedHoldings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--scenario=partial"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Partial valuation · Unpriced holdings are excluded."].waitForExistence(timeout: 10))
    }

    func testHomepageKeepsHoldingsInDedicatedTab() {
        let app = launch()
        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "Homepage gradient and glass menu"
        top.lifetime = .keepAlways
        add(top)
        for _ in 0..<5 { app.swipeUp() }
        let footer = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Sample portfolio ·")).firstMatch
        XCTAssertTrue(footer.exists)
        XCTAssertLessThan(footer.frame.maxY, app.buttons["tab-Overview"].frame.minY, "The footer must scroll fully above the floating menu")
        let bottom = XCTAttachment(screenshot: app.screenshot())
        bottom.name = "Homepage footer clears navigation"
        bottom.lifetime = .keepAlways
        add(bottom)
        XCTAssertFalse(app.textFields["overviewSearch"].exists)
        XCTAssertFalse(app.buttons["Filter holdings by category"].exists)
        XCTAssertFalse(app.buttons["overview-holding-hdfc"].exists)
        XCTAssertFalse(app.staticTexts["Imported custodian balances"].exists)
        XCTAssertFalse(app.buttons["tab-Settings"].exists)
        app.buttons["tab-Holdings"].tap()
        XCTAssertTrue(app.buttons["holding-hdfc"].waitForExistence(timeout: 5))
    }

    func testAllocationAndProfileNavigation() {
        let app = launch()
        let amounts = app.buttons["Allocation amounts"]
        for _ in 0..<4 where !amounts.isHittable { app.swipeUp() }
        amounts.tap()
        XCTAssertTrue(amounts.isSelected)
        let category = app.buttons["allocation-usEquity"]
        for _ in 0..<3 where !category.isHittable { app.swipeUp() }
        category.tap()
        XCTAssertTrue(app.buttons["US stocks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["US stocks"].isSelected)
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<6 where !app.buttons["homeSettings"].isHittable { app.swipeDown() }
        app.buttons["homeSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    func testHistoryPeriodAndBalancePrivacy() {
        let app = launch()
        let month = app.buttons["1M history"]
        if !month.isHittable { app.swipeUp() }
        month.tap()
        XCTAssertTrue(month.isSelected)
        app.buttons["tab-Holdings"].tap()
        app.buttons["balanceVisibility"].tap()
        app.buttons["tab-Overview"].tap()
        for _ in 0..<5 where !app.staticTexts["portfolioValue"].isHittable { app.swipeDown() }
        XCTAssertEqual(app.staticTexts["portfolioValue"].label, "Hidden amount")
        XCTAssertFalse(app.descendants(matching: .any)["portfolioHistory"].exists)
    }

}
