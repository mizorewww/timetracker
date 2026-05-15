import XCTest

final class timetrackerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    @MainActor
    func testLaunchSmokeShowsHome() throws {
        let app = launchApp()

        XCTAssertTrue(homeIsReady(in: app))
    }

    @MainActor
    func testPrimaryNavigationAndSettingsLoad() throws {
        let app = launchApp()

        XCTAssertTrue(homeIsReady(in: app))
        XCTAssertTrue(
            app.descendants(matching: .any)["home.activeTimers"].waitForExistence(timeout: 2) ||
            anyStaticText(["正在计时", "正在計時", "Active Timers"], in: app)
        )

        openSection("分析", sidebarIdentifier: "sidebar.Analytics", in: app)
        XCTAssertTrue(analyticsIsReady(in: app))

        openSection("设置", sidebarIdentifier: "settings.open", in: app)
        XCTAssertTrue(app.otherElements["settings.view"].waitForExistence(timeout: 3) || app.staticTexts["设置"].waitForExistence(timeout: 3) || app.staticTexts["Settings"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testTaskEditorAndPomodoroFlowOpen() throws {
        let app = launchApp()

        XCTAssertTrue(homeIsReady(in: app))
        app.buttons["home.newTask"].tap()
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 3) || app.buttons["Save"].waitForExistence(timeout: 3) || app.textFields["任务名称"].waitForExistence(timeout: 3))
        closePresentedEditor(in: app)

        openSection("番茄钟", sidebarIdentifier: "sidebar.Pomodoro", in: app)
        XCTAssertTrue(app.staticTexts["pomodoro.title"].waitForExistence(timeout: 3) || app.staticTexts["番茄钟"].waitForExistence(timeout: 3) || app.staticTexts["Pomodoro"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testUIRefactorBaselineScreenshots() throws {
        let app = launchApp()

        XCTAssertTrue(homeIsReady(in: app))
        try capture("iphone-home-baseline", app: app)

        openSection("分析", sidebarIdentifier: "sidebar.Analytics", in: app)
        XCTAssertTrue(analyticsIsReady(in: app))
        try capture("iphone-analytics-baseline", app: app)

        openSection("任务", sidebarIdentifier: "sidebar.Tasks", in: app)
        XCTAssertTrue(app.staticTexts["Design macOS UI"].waitForExistence(timeout: 3))
        try capture("iphone-tasks-baseline", app: app)

        app.staticTexts["Design macOS UI"].firstMatch.tap()
        XCTAssertTrue(taskDetailIsReady(in: app))
        try capture("iphone-task-detail-baseline", app: app)
    }

    @MainActor
    func testSidebarTaskOpensTaskDetailWhenSidebarIsVisible() throws {
        let app = launchApp()

        XCTAssertTrue(homeIsReady(in: app))
        let revealSidebar = app.descendants(matching: .any)["sidebar.show"].firstMatch
        if revealSidebar.waitForExistence(timeout: 1), revealSidebar.isHittable {
            revealSidebar.tap()
        }

        let sidebarTask = app.descendants(matching: .any)["sidebar.task.Time Tracker App"].firstMatch
        guard sidebarTask.waitForExistence(timeout: 3) else {
            throw XCTSkip("Sidebar is not visible in this size class.")
        }

        sidebarTask.tap()

        XCTAssertTrue(taskDetailIsReady(in: app))
        XCTAssertTrue(app.staticTexts["Time Tracker App"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.textFields["任务名称"].waitForExistence(timeout: 1))
        try capture("ipad-sidebar-task-detail-fix", app: app)
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"
        app.launch()
        app.activate()
        return app
    }

    @MainActor
    private func homeIsReady(in app: XCUIApplication) -> Bool {
        app.buttons["home.startTimer"].waitForExistence(timeout: 8)
    }

    @MainActor
    private func analyticsIsReady(in app: XCUIApplication) -> Bool {
        let decisionSummary = app.descendants(matching: .any)["analytics.decisionSummary"]
        let periodControl = app.descendants(matching: .any)["analytics.periodControl"]
        return decisionSummary.waitForExistence(timeout: 8) &&
        periodControl.waitForExistence(timeout: 2)
    }

    @MainActor
    private func taskDetailIsReady(in app: XCUIApplication) -> Bool {
        app.buttons["补录时间"].waitForExistence(timeout: 3) ||
        app.buttons["添加时间"].waitForExistence(timeout: 1) ||
        app.buttons["Add Time"].waitForExistence(timeout: 1)
    }

    @MainActor
    private func openSection(_ tabTitle: String, sidebarIdentifier: String, in app: XCUIApplication) {
        let identifiedElement = app.descendants(matching: .any)[sidebarIdentifier]
        if identifiedElement.waitForExistence(timeout: 1) {
            identifiedElement.firstMatch.tap()
            return
        }

        if app.tabBars.buttons[tabTitle].waitForExistence(timeout: 3) {
            app.tabBars.buttons[tabTitle].tap()
            return
        }

        if app.buttons[tabTitle].waitForExistence(timeout: 1) {
            app.buttons[tabTitle].firstMatch.tap()
            return
        }

        if app.staticTexts[tabTitle].waitForExistence(timeout: 1) {
            app.staticTexts[tabTitle].firstMatch.tap()
            return
        }

        XCTFail("Could not open section \(tabTitle)")
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) throws {
        guard let directory = ProcessInfo.processInfo.environment["UI_SCREENSHOT_DIR"], !directory.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try app.screenshot().pngRepresentation.write(to: url.appendingPathComponent("\(name).png"))
    }

    @MainActor
    private func closePresentedEditor(in app: XCUIApplication) {
        let cancel = app.buttons["取消"].exists ? app.buttons["取消"].firstMatch : app.buttons["Cancel"].firstMatch
        if cancel.exists, cancel.isHittable {
            cancel.tap()
            return
        }

        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    private func anyStaticText(_ labels: [String], in app: XCUIApplication) -> Bool {
        labels.contains { app.staticTexts[$0].waitForExistence(timeout: 1) }
    }
}
