import XCTest

#if os(macOS)
/// Regular-shell (macOS) navigation regressions driven through real clicks.
final class SidebarTaskDetailNavigationUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        launchDemoApp(windowSize: CGSize(width: 1400, height: 900))
    }

    private func click(_ element: XCUIElement, in app: XCUIApplication) {
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3))
        element.click()
    }

    private func sidebarTaskRow(named title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "sidebar.task.",
                title
            ))
            .firstMatch
    }

    func testSidebarTaskActivationOpensTaskDetail() {
        let app = launchApp()
        let taskTitle = "Time Tracker App"
        let row = sidebarTaskRow(named: taskTitle, in: app)

        XCTAssertTrue(
            row.waitForExistence(timeout: 15),
            "The demo task must be visible in the sidebar task tree."
        )
        click(row, in: app)

        let detail = app.descendants(matching: .any)["task.detail"].firstMatch
        XCTAssertTrue(
            detail.waitForExistence(timeout: 15),
            "Clicking a sidebar task row must open the task detail, not a blank column."
        )

        let titleField = app.descendants(matching: .any)["task.editor.title.field"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertEqual(
            titleField.value as? String,
            taskTitle,
            "The detail must show the task that was clicked in the sidebar."
        )
        attachScreenshot(app, named: "macos-sidebar-task-detail")
    }

    /// A completed Inbox item moves to the Completed section and can be
    /// reopened from the same control, leaving exactly one live row each time.
    func testInboxItemCompletesAndReopens() {
        let app = launchApp()
        click(app.descendants(matching: .any)["sidebar.Inbox"].firstMatch, in: app)

        let field = app.descendants(matching: .any)["inbox.capture.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        click(field, in: app)
        let title = "UITest inbox \(UUID().uuidString.prefix(8))"
        field.typeText(title + "\n")

        let completionControls = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item.completion.")
        )
        let rowField = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "inbox.item.", title)
        ).firstMatch
        XCTAssertTrue(rowField.waitForExistence(timeout: 10))
        let itemID = String(rowField.identifier.dropFirst("inbox.item.".count))
        let completion = completionControls.matching(identifier: "inbox.item.completion.\(itemID)")

        click(completion.firstMatch, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["inbox.completed.disclosure"].waitForExistence(timeout: 5)
        )
        XCTAssertEqual(completion.count, 1, "Completing must leave one live row, not a stale open cell.")
        attachScreenshot(app, named: "macos-inbox-completed")

        click(completion.firstMatch, in: app)
        let reopenedPredicate = NSPredicate { _, _ in completion.count == 1 }
        expectation(for: reopenedPredicate, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        attachScreenshot(app, named: "macos-inbox-reopened")
    }
}
#endif
