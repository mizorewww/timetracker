#if os(iOS)
import XCTest

/// The app's own cost of launching, showing each compact-shell tab and
/// scrolling it, for comparing changes made for performance (AD-144). Run in
/// Release (`UI_TEST_CONFIGURATION=Release`). Wall-clock time is not
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

    func testSwitchingTabs() throws {
        let app = try launchCompactShell()
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)]) {
            for tab in tabs {
                app.buttons[tab].tap()
            }
        }
    }

    func testScrollingEachTab() throws {
        let app = try launchCompactShell()
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

    private func launchCompactShell() throws -> XCUIApplication {
        let app = launchDemoApp()
        XCTAssertTrue(app.descendants(matching: .any)["home.view"].waitForExistence(timeout: 15))
        guard app.buttons["settings.open"].exists else {
            throw XCTSkip("Tab measurements walk the compact shell's tabs.")
        }
        return app
    }
}
#endif
