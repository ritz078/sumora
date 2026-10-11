import XCTest
@MainActor
final class GoldSettingsTests: XCTestCase {
 func testGoldSetupExplainsRequiredConnectionsInSettings() {
  let app=XCUIApplication();app.launchArguments=["--ui-testing"];app.launch()
  XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout:10))
  app.buttons["homeSettings"].tap()
  let guidance=app.staticTexts["Sign in to Sumora, then connect Gmail to import Gullak gold."]
  for _ in 0..<6 where !guidance.isHittable {app.swipeUp()}
  XCTAssertTrue(guidance.isHittable)
  XCTAssertFalse(app.buttons["sync-gullak"].exists)
  let image=XCTAttachment(screenshot:app.screenshot());image.name="Gullak setup in Settings";image.lifetime = .keepAlways;add(image)
 }
}
