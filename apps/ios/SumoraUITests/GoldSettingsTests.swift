import XCTest
@MainActor
final class GoldSettingsTests: XCTestCase {
 func testGoldSetupExplainsRequiredConnectionsInSettings() {
  let app=XCUIApplication();app.launchArguments=["--ui-testing"];app.launch()
  XCTAssertTrue(app.buttons["tab-Settings"].waitForExistence(timeout:10))
  app.buttons["tab-Settings"].tap()
  let guidance=app.staticTexts["Connect Zerodha to sign in, then connect Gmail under Connections to import Gullak gold."]
  for _ in 0..<6 where !guidance.isHittable {app.swipeUp()}
  XCTAssertTrue(guidance.isHittable)
  XCTAssertFalse(app.buttons["sync-gullak"].exists)
  let image=XCTAttachment(screenshot:app.screenshot());image.name="Gullak setup in Settings";image.lifetime = .keepAlways;add(image)
 }
}
