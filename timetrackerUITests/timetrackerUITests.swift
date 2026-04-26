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
        XCTAssertTrue(app.staticTexts["Active Timers"].exists)

        openSection("分析", sidebarIdentifier: "sidebar.Analytics", in: app)
        XCTAssertTrue(app.staticTexts["分析"].waitForExistence(timeout: 3))

        openSection("设置", sidebarIdentifier: "settings.open", in: app)
        XCTAssertTrue(app.otherElements["settings.view"].waitForExistence(timeout: 3) || app.staticTexts["设置"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testTaskEditorAndPomodoroFlowOpen() throws {
        let app = launchApp()

        XCTAssertTrue(homeIsReady(in: app))
        app.buttons["home.newTask"].tap()
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 3) || app.textFields["任务名称"].waitForExistence(timeout: 3))
        if app.buttons["取消"].exists {
            app.buttons["取消"].tap()
        }

        openSection("番茄钟", sidebarIdentifier: "sidebar.Pomodoro", in: app)
        XCTAssertTrue(app.staticTexts["pomodoro.title"].waitForExistence(timeout: 3) || app.staticTexts["番茄钟"].waitForExistence(timeout: 3))
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
    private func openSection(_ tabTitle: String, sidebarIdentifier: String, in app: XCUIApplication) {
        if app.buttons[sidebarIdentifier].exists {
            app.buttons[sidebarIdentifier].tap()
            return
        }

        if app.tabBars.buttons[tabTitle].waitForExistence(timeout: 3) {
            app.tabBars.buttons[tabTitle].tap()
            return
        }

        app.buttons[tabTitle].tap()
    }
}
