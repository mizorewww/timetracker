import XCTest

/// Feedback raised while a sheet is open must appear over that sheet, not
/// behind it. A widget start link for a task that no longer exists fails
/// immediately even while a sheet is up, so it raises scene feedback from
/// under the open Settings sheet.
final class SheetFeedbackUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFeedbackRaisedWhileASheetIsOpenAppearsOverTheSheet() throws {
        #if os(macOS)
        throw XCTSkip("Settings is its own window on macOS, not a sheet.")
        #else
        let app = launchDemoApp()
        let settingsButton = app.descendants(matching: .any)["settings.open"]
        guard settingsButton.waitForExistence(timeout: 15) else {
            throw XCTSkip("Settings is a sheet only in the compact shell.")
        }
        settingsButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.view"].waitForExistence(timeout: 10)
        )

        let missingTaskID = UUID().uuidString
        // Through the system, as a widget tap does, so the running app keeps
        // its sheet; `XCUIApplication.open` relaunches the app.
        XCUIDevice.shared.system.open(URL(
            string: "timetracker://timer/start?taskID=\(missingTaskID)&source=widget"
        )!)

        let alert = app.alerts.firstMatch
        XCTAssertTrue(
            alert.waitForExistence(timeout: 10),
            "The failure was not shown while the Settings sheet was open."
        )
        XCTAssertTrue(app.descendants(matching: .any)["settings.view"].exists)
        attachScreenshot(app, named: "Feedback alert over the Settings sheet")

        alert.buttons.firstMatch.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.view"].exists)
        #endif
    }
}
