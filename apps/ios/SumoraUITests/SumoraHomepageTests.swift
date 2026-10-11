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

    func testIndianEquitiesHasSortableDisplayOnlyStocks() {
        let app = launch()
        app.buttons["home-instrument-indianEquity"].tap()
        XCTAssertTrue(app.staticTexts["Indian Stocks"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["equityValue"].label, "₹10,80,000")
        XCTAssertFalse(app.buttons["tab-Overview"].exists)
        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "Indian stocks summary and trajectory"
        top.lifetime = .keepAlways
        add(top)
        let sort = app.buttons["Sort Indian stocks"]
        for _ in 0..<3 where !sort.isHittable { app.swipeUp() }
        sort.tap()
        app.buttons["Value: Low to High"].tap()
        let row = app.descendants(matching: .any)["equity-holding-hdfc"].firstMatch
        XCTAssertTrue(row.exists)
        XCTAssertLessThan(row.frame.minY, app.descendants(matching: .any)["equity-holding-reliance"].firstMatch.frame.minY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Indian stocks holdings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        row.tap()
        XCTAssertFalse(app.staticTexts["holdingName"].exists)
        XCTAssertTrue(app.staticTexts["Indian Stocks"].exists)
        app.buttons["equitiesBack"].tap()
        XCTAssertTrue(app.buttons["tab-Overview"].waitForExistence(timeout: 5))
    }

    func testUSStocksUsesSharedLayoutAndOnlyUSHoldings() {
        let app = launch()
        app.buttons["home-instrument-usEquity"].tap()
        XCTAssertTrue(app.staticTexts["US Stocks"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["equityValue"].label, "₹11,90,000")
        app.buttons["stockCurrencyToggle"].tap()
        XCTAssertEqual(app.staticTexts["equityValue"].label, "$14,000")
        app.buttons["stockCurrencyToggle"].tap()
        XCTAssertEqual(app.staticTexts["equityValue"].label, "₹11,90,000")
        XCTAssertFalse(app.buttons["tab-Overview"].exists)
        let sort = app.buttons["Sort US stocks"]
        for _ in 0..<3 where !sort.isHittable { app.swipeUp() }
        sort.tap()
        app.buttons["Value: Low to High"].tap()
        app.swipeUp()
        let apple = app.descendants(matching: .any)["equity-holding-apple"].firstMatch
        let voo = app.descendants(matching: .any)["equity-holding-voo"].firstMatch
        XCTAssertTrue(apple.exists && voo.exists)
        XCTAssertFalse(app.descendants(matching: .any)["equity-holding-hdfc"].firstMatch.exists)
        XCTAssertLessThan(apple.frame.minY, voo.frame.minY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "US stocks shared layout and holdings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        apple.tap()
        XCTAssertFalse(app.staticTexts["holdingName"].exists)
        app.buttons["equitiesBack"].tap()
        XCTAssertTrue(app.buttons["tab-Overview"].waitForExistence(timeout: 5))
    }

    func testMutualFundsUsesInstrumentLayoutAndUnits() {
        let app = launch()
        app.buttons["home-instrument-mutualFund"].tap()
        XCTAssertTrue(app.staticTexts["Mutual Funds"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["equityValue"].label, "₹14,80,000")
        XCTAssertFalse(app.buttons["stockCurrencyToggle"].exists)
        let top = XCTAttachment(screenshot: app.screenshot()); top.name = "Mutual Funds summary"; top.lifetime = .keepAlways; add(top)
        let sort = app.buttons["Sort mutual funds"]
        for _ in 0..<3 where !sort.isHittable { app.swipeUp() }
        sort.tap(); app.buttons["Value: Low to High"].tap()
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["equity-holding-parag"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["equity-holding-hdfc"].firstMatch.exists)
        let rows = XCTAttachment(screenshot: app.screenshot()); rows.name = "Mutual Funds holdings"; rows.lifetime = .keepAlways; add(rows)
    }

    func testGoldBullionShowsRecordedValuesAndDedicatedLayout() {
        let app = launch()
        let category = app.buttons["allocation-gold"]
        for _ in 0..<5 where !category.isHittable { app.swipeUp() }
        category.tap()
        XCTAssertTrue(app.staticTexts["goldValue"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["goldValue"].label, "₹3,50,000")
        XCTAssertTrue(app.buttons["goldRefresh"].exists)
        XCTAssertTrue(app.staticTexts["Gold & Bullion Trajectory"].exists)
        let top = XCTAttachment(screenshot: app.screenshot()); top.name = "Gold and Bullion summary"; top.lifetime = .keepAlways; add(top)
        let sort = app.buttons["Sort gold holdings"]
        for _ in 0..<3 where !sort.isHittable { app.swipeUp() }
        sort.tap(); app.buttons["Value: Low to High"].tap()
        let row = app.descendants(matching: .any)["gold-holding-gold"].firstMatch
        XCTAssertTrue(row.exists)
        XCTAssertTrue(row.label.contains("35 grams"))
        XCTAssertTrue(row.label.contains("BULLION"))
        XCTAssertFalse(app.descendants(matching: .any)["gold-holding-hdfc"].firstMatch.exists)
        let rows = XCTAttachment(screenshot: app.screenshot()); rows.name = "Gold and Bullion holdings"; rows.lifetime = .keepAlways; add(rows)
        app.buttons["goldBack"].tap()
        XCTAssertTrue(app.buttons["tab-Overview"].waitForExistence(timeout: 5))
    }

    func testGoldMixedHoldingsPreserveUnknownCostsAndDailyBaseline() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--gold-fixture"]
        app.launch()
        XCTAssertTrue(app.staticTexts["portfolioValue"].waitForExistence(timeout: 10))
        let category = app.buttons["allocation-gold"]
        for _ in 0..<5 where !category.isHittable { app.swipeUp() }
        category.tap()
        XCTAssertTrue(app.staticTexts["goldValue"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["goldValue"].label, "₹15,80,089")
        XCTAssertTrue(app.staticTexts["Known invested"].exists)
        XCTAssertTrue(app.staticTexts["+0.55% today"].exists)
        let top = XCTAttachment(screenshot: app.screenshot()); top.name = "Mixed Gold summary and daily performance"; top.lifetime = .keepAlways; add(top)
        let sort = app.buttons["Sort gold holdings"]
        for _ in 0..<3 where !sort.isHittable { app.swipeUp() }
        sort.tap();app.buttons["Value: Low to High"].tap()
        app.swipeUp()
        let gullak = app.descendants(matching: .any)["gold-holding-gullak:gold"].firstMatch
        let sgb = app.descendants(matching: .any)["gold-holding-sgb-2028"].firstMatch
        XCTAssertTrue(gullak.exists && sgb.exists)
        XCTAssertTrue(gullak.label.contains("GULLAK"))
        XCTAssertTrue(gullak.label.contains("Return unavailable"))
        XCTAssertTrue(sgb.label.contains("SGB2028-IX"))
        XCTAssertTrue(sgb.label.contains("120 units"))
        XCTAssertLessThan(gullak.frame.minY,sgb.frame.minY)
        let rows = XCTAttachment(screenshot: app.screenshot()); rows.name = "Mixed Gold sorted holdings"; rows.lifetime = .keepAlways; add(rows)
    }

    private func statementPage(_ asset: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--statement-fixture"]
        app.launch()
        XCTAssertTrue(app.staticTexts["portfolioValue"].waitForExistence(timeout: 10))
        let category = app.buttons["allocation-" + asset]
        for _ in 0..<5 where !category.isHittable { app.swipeUp() }
        category.tap()
        return app
    }

    func testNPSPageUsesStatementUnitsWithoutDailyPerformance() {
        let app = statementPage("nps")
        XCTAssertTrue(app.staticTexts["statementValue"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["statementValue"].label, "₹72,020")
        XCTAssertEqual(app.staticTexts["statementPrincipal"].label, "₹60,000")
        XCTAssertTrue(app.staticTexts["statementGain"].label.contains("12,020"))
        XCTAssertTrue(app.staticTexts["npsXIRR-I"].label.contains("6.51%"))
        XCTAssertTrue(app.staticTexts["NPS Trajectory"].exists)
        XCTAssertFalse(app.staticTexts["DAILY PERFORMANCE"].exists)
        XCTAssertFalse(app.staticTexts["NSE/BSE Direct"].exists)
        let top = XCTAttachment(screenshot:app.screenshot()); top.name = "NPS instrument summary"; top.lifetime = .keepAlways; add(top)
        let sort = app.buttons["Sort NPS holdings"]
        for _ in 0..<3 where !sort.isHittable { app.swipeUp() }
        sort.tap();app.buttons["Value: Low to High"].tap()
        let c = app.descendants(matching:.any)["statement-holding-nps:I:C"].firstMatch
        let e = app.descendants(matching:.any)["statement-holding-nps:I:E"].firstMatch
        XCTAssertTrue(c.exists && e.exists)
        XCTAssertTrue(c.label.contains("800 units"))
        XCTAssertTrue(c.label.contains("NAV"))
        XCTAssertTrue(c.label.contains("Return unavailable"))
        XCTAssertLessThan(c.frame.minY,e.frame.minY)
        let rows = XCTAttachment(screenshot:app.screenshot()); rows.name = "NPS holdings"; rows.lifetime = .keepAlways; add(rows)
        app.buttons["statementBack"].tap()
        XCTAssertTrue(app.buttons["tab-Overview"].waitForExistence(timeout:5))
    }

    func testFixedDepositsPageUsesMaturityAmountsWithoutDailyPerformance() {
        let app = statementPage("fixedDeposit")
        XCTAssertTrue(app.staticTexts["statementValue"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["statementValue"].label, "₹3,60,000")
        XCTAssertFalse(app.staticTexts["statementPrincipal"].exists)
        XCTAssertFalse(app.staticTexts["statementGain"].exists)
        XCTAssertFalse(app.staticTexts["At maturity"].exists)
        XCTAssertTrue(app.staticTexts["MATURITY VALUE"].exists)
        XCTAssertTrue(app.staticTexts["Fixed Deposit Trajectory"].exists)
        XCTAssertFalse(app.staticTexts["DAILY PERFORMANCE"].exists)
        let top = XCTAttachment(screenshot:app.screenshot()); top.name = "Fixed Deposit instrument summary"; top.lifetime = .keepAlways; add(top)
        let sort = app.buttons["Sort fixed deposits"]
        for _ in 0..<3 where !sort.isHittable { app.swipeUp() }
        sort.tap();app.buttons["Value: Low to High"].tap()
        let first = app.descendants(matching:.any)["statement-holding-hdfc:fd:1234"].firstMatch
        let second = app.descendants(matching:.any)["statement-holding-hdfc:fd:5678"].firstMatch
        XCTAssertTrue(first.exists && second.exists)
        XCTAssertTrue(first.label.contains("1,20,000"))
        XCTAssertFalse(first.label.contains("Interest:"))
        XCTAssertFalse(first.label.contains("Principal:"))
        XCTAssertTrue(first.label.contains("7.25% p.a."))
        XCTAssertTrue(first.label.contains("31 Mar 2027"))
        XCTAssertLessThan(first.frame.minY,second.frame.minY)
        let rows = XCTAttachment(screenshot:app.screenshot()); rows.name = "Fixed Deposit holdings"; rows.lifetime = .keepAlways; add(rows)
        app.buttons["statementBack"].tap()
        XCTAssertTrue(app.buttons["tab-Overview"].waitForExistence(timeout:5))
    }

    func testRealEstateEmptyStateAndAddSheetHaveNoOwnershipOrLoanFields() {
        let app = launch()
        let category = app.buttons["allocation-realEstate"]
        for _ in 0..<5 where !category.isHittable { app.swipeUp() }
        XCTAssertTrue(category.exists)
        XCTAssertTrue(category.label.contains("0%"))
        let allocation = XCTAttachment(screenshot: app.screenshot()); allocation.name = "Homepage Real Estate allocation"; allocation.lifetime = .keepAlways; add(allocation)
        category.tap()
        XCTAssertTrue(app.staticTexts["realEstateEmpty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["realEstateBack"].exists)
        app.swipeDown()
        let hierarchy = XCTAttachment(string:app.debugDescription); hierarchy.name = "Real Estate empty geometry"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        let empty = XCTAttachment(screenshot: app.screenshot()); empty.name = "Real Estate empty state"; empty.lifetime = .keepAlways; add(empty)
        app.buttons["first-property"].tap()
        XCTAssertTrue(app.staticTexts["property-editor-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["property-class-apartment"].isSelected)
        app.buttons["property-class-house"].tap()
        XCTAssertTrue(app.buttons["property-class-house"].isSelected)
        XCTAssertTrue(app.textFields["property-name"].exists)
        XCTAssertFalse(app.textFields["property-ownership"].exists)
        XCTAssertFalse(app.textFields["Loan balance"].exists)
        XCTAssertFalse(app.buttons["save-property"].isEnabled)
        let sheet = XCTAttachment(screenshot: app.screenshot()); sheet.name = "Add Real Estate Property"; sheet.lifetime = .keepAlways; add(sheet)
        app.buttons["discard-property"].tap()
        XCTAssertTrue(app.staticTexts["realEstateEmpty"].exists)
    }

    func testRealEstateFullValuationRegistryAndEditSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--real-estate-fixture"]
        app.launch()
        XCTAssertTrue(app.staticTexts["portfolioValue"].waitForExistence(timeout: 10))
        let category = app.buttons["allocation-realEstate"]
        for _ in 0..<5 where !category.isHittable { app.swipeUp() }
        category.tap()
        XCTAssertTrue(app.staticTexts["realEstateValue"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["realEstateValue"].label, "₹1,50,00,000")
        let top = XCTAttachment(screenshot: app.screenshot()); top.name = "Real Estate valuation and trajectory"; top.lifetime = .keepAlways; add(top)
        let sort = app.buttons["Sort properties"]
        for _ in 0..<4 where !sort.isHittable { app.swipeUp() }
        sort.tap(); app.buttons["Value: Low to High"].tap()
        app.swipeUp()
        let first = app.buttons["property-card-22222222-2222-4222-8222-222222222222"]
        XCTAssertTrue(first.exists)
        let rows = XCTAttachment(screenshot: app.screenshot()); rows.name = "Real Estate registry"; rows.lifetime = .keepAlways; add(rows)
        first.tap()
        XCTAssertTrue(app.staticTexts["property-editor-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["property-name"].value as? String, "Brigade Orchards Villa 18")
        XCTAssertEqual(app.textFields["property-location"].value as? String, "Bengaluru, KA")
        XCTAssertFalse(app.textFields["property-ownership"].exists)
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
        XCTAssertTrue(app.buttons["homeDemo"].exists)
        XCTAssertFalse(app.staticTexts["Private Wealth"].exists)
        let indian = app.buttons["home-instrument-indianEquity"]
        let us = app.buttons["home-instrument-usEquity"]
        let funds = app.buttons["home-instrument-mutualFund"]
        let gold = app.buttons["home-instrument-gold"]
        XCTAssertTrue(indian.exists && us.exists && funds.exists && gold.exists)
        XCTAssertEqual(indian.frame.minY, us.frame.minY, accuracy: 1)
        XCTAssertEqual(funds.frame.minY, gold.frame.minY, accuracy: 1)
        XCTAssertEqual(indian.frame.minX, funds.frame.minX, accuracy: 1)
        XCTAssertEqual(us.frame.minX, gold.frame.minX, accuracy: 1)
        XCTAssertGreaterThan(funds.frame.minY, indian.frame.maxY)
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
        XCTAssertFalse(app.staticTexts["Connected Accounts"].exists)
        XCTAssertFalse(app.buttons["tab-Settings"].exists)
        app.buttons["tab-Holdings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["holding-hdfc"].firstMatch.waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["US Stocks"].waitForExistence(timeout: 5))
        app.buttons["equitiesBack"].tap()
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
