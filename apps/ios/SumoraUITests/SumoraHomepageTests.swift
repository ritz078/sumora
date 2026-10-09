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

    func testHomepageKeepsHoldingsInDedicatedTab() {
        let app = launch()
        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "Homepage gradient and glass menu"
        top.lifetime = .keepAlways
        add(top)
        app.swipeUp()
        app.swipeUp()
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
        app.buttons["tab-Holdings"].tap()
        XCTAssertTrue(app.buttons["holding-hdfc"].waitForExistence(timeout: 5))
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
