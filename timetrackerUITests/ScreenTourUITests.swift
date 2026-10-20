#if os(iOS)
import XCTest

/// Visits every tab and Settings in the compact shell and keeps a screenshot
/// of each, so UI changes can be reviewed from the result bundle. Run once per
/// simulator appearance.
final class ScreenTourUITests: XCTestCase {
    func testEveryTab() throws {
        continueAfterFailure = false
        let app = launchDemoApp()
        XCTAssertTrue(app.descendants(matching: .any)["home.view"].waitForExistence(timeout: 15))
        guard app.buttons["settings.open"].exists else {
            throw XCTSkip("The tour walks the compact shell's tabs.")
        }

        for tab in ["Today", "Inbox", "Tasks", "Focus", "Analytics"] {
            let button = app.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            attachScreenshot(app, named: tab.lowercased())
        }

        app.buttons["Today"].tap()
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.view"].waitForExistence(timeout: 10))
        attachScreenshot(app, named: "settings")
    }
}
#endif
