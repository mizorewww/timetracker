import XCTest

/// Visits every tab and keeps a screenshot of each, so UI changes can be
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
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = tab.lowercased()
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}
