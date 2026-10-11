import XCTest
@MainActor
final class AppLoginTests:XCTestCase {
 func testSignedOutAppShowsOnlyGoogleLogin() {
  let app=XCUIApplication();app.launchArguments=["--ui-testing","--auth-testing"];app.launch()
  XCTAssertTrue(app.buttons["sign-in-google"].waitForExistence(timeout:10))
  XCTAssertFalse(app.buttons["homeSettings"].exists)
  XCTAssertFalse(app.buttons["connect-gmail"].exists)
 }
}
