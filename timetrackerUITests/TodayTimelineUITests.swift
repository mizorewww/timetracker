import XCTest

/// Renders Today's timeline from demo data so axis, grid, and bar changes get
/// a screenshot at normal text size.
final class TodayTimelineUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTodayTimelineRendersDemoBars() {
        let app = launchDemoApp(windowSize: CGSize(width: 1280, height: 900))

        // Today's sections load lazily; scroll until the timeline is built.
        let chart = app.descendants(matching: .any)["home.timeline.chart"]
        let home = app.descendants(matching: .any)["home.view"]
        for _ in 0 ..< 8 where chart.waitForExistence(timeout: 2) == false {
            scrollDown(home)
        }
        XCTAssertTrue(chart.exists, "Today's timeline chart never rendered.")
        let bar = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'timeline.bar.'"))
            .firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "Demo data produced no timeline bars.")
        scrollDown(home)
        attachScreenshot(app, named: "Today timeline")
    }

    /// macOS scrolls with a pointer; iOS simulators without pointer support
    /// need a swipe.
    private func scrollDown(_ element: XCUIElement) {
        #if os(macOS)
        element.scroll(byDeltaX: 0, deltaY: -400)
        #else
        element.swipeUp()
        #endif
    }
}
