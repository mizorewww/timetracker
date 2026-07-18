import XCTest

final class LiveActivitySystemSurfaceUITests: XCTestCase {
    private static let auditedDynamicIslandSimulatorModels: Set<String> = [
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
    func testExpandedDynamicIslandShowsTheRunningTask() throws {
        #if os(iOS)
        #if targetEnvironment(simulator)
        let modelIdentifier = ProcessInfo.processInfo.environment[
            "SIMULATOR_MODEL_IDENTIFIER"
        ] ?? ""
        guard Self.auditedDynamicIslandSimulatorModels.contains(modelIdentifier) else {
            throw XCTSkip(
                "Run this screenshot test on an audited Dynamic Island iPhone simulator."
            )
        }
        #else
        throw XCTSkip(
            "This automated screenshot path is simulator-only; verify real devices manually."
        )
        #endif

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

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(
            springboard.wait(for: .runningForeground, timeout: 5)
        )
        let taskTitle = springboard.staticTexts[expectedTaskTitle]
        XCTAssertTrue(
            taskTitle.waitForExistence(timeout: 5),
            "The compact Dynamic Island should expose the running task title."
        )
        attachScreenshot(named: "live-activity-dynamic-island-compact")

        springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)
        )
        .press(forDuration: 1.2)

        XCTAssertTrue(
            taskTitle.waitForExistence(timeout: 5),
            "The expanded Dynamic Island should expose the running task title."
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
}
