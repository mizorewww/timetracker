import XCTest

extension XCTestCase {
    /// Launches an isolated demo-data app in English and waits until initial
    /// configuration finishes. The app is terminated at teardown.
    func launchDemoApp(
        windowSize: CGSize? = nil,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-TimeTrackerAutomaticDemoDataModeOverride", "replaceOnLaunch",
            "-TimeTrackerAutomaticDemoSeedingDisabled", "NO",
        ] + extraArguments
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"
        #if os(macOS)
        if let windowSize {
            app.launchEnvironment["TIMETRACKER_UI_TEST_WINDOW_WIDTH"] = "\(windowSize.width)"
            app.launchEnvironment["TIMETRACKER_UI_TEST_WINDOW_HEIGHT"] = "\(windowSize.height)"
        }
        #endif
        app.launch()
        addTeardownBlock {
            if app.state != .notRunning {
                app.terminate()
            }
        }
        #if os(macOS)
        let readyElement = app.descendants(matching: .any)["home.view"]
        #else
        let readyElement = app.otherElements["app.initialConfiguration.ready"]
        #endif
        XCTAssertTrue(
            readyElement.waitForExistence(timeout: 90),
            "The app never finished initial configuration."
        )
        return app
    }

    func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
