import Vision
import XCTest

final class LiveActivitySystemSurfaceUITests: XCTestCase {
    private static let auditedDynamicIslandModels: Set<String> = [
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
    func testDynamicIslandPresentsTheRegisteredRunningTask() throws {
        #if os(iOS) && targetEnvironment(simulator)
        let modelIdentifier = ProcessInfo.processInfo.environment[
            "SIMULATOR_MODEL_IDENTIFIER"
        ] ?? ""
        guard Self.auditedDynamicIslandModels.contains(modelIdentifier) else {
            throw XCTSkip(
                "Run this screenshot test on an audited Dynamic Island iPhone."
            )
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
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["home.view"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["app.initialConfiguration.ready"]
                .waitForExistence(timeout: 20),
            "The app must finish startup configuration before fixture assertions."
        )
        let expectedTaskTitle = "Read Apple HIG"
        let primaryTask = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@ AND value == %@",
            "home.activeTimer.",
            expectedTaskTitle,
            "Running"
        ))
        .firstMatch
        let fixtureReady = primaryTask.waitForExistence(timeout: 8)
        if !fixtureReady {
            attachHierarchy(named: "live-activity-fixture-startup-failure", app: app)
        }
        XCTAssertTrue(
            fixtureReady,
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
        let elapsedMatches = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "home.timer.elapsed."
            ))
        let elapsed = elapsedMatches.firstMatch
        XCTAssertTrue(
            elapsed.waitForExistence(timeout: 5),
            "The screenshot fixture must expose its live elapsed clock."
        )
        XCTAssertEqual(
            elapsedMatches.count,
            1,
            "The fixture must expose one elapsed clock for its one running task."
        )
        assertLongElapsedFixture(elapsed)

        let settingsButton = app.buttons["settings.open"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
        let settingsView = app.descendants(matching: .any)["settings.view"]
        if !settingsView.waitForExistence(timeout: 5) {
            settingsButton.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).tap()
        }
        XCTAssertTrue(
            settingsView.waitForExistence(timeout: 5),
            "The scripted Settings coordinate must open its sheet."
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
        authorizeLiveActivitiesIfNeeded(in: springboard)
        waitForSystemSurfaceTransition()
        let compactScreenshot = attachScreenshot(
            named: "live-activity-dynamic-island-compact-or-minimal"
        )
        try assertScreenshotContainsLongElapsedClock(
            compactScreenshot,
            surfaceName: "Compact Dynamic Island",
            normalizedSurfaceRegion: CGRect(
                x: 0.2,
                y: 0.9,
                width: 0.6,
                height: 0.1
            )
        )

        let compactLeading = uniqueSystemSurfaceElement(
            identifier: "liveActivity.compact.leading",
            in: springboard
        )
        let compactTimer = uniqueSystemSurfaceElement(
            identifier: "liveActivity.compact.timer",
            in: springboard
        )
        XCTAssertEqual(compactLeading.label, expectedTaskTitle)
        let initialCompactValue = assertElapsedTimerSemantics(compactTimer)
        XCTAssertTrue(
            waitForTimerValueToAdvance(
                compactTimer,
                from: initialCompactValue,
                timeout: 4
            ),
            "The compact Dynamic Island accessibility value must remain live."
        )
        assertCompactLayout(
            leading: compactLeading,
            timer: compactTimer,
            screenFrame: springboard.frame
        )

        revealNotificationCenter(in: springboard)
        let lockScreenTitle = uniqueSystemSurfaceElement(
            identifier: "liveActivity.lockScreen.title",
            in: springboard
        )
        let lockScreenTimer = uniqueSystemSurfaceElement(
            identifier: "liveActivity.lockScreen.timer",
            in: springboard
        )
        XCTAssertEqual(lockScreenTitle.label, expectedTaskTitle)
        _ = assertElapsedTimerSemantics(lockScreenTimer)
        let lockScreenScreenshot = attachScreenshot(named: "live-activity-lock-screen")
        try assertScreenshotContainsLongElapsedClock(
            lockScreenScreenshot,
            surfaceName: "Lock Screen",
            normalizedSurfaceRegion: CGRect(
                x: 0.02,
                y: 0.04,
                width: 0.96,
                height: 0.28
            )
        )
        assertLockScreenLayout(
            title: lockScreenTitle,
            timer: lockScreenTimer,
            screenFrame: springboard.frame
        )
        XCUIDevice.shared.press(.home)
        waitForSystemSurfaceTransition()

        let expanded = expandDynamicIslandTask(in: springboard)
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
        let expandedTitle = uniqueSystemSurfaceElement(
            identifier: "liveActivity.expanded.title",
            in: springboard
        )
        let expandedTimer = uniqueSystemSurfaceElement(
            identifier: "liveActivity.expanded.timer",
            in: springboard
        )
        XCTAssertEqual(expandedTitle.label, expectedTaskTitle)
        _ = assertElapsedTimerSemantics(expandedTimer)
        let expandedScreenshot = attachScreenshot(
            named: "live-activity-dynamic-island-expanded"
        )
        try assertScreenshotContainsLongElapsedClock(
            expandedScreenshot,
            surfaceName: "Expanded Dynamic Island",
            normalizedSurfaceRegion: CGRect(
                x: 0.1,
                y: 0.8,
                width: 0.8,
                height: 0.2
            )
        )
        assertExpandedLayout(
            title: expandedTitle,
            timer: expandedTimer,
            screenFrame: springboard.frame
        )
        XCTAssertFalse(springboard.buttons["Stop"].exists)
        #else
        throw XCTSkip("Live Activity system-surface screenshots run only on audited iOS simulators.")
        #endif
    }

    @MainActor
    @discardableResult
    private func attachScreenshot(named name: String) -> XCUIScreenshot {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return screenshot
    }

    private func assertScreenshotContainsLongElapsedClock(
        _ screenshot: XCUIScreenshot,
        surfaceName: String,
        normalizedSurfaceRegion: CGRect
    ) throws {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.regionOfInterest = normalizedSurfaceRegion
        let handler = VNImageRequestHandler(
            data: screenshot.pngRepresentation,
            options: [:]
        )
        try handler.perform([request])
        let recognizedLines = request.results?
            .compactMap { $0.topCandidates(1).first?.string } ?? []
        let recognizedText = recognizedLines.joined(separator: "\n")
        let longElapsedClock = #"(?:[89]|[1-9][0-9]+):[0-5][0-9]:[0-5][0-9]"#
        let containsLongElapsedClock = recognizedLines.contains { line in
            line.filter { !$0.isWhitespace }.range(
                of: longElapsedClock,
                options: .regularExpression
            ) != nil
        }

        XCTAssertTrue(
            containsLongElapsedClock,
            "\(surfaceName) screenshot must visibly render the multi-hour HH:MM:SS stopwatch inside its own ROI. Vision recognized: \(recognizedText)"
        )
    }

    @MainActor
    private func waitForSystemSurfaceTransition() {
        RunLoop.current.run(until: Date().addingTimeInterval(5))
    }

    @MainActor
    private func attachHierarchy(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    #if os(iOS)
    @MainActor
    private func revealNotificationCenter(in springboard: XCUIApplication) {
        let topLeading = springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.15, dy: 0.005)
        )
        let lowerScreen = springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8)
        )
        topLeading.press(forDuration: 0.1, thenDragTo: lowerScreen)
        waitForSystemSurfaceTransition()
    }

    @MainActor
    private func authorizeLiveActivitiesIfNeeded(in springboard: XCUIApplication) {
        revealNotificationCenter(in: springboard)
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 3) {
            allow.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).tap()
            waitForSystemSurfaceTransition()
            XCTAssertTrue(allow.waitForNonExistence(timeout: 2))
        }
        XCUIDevice.shared.press(.home)
    }
    #endif

    @MainActor
    private func uniqueSystemSurfaceElement(
        identifier: String,
        in springboard: XCUIApplication
    ) -> XCUIElement {
        let matches = springboard.descendants(matching: .any)
            .matching(identifier: identifier)
        let element = matches.firstMatch
        XCTAssertTrue(
            element.waitForExistence(timeout: 4),
            "The system surface must expose \(identifier)."
        )
        XCTAssertEqual(
            matches.count,
            1,
            "Each Live Activity presentation needs a unique accessibility identifier."
        )
        return element
    }

    @discardableResult
    private func assertElapsedTimerSemantics(_ timer: XCUIElement) -> String {
        XCTAssertEqual(timer.label, "Elapsed")
        let value = timer.value as? String ?? ""
        XCTAssertEqual(
            value.filter { $0 == ":" }.count,
            2,
            "The accessibility value must retain the full HH:MM:SS stopwatch."
        )
        let fields = value.split(separator: ":")
        XCTAssertEqual(fields.count, 3)
        XCTAssertGreaterThanOrEqual(
            fields.first.flatMap { Int($0) } ?? -1,
            8,
            "Every system presentation must retain the original multi-hour start date."
        )
        return value
    }

    private func assertLongElapsedFixture(_ elapsed: XCUIElement) {
        let clock = [elapsed.value as? String, elapsed.label]
            .compactMap { $0 }
            .first { $0.filter { $0 == ":" }.count == 2 } ?? ""
        let fields = clock.split(separator: ":")
        XCTAssertEqual(fields.count, 3, "The fixture clock must use HH:MM:SS.")
        guard let hours = fields.first.flatMap({ Int($0) }) else {
            XCTFail("The fixture clock must begin with a numeric hour field.")
            return
        }
        XCTAssertGreaterThanOrEqual(
            hours,
            8,
            "The layout fixture must exercise a multi-hour stopwatch."
        )
    }

    @MainActor
    private func waitForTimerValueToAdvance(
        _ timer: XCUIElement,
        from initialValue: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let currentValue = timer.value as? String,
               currentValue != initialValue
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    private func assertCompactLayout(
        leading: XCUIElement,
        timer: XCUIElement,
        screenFrame: CGRect
    ) {
        let leadingFrame = leading.frame
        let timerFrame = timer.frame
        let leadingIsUsable = hasUsableFrame(leadingFrame, in: screenFrame)
        let timerIsUsable = hasUsableFrame(timerFrame, in: screenFrame)

        XCTAssertTrue(leadingIsUsable, "Compact leading surface must have a usable frame")
        XCTAssertTrue(timerIsUsable, "Compact timer surface must have a usable frame")

        guard leadingIsUsable, timerIsUsable else {
            return
        }

        XCTAssertLessThanOrEqual(leadingFrame.maxX, timerFrame.minX)
    }

    private func assertLockScreenLayout(
        title: XCUIElement,
        timer: XCUIElement,
        screenFrame: CGRect
    ) {
        let titleFrame = title.frame
        let timerFrame = timer.frame
        let titleHasUsableFrame = hasUsableFrame(titleFrame, in: screenFrame)
        let timerHasUsableFrame = hasUsableFrame(timerFrame, in: screenFrame)
        XCTAssertTrue(
            titleHasUsableFrame,
            "Lock Screen title must publish a usable frame."
        )
        XCTAssertTrue(
            timerHasUsableFrame,
            "Lock Screen timer must publish a usable frame."
        )
        guard titleHasUsableFrame, timerHasUsableFrame else {
            return
        }

        assertHorizontalOrStackedTimerPlacement(
            titleFrame: titleFrame,
            timerFrame: timerFrame,
            surfaceName: "Lock Screen"
        )
    }

    private func assertExpandedLayout(
        title: XCUIElement,
        timer: XCUIElement,
        screenFrame: CGRect
    ) {
        let titleFrame = title.frame
        let timerFrame = timer.frame
        let titleHasUsableFrame = hasUsableFrame(titleFrame, in: screenFrame)
        let timerHasUsableFrame = hasUsableFrame(timerFrame, in: screenFrame)
        XCTAssertTrue(
            titleHasUsableFrame,
            "Expanded Dynamic Island title must publish a usable frame."
        )
        XCTAssertTrue(
            timerHasUsableFrame,
            "Expanded Dynamic Island timer must publish a usable frame."
        )
        guard titleHasUsableFrame, timerHasUsableFrame else {
            return
        }
        let hasVerticalOverlap = titleFrame.minY <= timerFrame.maxY
            && timerFrame.minY <= titleFrame.maxY
        XCTAssertTrue(
            hasVerticalOverlap,
            "Expanded Dynamic Island title and timer must remain in one row."
        )
        XCTAssertGreaterThanOrEqual(
            timerFrame.minX,
            titleFrame.maxX,
            "Expanded Dynamic Island title and timer must not overlap."
        )
    }

    private func assertHorizontalOrStackedTimerPlacement(
        titleFrame: CGRect,
        timerFrame: CGRect,
        surfaceName: String
    ) {
        let hasVerticalOverlap = titleFrame.minY <= timerFrame.maxY
            && timerFrame.minY <= titleFrame.maxY
        let isHorizontal = timerFrame.minX >= titleFrame.maxX && hasVerticalOverlap
        let isStacked = timerFrame.minY >= titleFrame.maxY

        XCTAssertTrue(
            isHorizontal || isStacked,
            "\(surfaceName) timer must sit beside or below the title without overlap."
        )
    }

    private func hasUsableFrame(_ frame: CGRect, in screenFrame: CGRect) -> Bool {
        !frame.isNull
            && !frame.isInfinite
            && !frame.isEmpty
            && frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.intersects(screenFrame)
    }

    #if os(iOS)
    @MainActor
    private func expandDynamicIslandTask(
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
            let expandedTitle = springboard.descendants(matching: .any)[
                "liveActivity.expanded.title"
            ].firstMatch
            if expandedTitle.waitForExistence(timeout: 4) {
                return true
            }
            XCUIDevice.shared.press(.home)
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        return false
    }
    #endif
}
