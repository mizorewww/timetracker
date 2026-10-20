import XCTest

/// Baseline for the UIKit rewrite (AD-144): the app's own cost of launching,
/// showing each tab and scrolling it, measured the same way before and after.
/// Run in Release (`UI_TEST_CONFIGURATION=Release`). Wall-clock time is not
/// measured: XCUITest's waits for an idle app dominate it.
final class PagePerformanceUITests: XCTestCase {
    /// Tab labels; the tests launch in English.
    private let tabs = ["Today", "Inbox", "Tasks", "Focus", "Analytics"]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds once, then measures launches that reuse the seeded store.
    func testLaunch() {
        let reuseSeed = ["-TimeTrackerAutomaticDemoDataModeOverride", "seedIfEmpty"]
        launchDemoApp(extraArguments: reuseSeed).terminate()
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            launchDemoApp(extraArguments: reuseSeed).terminate()
        }
    }

    func testSwitchingTabs() {
        let app = launchShownApp()
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)]) {
            for tab in tabs {
                app.buttons[tab].tap()
            }
        }
    }

    func testScrollingEachTab() {
        let app = launchShownApp()
        measure(metrics: [XCTHitchMetric(application: app), XCTCPUMetric(application: app)]) {
            for tab in tabs {
                app.buttons[tab].tap()
                let content = app.collectionViews.firstMatch.exists
                    ? app.collectionViews.firstMatch
                    : app.scrollViews.firstMatch
                content.swipeUp(velocity: .fast)
                content.swipeDown(velocity: .fast)
            }
        }
    }

    private func launchShownApp() -> XCUIApplication {
        let app = launchDemoApp()
        XCTAssertTrue(app.descendants(matching: .any)["home.view"].waitForExistence(timeout: 15))
        return app
    }
}
