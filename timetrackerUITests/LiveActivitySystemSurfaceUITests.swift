import XCTest

/// Smoke test for the Live Activity projection. Simulator evidence is
/// diagnostic only; the screenshots are for visual review.
final class LiveActivitySystemSurfaceUITests: XCTestCase {
    /// Single-screen iPhones with a Dynamic Island (iPhone 14 Pro through 17).
    private static let dynamicIslandModels: Set<String> = [
        "iPhone15,2", "iPhone15,3", "iPhone15,4", "iPhone15,5",
        "iPhone16,1", "iPhone16,2",
        "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4",
        "iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,4",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    @MainActor
    func testRunningTimerAppearsOnSystemSurfaces() throws {
        #if os(iOS) && targetEnvironment(simulator)
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        guard Self.dynamicIslandModels.contains(model) else {
            throw XCTSkip("Run on a single-screen Dynamic Island iPhone simulator.")
        }
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--uitesting-live-activity-long-timer",
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-TimeTrackerAutomaticDemoDataModeOverride", "replaceOnLaunch",
            "-TimeTrackerAutomaticDemoSeedingDisabled", "NO",
        ]
        app.launch()

        let expectedTaskTitle = "Read Apple HIG"
        let runningTask = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@ AND value == %@",
            "home.activeTimer.",
            expectedTaskTitle,
            "Running"
        )).firstMatch
        XCTAssertTrue(runningTask.waitForExistence(timeout: 20))

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 5))

        revealNotificationCenter(in: springboard)
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
        }
        let lockScreenTitle = springboard.descendants(matching: .any)["liveActivity.lockScreen.title"]
        XCTAssertTrue(lockScreenTitle.waitForExistence(timeout: 10))
        XCTAssertEqual(lockScreenTitle.label, expectedTaskTitle)
        XCTAssertTrue(
            springboard.descendants(matching: .any)["liveActivity.lockScreen.timer"].exists
        )
        attachScreenshot(named: "live-activity-lock-screen")

        XCUIDevice.shared.press(.home)
        let compactTimer = springboard.descendants(matching: .any)["liveActivity.compact.timer"]
        XCTAssertTrue(compactTimer.waitForExistence(timeout: 10))
        attachScreenshot(named: "live-activity-dynamic-island-compact")
        #else
        throw XCTSkip("Live Activity system surfaces run only on iOS simulators.")
        #endif
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    #if os(iOS)
    /// Swipes down from the top-leading edge; Notification Center has no
    /// accessibility element to drag.
    @MainActor
    private func revealNotificationCenter(in springboard: XCUIApplication) {
        let topLeading = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.005))
        let lowerScreen = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8))
        topLeading.press(forDuration: 0.1, thenDragTo: lowerScreen)
    }
    #endif
}
