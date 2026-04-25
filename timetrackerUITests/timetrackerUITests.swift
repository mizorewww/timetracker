import XCTest

final class timetrackerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPrimaryNavigationAndSettingsLoad() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["home.startTimer"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Active Timers"].exists)

        app.buttons["sidebar.Analytics"].click()
        XCTAssertTrue(app.staticTexts["分析"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Wall Time"].exists)

        app.buttons["sidebar.Settings"].click()
        XCTAssertTrue(app.otherElements["settings.view"].waitForExistence(timeout: 3) || app.staticTexts["同步"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["iCloud 容器"].exists)
    }

    @MainActor
    func testTaskEditorAndPomodoroFlowOpen() throws {
        let app = launchApp()

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
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            _ = launchApp()
        }
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        return app
    }
}
