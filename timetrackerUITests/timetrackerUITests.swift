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

        app.buttons["sidebar.Analytics"].click()
        XCTAssertTrue(app.staticTexts["分析"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Wall Time"].exists)
        XCTAssertTrue(app.staticTexts["今天时间分布"].exists)
        XCTAssertTrue(app.staticTexts["任务使用时间"].exists)

        app.buttons["sidebar.Settings"].click()
        XCTAssertTrue(app.otherElements["settings.view"].waitForExistence(timeout: 3) || app.staticTexts["同步"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["iCloud 容器"].exists)
        XCTAssertTrue(app.staticTexts["CloudKit 账号"].exists)
        XCTAssertTrue(app.buttons["重新检查 iCloud"].exists)
    }

    @MainActor
    func testTaskEditorAndPomodoroFlowOpen() throws {
        let app = launchApp()

        XCTAssertTrue(homeIsReady(in: app))
        app.buttons["home.newTask"].click()
        XCTAssertTrue(app.staticTexts["新建任务"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["保存"].exists)
        app.buttons["取消"].click()

        app.buttons["sidebar.Pomodoro"].click()
        XCTAssertTrue(app.staticTexts["pomodoro.title"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.buttons["pomodoro.startFocus"].exists ||
            app.staticTexts["可以完成本轮"].exists ||
            app.staticTexts["剩余时间"].exists
        )
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"
        app.terminate()
        app.launch()
        app.activate()
        return app
    }

    @MainActor
    private func homeIsReady(in app: XCUIApplication) -> Bool {
        app.buttons["home.startTimer"].waitForExistence(timeout: 8)
    }
}
