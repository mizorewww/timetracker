import XCTest

final class LiveActivitySystemSurfaceUITests: XCTestCase {
    private static let auditedDynamicIslandModels: Set<String> = [
        "iPhone15,2", "iPhone15,3", "iPhone15,4", "iPhone15,5",
        "iPhone16,1", "iPhone16,2",
        "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4",
        "iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,4"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    @MainActor
    func testDynamicIslandPresentsTheRegisteredRunningTask() throws {
        #if os(iOS)
        #if targetEnvironment(simulator)
        let modelIdentifier = ProcessInfo.processInfo.environment[
            "SIMULATOR_MODEL_IDENTIFIER"
        ] ?? ""
        #else
        let modelIdentifier = Self.physicalDeviceModelIdentifier
        #endif
        guard Self.auditedDynamicIslandModels.contains(modelIdentifier) else {
            throw XCTSkip(
                "Run this screenshot test on an audited Dynamic Island iPhone."
            )
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-TimeTrackerAutomaticDemoDataModeOverride", "replaceOnLaunch",
            "-TimeTrackerAutomaticDemoSeedingDisabled", "NO"
        ]
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"
        app.launchEnvironment["TIMETRACKER_UI_AUDIT_ROUTE"] = "today"
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["home.view"]
                .waitForExistence(timeout: 8)
        )
        let elapsed = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "home.timer.elapsed."
            ))
            .firstMatch
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        let expectedTaskTitle = "Read Apple HIG"
        let primaryTask = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@ AND value == %@",
            "home.activeTimer.",
            expectedTaskTitle,
            "Running"
        ))
        .firstMatch
        XCTAssertTrue(
            primaryTask.waitForExistence(timeout: 5),
            "The demo's overdue Pomodoro must reconcile before system-surface assertions."
        )
        let runningTaskRows = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND value == %@",
            "home.activeTimer.",
            "Running"
        ))
        XCTAssertEqual(
            runningTaskRows.count,
            1,
            "The expected task must be the only running row before inspecting its projection."
        )

        let settingsButton = app.descendants(matching: .any)["settings.open"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.view"]
                .waitForExistence(timeout: 5)
        )
        let general = app.buttons["settings.category.general"].firstMatch
        XCTAssertTrue(general.waitForExistence(timeout: 3))
        general.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.liveActivity.status.active"]
                .waitForExistence(timeout: 8),
            "ActivityKit must accept and register the timer before inspecting system surfaces."
        )
        attachScreenshot(named: "live-activity-registration-status")

        let settingsBack = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(settingsBack.waitForExistence(timeout: 3) && settingsBack.isHittable)
        settingsBack.tap()
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 3) && done.isHittable)
        done.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.view"]
                .waitForNonExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["home.view"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            primaryTask.waitForExistence(timeout: 5),
            "The registered timer must remain running after Settings closes."
        )
        attachScreenshot(named: "live-activity-app-restored-after-registration")

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(
            springboard.wait(for: .runningForeground, timeout: 5)
        )
        waitForSystemSurfaceTransition()
        attachScreenshot(named: "live-activity-dynamic-island-compact-or-minimal")

        let taskTitle = springboard.descendants(matching: .any)
            .matching(NSPredicate(
                format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
                expectedTaskTitle,
                expectedTaskTitle
            ))
            .firstMatch
        let expanded = expandDynamicIslandTask(
            taskTitle,
            in: springboard
        )
        if !expanded {
            attachScreenshot(named: "failure-live-activity-dynamic-island-expanded")
            let hierarchy = XCTAttachment(string: springboard.debugDescription)
            hierarchy.name = "Accessibility - live-activity-dynamic-island-expanded"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(
            expanded,
            "Expanding Time Tracker's compact or minimal presentation should expose the running task title."
        )
        XCTAssertFalse(springboard.buttons["Stop"].exists)
        attachScreenshot(named: "live-activity-dynamic-island-expanded")
        #else
        throw XCTSkip("Dynamic Island is available only on supported iPhones.")
        #endif
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func waitForSystemSurfaceTransition() {
        RunLoop.current.run(until: Date().addingTimeInterval(5))
    }

    #if os(iOS)
    @MainActor
    private func expandDynamicIslandTask(
        _ taskTitle: XCUIElement,
        in springboard: XCUIApplication
    ) -> Bool {
        for horizontalOffset in [0.71, 0.5, 0.29] {
            springboard.coordinate(
                withNormalizedOffset: CGVector(
                    dx: horizontalOffset,
                    dy: 0.04
                )
            )
            .press(forDuration: 1.2)
            if taskTitle.waitForExistence(timeout: 4) {
                return true
            }
            XCUIDevice.shared.press(.home)
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        return false
    }
    #endif

    private static var physicalDeviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
