import XCTest

/// Visits every tab and Settings and keeps a screenshot of each, so UI changes can be
/// reviewed from the result bundle. Run once per simulator appearance.
final class ScreenTourUITests: XCTestCase {
    func testEveryTab() {
        continueAfterFailure = false
        let app = launchDemoApp()
        XCTAssertTrue(app.descendants(matching: .any)["home.view"].waitForExistence(timeout: 15))

        for tab in ["Today", "Inbox", "Tasks", "Focus", "Analytics"] {
            let button = app.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            keepScreenshot(of: app, named: tab.lowercased())
        }

        app.buttons["Today"].tap()
        let settings = app.buttons["settings.open"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        keepScreenshot(of: app, named: "settings")
    }

    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
