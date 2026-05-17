import XCTest

final class timetrackerClickableSurfaceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    @MainActor
    func testRootDestinationsAreClickable() throws {
        let app = launchApp()

        let destinations: [RootDestination] = [
            RootDestination(rawValue: "Today", title: "首页", readyIdentifier: "home.startTimer"),
            RootDestination(rawValue: "Inbox", title: "收件箱", readyIdentifier: "inbox.view"),
            RootDestination(rawValue: "Tasks", title: "任务", readyIdentifier: "tasks.view"),
            RootDestination(rawValue: "Pomodoro", title: "番茄钟", readyIdentifiers: ["pomodoro.choosePlan", "pomodoro.stopControl"]),
            RootDestination(rawValue: "Analytics", title: "分析", readyIdentifier: "analytics.homeSummary"),
            RootDestination(rawValue: "Settings", title: "设置", readyIdentifier: "settings.view")
        ]

        for destination in destinations {
            openRootDestination(destination, in: app)
            XCTAssertTrue(destinationIsReady(destination, in: app), "\(destination.rawValue) did not become ready.")
            assertAppStillRunning(app, after: destination.rawValue)
        }
    }

    @MainActor
    func testTaskRowsOpenDetailsWithoutCrashing() throws {
        let taskTargets: [(title: String, searchToken: String)] = [
            ("Time Tracker App", "Tracker"),
            ("Design System", "System"),
            ("Design macOS UI", "macOS"),
            ("Design iOS UI", "iOS"),
            ("Implementation", "Implementation"),
            ("SwiftData Ledger", "SwiftData"),
            ("Analytics Charts", "Analytics"),
            ("iCloud Sync", "iCloud"),
            ("Client Work", "Client"),
            ("Team Meeting", "Team"),
            ("Requirements Review", "Requirements"),
            ("Study", "Study"),
            ("Read Apple HIG", "HIG"),
            ("SwiftData Docs", "Docs")
        ]

        for target in taskTargets {
            let app = launchApp()
            openRootDestination(RootDestination(rawValue: "Tasks", title: "任务", readyIdentifier: "tasks.view"), in: app)
            _ = searchForTask(target.searchToken, in: app)

            let title = target.title
            let identifier = "tasks.task.\(title)"
            guard tapElement(identifier: identifier, in: app, scrollIfNeeded: true) else {
                XCTFail("Could not tap visible task row \(title).")
                return
            }

            XCTAssertTrue(taskDetailIsReady(in: app), "Task detail did not open for \(title).")
            assertAppStillRunning(app, after: "task row \(title)")
            app.terminate()
        }
    }

    @MainActor
    func testAnalyticsCategoriesOpenDetailsAndPeriodControlsWithoutCrashing() throws {
        let categories = ["overview", "time", "tasks", "pomodoro", "decisions", "quality"]
        for category in categories {
            let app = launchApp()
            openRootDestination(RootDestination(rawValue: "Analytics", title: "分析", readyIdentifier: "analytics.homeSummary"), in: app)

            let rowIdentifier = "analytics.category.\(category)"
            guard tapElement(identifier: rowIdentifier, in: app, scrollIfNeeded: true) else {
                XCTFail("Could not tap analytics category \(category).")
                return
            }

            XCTAssertTrue(waitForIdentifier("analytics.detail.\(category)", in: app), "Analytics detail did not open for \(category).")
            assertAppStillRunning(app, after: "analytics category \(category)")

            _ = tapElement(identifier: "analytics.periodControl", in: app, timeout: 1)
            assertAppStillRunning(app, after: "analytics period controls in \(category)")
            app.terminate()
        }
    }

    @MainActor
    func testTaskCreationEditingAndManualTimeSurfacesWithoutCrashing() throws {
        let app = launchApp()
        openRootDestination(RootDestination(rawValue: "Tasks", title: "任务", readyIdentifier: "tasks.view"), in: app)

        XCTAssertTrue(tapElement(identifier: "tasks.addMenu", in: app), "Could not open task add menu.")
        XCTAssertTrue(tapElement(identifier: "tasks.addRoot", in: app), "Could not open new task editor.")
        XCTAssertTrue(waitForIdentifier("task.editor.title", in: app), "New task editor did not expose the title field.")
        assertAppStillRunning(app, after: "opening new task editor")
        XCTAssertTrue(tapElement(identifier: "task.editor.cancel", in: app), "Could not cancel new task editor.")

        XCTAssertTrue(tapElement(identifier: "tasks.addMenu", in: app), "Could not reopen task add menu.")
        XCTAssertTrue(tapElement(identifier: "tasks.addCategory", in: app), "Could not open new category editor.")
        XCTAssertTrue(waitForIdentifier("taskCategory.editor.title", in: app), "New category editor did not expose the title field.")
        assertAppStillRunning(app, after: "opening new category editor")
        XCTAssertTrue(tapElement(identifier: "taskCategory.editor.cancel", in: app), "Could not cancel category editor.")

        _ = searchForTask("Tracker", in: app)
        XCTAssertTrue(tapElement(identifier: "tasks.task.Time Tracker App", in: app, scrollIfNeeded: true), "Could not open demo task detail.")
        XCTAssertTrue(taskDetailIsReady(in: app), "Task detail did not become ready.")

        XCTAssertTrue(tapElement(identifier: "task.detail.addTime", in: app), "Could not open manual time sheet from task detail.")
        XCTAssertTrue(waitForIdentifier("manualTime.cancel", in: app), "Manual time sheet did not expose the cancel button.")
        assertAppStillRunning(app, after: "opening task detail manual time")
        XCTAssertTrue(tapElement(identifier: "manualTime.cancel", in: app), "Could not cancel manual time sheet.")

        XCTAssertTrue(tapElement(identifier: "task.detail.header.edit", in: app), "Could not expand task detail editor from the header.")
        assertAppStillRunning(app, after: "task detail edit controls")
    }

    @MainActor
    func testInboxCaptureSuggestionActionsAndMenuWithoutCrashing() throws {
        let app = launchApp(stressProfile: "custom", stressOverrides: compactClickableStressOverrides)
        openRootDestination(RootDestination(rawValue: "Inbox", title: "收件箱", readyIdentifier: "inbox.view"), in: app)

        let captureTitle = "UICaptureFlow"
        XCTAssertTrue(tapElement(identifier: "inbox.add", in: app), "Could not focus inbox capture.")
        XCTAssertTrue(typeText(captureTitle, into: "inbox.capture.title", in: app), "Could not type into inbox capture.")
        submitFocusedTextEntry(in: app)
        XCTAssertTrue(tapElement(identifier: "inbox.capture.add", in: app), "Could not submit inbox capture.")
        XCTAssertTrue(waitForIdentifier("inbox.item.\(captureTitle)", in: app, scrollIfNeeded: true), "Created inbox item did not appear.")
        assertAppStillRunning(app, after: "inbox capture")

        XCTAssertTrue(tapAnyElement(identifiers: ["inbox.suggestion.discard", "Discard Suggestion", "丢弃建议", "丟棄推薦"], in: app, timeout: 2), "Could not discard an inbox suggestion.")
        assertAppStillRunning(app, after: "discarding inbox suggestion")
        XCTAssertTrue(tapAnyElement(identifiers: ["inbox.suggestion.apply", "Add to Task", "添加到任务", "加入任務"], in: app, timeout: 2), "Could not apply an inbox suggestion.")
        assertAppStillRunning(app, after: "applying inbox suggestion")
    }

    @MainActor
    func testPomodoroTaskPlanStartAndStopControlsWithoutCrashing() throws {
        let app = launchApp(stressProfile: "compact")
        openRootDestination(RootDestination(rawValue: "Pomodoro", title: "番茄钟", readyIdentifiers: ["pomodoro.choosePlan", "pomodoro.stopControl"]), in: app)

        XCTAssertTrue(tapElement(identifier: "pomodoro.choosePlan", in: app), "Could not open Pomodoro plan chooser.")
        XCTAssertTrue(tapElement(identifier: "pomodoro.plan.0", in: app, scrollIfNeeded: true), "Could not choose the default Pomodoro plan.")
        assertAppStillRunning(app, after: "choosing Pomodoro plan")

        XCTAssertTrue(tapElement(identifier: "pomodoro.chooseTask", in: app), "Could not open Pomodoro task chooser.")
        XCTAssertTrue(tapElement(identifier: "pomodoro.task.Stress Root 1", in: app, scrollIfNeeded: true), "Could not choose a Pomodoro task.")
        dismissTransientSurface(in: app)
        assertAppStillRunning(app, after: "choosing Pomodoro task")

        XCTAssertTrue(tapElement(identifier: "pomodoro.startFocus", in: app), "Could not start Pomodoro focus.")
        XCTAssertTrue(waitForIdentifier("pomodoro.stopControl", in: app), "Active Pomodoro stop control did not appear.")
        if let stopControl = hittableElement(identifier: "pomodoro.stopControl", in: app, timeout: 3) {
            stopControl.press(forDuration: 1.1)
            XCTAssertTrue(waitForIdentifier("pomodoro.startFocus", in: app), "Pomodoro setup did not return after stop hold.")
        } else {
            XCTFail("Could not find Pomodoro stop control.")
        }
        assertAppStillRunning(app, after: "Pomodoro start and stop")
    }

    @MainActor
    func testSettingsControlsCountdownManualTimeAndConfirmationsWithoutCrashing() throws {
        var settingsStressOverrides = compactClickableStressOverrides
        settingsStressOverrides["TimeTrackerStressCountdownEventCount"] = "0"
        let app = launchApp(stressProfile: "custom", stressOverrides: settingsStressOverrides)
        openRootDestination(RootDestination(rawValue: "Settings", title: "设置", readyIdentifier: "settings.view"), in: app)

        for identifier in ["settings.allowParallelTimers", "settings.showWallGross"] {
            XCTAssertTrue(tapElement(identifier: identifier, in: app, scrollIfNeeded: true), "Could not tap \(identifier).")
            XCTAssertTrue(tapElement(identifier: identifier, in: app, scrollIfNeeded: true), "Could not restore \(identifier).")
            assertAppStillRunning(app, after: "settings toggle \(identifier)")
        }

        XCTAssertTrue(waitForIdentifier("settings.icloud.toggle", in: app), "iCloud toggle did not appear in Settings.")
        if let iCloudToggle = hittableElement(identifier: "settings.icloud.toggle", in: app, timeout: 1) {
            iCloudToggle.tap()
            assertAppStillRunning(app, after: "settings iCloud toggle")
            iCloudToggle.tap()
        }

        XCTAssertTrue(tapElement(identifier: "settings.addTime", in: app, scrollIfNeeded: true), "Could not open manual time from Settings.")
        XCTAssertTrue(waitForIdentifier("manualTime.cancel", in: app), "Manual time sheet did not expose the cancel button from Settings.")
        XCTAssertTrue(tapElement(identifier: "manualTime.cancel", in: app), "Could not cancel Settings manual time sheet.")

        XCTAssertTrue(tapElement(identifier: "settings.countdown.add", in: app, scrollIfNeeded: true), "Could not add countdown event.")
        XCTAssertTrue(waitForIdentifier("settings.countdown.date", in: app), "Countdown date picker did not appear.")
        XCTAssertTrue(tapElement(identifier: "settings.countdown.delete", in: app, scrollIfNeeded: true), "Could not delete countdown event.")
        assertAppStillRunning(app, after: "countdown settings controls")

        let confirmationButtons = [
            "settings.optimizeDatabase",
            "settings.forceUpload",
            "settings.forceDownload",
            "settings.rebuildDemoData",
            "settings.clearDemoData",
            "settings.resetData"
        ]
        for identifier in confirmationButtons {
            XCTAssertTrue(tapElement(identifier: identifier, in: app, scrollIfNeeded: true), "Could not open confirmation for \(identifier).")
            XCTAssertTrue(tapCancelButton(in: app), "Could not cancel confirmation for \(identifier).")
            assertAppStillRunning(app, after: "canceling confirmation \(identifier)")
        }
    }

    @MainActor
    private func launchApp(stressProfile: String? = nil, stressOverrides: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "-ApplePersistenceIgnoreState", "YES",
            "-TimeTrackerAutomaticDemoDataModeOverride", "replaceOnLaunch",
            "-TimeTrackerStressDataProfile", stressProfile ?? "off"
        ]
        for key in stressOverrides.keys.sorted() {
            app.launchArguments.append(contentsOf: ["-\(key)", stressOverrides[key] ?? ""])
        }
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"
        app.launch()
        app.activate()
        return app
    }

    @MainActor
    private func openRootDestination(_ destination: RootDestination, in app: XCUIApplication) {
        if destinationIsReady(destination, in: app, timeout: 0.5) {
            return
        }

        if tapElement(identifier: "sidebar.\(destination.rawValue)", in: app, timeout: 1),
           destinationIsReady(destination, in: app, timeout: 3) {
            return
        }

        if tapPhoneDestination(destination.rawValue, in: app),
           destinationIsReady(destination, in: app, timeout: 3) {
            return
        }

        if tapElement(identifier: destination.title, in: app, timeout: 1),
           destinationIsReady(destination, in: app, timeout: 3) {
            return
        }

        if destination.rawValue == "Settings",
           tapElement(identifier: "settings.open", in: app, timeout: 1),
           destinationIsReady(destination, in: app, timeout: 3) {
            return
        }

        XCTFail("Could not open \(destination.rawValue).")
    }

    @MainActor
    private func tapPhoneDestination(_ rawValue: String, in app: XCUIApplication) -> Bool {
        let identifier = "phone.bottom.\(rawValue)"
        if tapElement(identifier: identifier, in: app, timeout: 1) {
            return true
        }

        let bottomBar = app.descendants(matching: .any)["phone.bottomBar"].firstMatch
        guard bottomBar.waitForExistence(timeout: 1) else {
            return false
        }

        for _ in 0..<2 {
            bottomBar.swipeLeft()
            if tapElement(identifier: identifier, in: app, timeout: 1) {
                return true
            }
        }

        for _ in 0..<2 {
            bottomBar.swipeRight()
            if tapElement(identifier: identifier, in: app, timeout: 1) {
                return true
            }
        }

        return false
    }

    @MainActor
    private func tapElement(
        identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 3,
        scrollIfNeeded: Bool = false
    ) -> Bool {
        if let element = hittableElement(identifier: identifier, in: app, timeout: timeout) {
            element.tap()
            return true
        }

        guard scrollIfNeeded else { return false }

        #if os(macOS)
        if let element = scrollableTapElement(identifier: identifier, in: app) {
            element.tap()
            return true
        }
        #endif

        for _ in 0..<8 {
            guard scrollContent(in: app, direction: .up) else { return false }
            if let element = hittableElement(identifier: identifier, in: app, timeout: 0.25) {
                element.tap()
                return true
            }
        }

        for _ in 0..<8 {
            guard scrollContent(in: app, direction: .down) else { return false }
            if let element = hittableElement(identifier: identifier, in: app, timeout: 0.25) {
                element.tap()
                return true
            }
        }

        return false
    }

    @MainActor
    private func hittableElement(identifier: String, in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let preferredQueries = [
            app.buttons[identifier].firstMatch,
            app.textFields[identifier].firstMatch,
            app.secureTextFields[identifier].firstMatch,
            app.switches[identifier].firstMatch,
            app.checkBoxes[identifier].firstMatch,
            app.datePickers[identifier].firstMatch,
            app.cells[identifier].firstMatch,
            app.otherElements[identifier].firstMatch,
            app.staticTexts[identifier].firstMatch
        ]

        let matches = app.descendants(matching: .any).matching(identifier: identifier)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for element in preferredQueries {
                if element.exists, element.isHittable, element.elementType != .progressIndicator {
                    return element
                }
            }

            let count = min(matches.count, 32)
            for index in 0..<count {
                let element = matches.element(boundBy: index)
                if element.exists, element.isHittable {
                    return element
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return nil
    }

    @MainActor
    private func scrollableTapElement(identifier: String, in app: XCUIApplication) -> XCUIElement? {
        let preferredQueries = [
            app.buttons[identifier].firstMatch,
            app.cells[identifier].firstMatch
        ]

        for element in preferredQueries where element.exists {
            return element
        }

        return nil
    }

    @MainActor
    private func typeText(_ text: String, into identifier: String, in app: XCUIApplication) -> Bool {
        if let textInput = hittableTextInput(identifier: identifier, in: app, timeout: 3) {
            textInput.tap()
            textInput.typeText(text)
            return true
        }

        guard let fallback = hittableElement(identifier: identifier, in: app, timeout: 3) else { return false }
        fallback.tap()
        app.typeText(text)
        return true
    }

    @MainActor
    private func hittableTextInput(identifier: String, in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let preferredQueries = [
            app.textFields[identifier].firstMatch,
            app.searchFields[identifier].firstMatch,
            app.secureTextFields[identifier].firstMatch
        ]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for element in preferredQueries where element.exists && element.isHittable {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return nil
    }

    @MainActor
    private func tapCancelButton(in app: XCUIApplication) -> Bool {
        for label in ["Cancel", "取消", "取消"] where tapElement(identifier: label, in: app, timeout: 2) {
            return true
        }
        return false
    }

    @MainActor
    private func tapAnyElement(identifiers: [String], in app: XCUIApplication, timeout: TimeInterval = 2) -> Bool {
        for identifier in identifiers where tapElement(identifier: identifier, in: app, timeout: timeout) {
            return true
        }
        return false
    }

    @MainActor
    private func dismissTransientSurface(in app: XCUIApplication) {
        #if os(macOS)
        app.typeKey(.escape, modifierFlags: [])
        #else
        app.tap()
        #endif
    }

    @MainActor
    private func submitFocusedTextEntry(in app: XCUIApplication) {
        #if os(macOS)
        app.typeKey(.return, modifierFlags: [])
        #else
        app.keyboards.buttons["Return"].tap()
        #endif
    }

    @MainActor
    private func searchForTask(_ title: String, in app: XCUIApplication) -> Bool {
        if let searchField = hittableSearchField(in: app) {
            searchField.tap()
            searchField.typeText(title)
            commitSearchText(in: app)
            return true
        }

        #if os(macOS)
        app.typeKey("f", modifierFlags: .command)
        if let searchField = hittableSearchField(in: app) {
            searchField.tap()
            searchField.typeText(title)
            commitSearchText(in: app)
            return true
        }
        #endif

        return false
    }

    @MainActor
    private func hittableSearchField(in app: XCUIApplication) -> XCUIElement? {
        let searchFields = app.searchFields
        let deadline = Date().addingTimeInterval(1)
        repeat {
            let count = min(searchFields.count, 8)
            for index in 0..<count {
                let field = searchFields.element(boundBy: index)
                if field.exists, field.isHittable {
                    return field
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return nil
    }

    @MainActor
    private func commitSearchText(in app: XCUIApplication) {
        #if os(macOS)
        app.typeKey(.return, modifierFlags: [])
        #endif
    }

    @MainActor
    private func scrollContent(in app: XCUIApplication, direction: ScrollDirection) -> Bool {
        let containers = [
            app.descendants(matching: .any)["inbox.view"].firstMatch,
            app.descendants(matching: .any)["settings.view"].firstMatch,
            app.descendants(matching: .any)["tasks.view"].firstMatch,
            app.descendants(matching: .any)["analytics.homeSummary"].firstMatch,
            app.scrollViews.firstMatch,
            app.collectionViews.firstMatch,
            app.tables.firstMatch,
            app.windows.firstMatch
        ]

        for container in containers where container.exists && container.isHittable {
            #if os(macOS)
            switch direction {
            case .up:
                container.scroll(byDeltaX: 0, deltaY: 650)
            case .down:
                container.scroll(byDeltaX: 0, deltaY: -650)
            }
            #else
            switch direction {
            case .up:
                container.swipeUp()
            case .down:
                container.swipeDown()
            }
            #endif
            return true
        }

        return false
    }

    @MainActor
    private func waitForIdentifier(
        _ identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 5,
        scrollIfNeeded: Bool = false
    ) -> Bool {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        if element.waitForExistence(timeout: timeout) {
            return true
        }

        guard scrollIfNeeded else { return false }

        for direction in [ScrollDirection.up, .down] {
            for _ in 0..<8 {
                guard scrollContent(in: app, direction: direction) else { break }
                if element.waitForExistence(timeout: 0.25) {
                    return true
                }
            }
        }

        return false
    }

    @MainActor
    private func destinationIsReady(_ destination: RootDestination, in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        destination.readyIdentifiers.contains { waitForIdentifier($0, in: app, timeout: timeout) }
    }

    @MainActor
    private func taskDetailIsReady(in app: XCUIApplication) -> Bool {
        app.buttons["task.detail.addTime"].waitForExistence(timeout: 4) ||
        app.buttons["补录时间"].waitForExistence(timeout: 1) ||
        app.buttons["添加时间"].waitForExistence(timeout: 1) ||
        app.buttons["Add Time"].waitForExistence(timeout: 1)
    }

    @MainActor
    private func assertAppStillRunning(_ app: XCUIApplication, after action: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(app.state, .notRunning, "App stopped running after \(action).", file: file, line: line)
    }

    private var compactClickableStressOverrides: [String: String] {
        [
            "TimeTrackerStressCategoryCount": "2",
            "TimeTrackerStressChecklistItemsPerTask": "0",
            "TimeTrackerStressChildrenPerNode": "0",
            "TimeTrackerStressCountdownEventCount": "4",
            "TimeTrackerStressInboxItemCount": "4",
            "TimeTrackerStressMaxDepth": "1",
            "TimeTrackerStressRootCount": "2",
            "TimeTrackerStressSegmentsPerTask": "0"
        ]
    }
}

private struct RootDestination {
    let rawValue: String
    let title: String
    let readyIdentifiers: [String]

    init(rawValue: String, title: String, readyIdentifier: String) {
        self.rawValue = rawValue
        self.title = title
        readyIdentifiers = [readyIdentifier]
    }

    init(rawValue: String, title: String, readyIdentifiers: [String]) {
        self.rawValue = rawValue
        self.title = title
        self.readyIdentifiers = readyIdentifiers
    }
}

private enum ScrollDirection {
    case up
    case down
}
