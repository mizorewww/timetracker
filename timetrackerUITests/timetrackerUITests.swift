import XCTest

final class timetrackerUITests: XCTestCase {
    private enum ScrollDirection {
        case up
        case down
    }

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

        openSection("Analytics", tabIdentifier: "phone.tab.analytics", sidebarIdentifier: "sidebar.Analytics", in: app)
        XCTAssertTrue(analyticsIsReady(in: app))

        openSettings(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["settings.view"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSettingsCategoryNavigationRemainsReachableAtLargeTextSizes() throws {
        let app = launchApp()
        XCTAssertTrue(homeIsReady(in: app))
        openSettings(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["settings.view"].waitForExistence(timeout: 8))

        let general = app.buttons["settings.category.general"].firstMatch
        let focus = app.buttons["settings.category.focus"].firstMatch
        XCTAssertTrue(general.waitForExistence(timeout: 3) && general.isHittable)
        XCTAssertTrue(focus.waitForExistence(timeout: 3) && focus.isHittable)
        try capture("iphone-settings-category-navigation", app: app)

        activate(general)
        XCTAssertTrue(app.navigationBars["General"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testTaskListKeepsSearchAndFirstTaskReachableAtLargeTextSizes() throws {
        let app = launchApp()
        openSection(
            "Tasks",
            tabIdentifier: "phone.tab.tasks",
            sidebarIdentifier: "sidebar.Tasks",
            in: app
        )

        let searchField = app.descendants(matching: .any)["tasks.search.field"].firstMatch
        let firstTask = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "tasks.row."))
            .firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8) && searchField.isHittable)
        XCTAssertTrue(firstTask.waitForExistence(timeout: 8) && firstTask.isHittable)
        try capture("iphone-tasks-accessibility-list", app: app)

        activate(firstTask)
        XCTAssertTrue(taskDetailIsReady(in: app))
    }

    @MainActor
    func testInboxCaptureAffordanceFocusesThenAddsAValidDraft() throws {
        let app = launchApp()
        openSection(
            "Inbox",
            tabIdentifier: "phone.tab.inbox",
            sidebarIdentifier: "sidebar.Inbox",
            in: app
        )
        XCTAssertTrue(app.descendants(matching: .any)["inbox.view"].waitForExistence(timeout: 8))

        let addButton = app.buttons["inbox.capture.add"].firstMatch
        let field = app.descendants(matching: .any)["inbox.capture.field"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 3) && addButton.isHittable)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        try capture("iphone-inbox-simplified-empty", app: app)

        activate(addButton)
        let draftTitle = "Review capture flow"
        field.typeText(draftTitle)
        let valueExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", draftTitle),
            object: field
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [valueExpectation], timeout: 3),
            .completed
        )

        activate(addButton)
        let newItem = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "inbox.item."))
            .firstMatch
        XCTAssertTrue(
            waitForElement(
                newItem,
                timeout: 5,
                diagnosticName: "inbox-captured-item",
                in: app
            )
        )
    }

    @MainActor
    func testTaskEditorAndPomodoroFlowOpen() throws {
        let app = launchApp()

        XCTAssertTrue(homeIsReady(in: app))
        openSection("Tasks", tabIdentifier: "phone.tab.tasks", sidebarIdentifier: "sidebar.Tasks", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["tasks.view"].waitForExistence(timeout: 5))
        let addTaskMenu = app.descendants(matching: .any)["tasks.add"].firstMatch
        XCTAssertTrue(addTaskMenu.waitForExistence(timeout: 3) && addTaskMenu.isHittable)
        activate(addTaskMenu)
        let addRootTask = app.descendants(matching: .any)["tasks.addRoot"].firstMatch
        XCTAssertTrue(addRootTask.waitForExistence(timeout: 3) && addRootTask.isHittable)
        activate(addRootTask)
        XCTAssertTrue(
            waitForElement(
                app.descendants(matching: .any)["task.editor"],
                timeout: 5,
                diagnosticName: "task-editor-open",
                in: app
            )
        )
        closePresentedEditor(in: app)

        openSection("Focus", tabIdentifier: "phone.tab.focus", sidebarIdentifier: "sidebar.Pomodoro", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["pomodoro.view"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testFocusAdaptiveScreenshots() throws {
        #if os(macOS)
        throw XCTSkip("Focus adaptive screenshots require an iOS simulator.")
        #else
        let app = launchApp(route: "focus")

        XCTAssertTrue(app.descendants(matching: .any)["pomodoro.view"].waitForExistence(timeout: 8))
        try capture("iphone-focus-initial", app: app)

        let startFocus = app.buttons["pomodoro.startFocus"].firstMatch
        XCTAssertTrue(startFocus.waitForExistence(timeout: 5))
        scrollUntilFullyVisibleAboveSystemChrome(startFocus, in: app)
        XCTAssertTrue(
            isFullyVisibleAboveSystemChrome(startFocus, in: app),
            "Start Focus must be completely visible above the floating tab bar."
        )
        try capture("iphone-focus-primary-action", app: app)
        #endif
    }

    @MainActor
    func testUIRefactorBaselineScreenshots() throws {
        let app = launchApp()

        XCTAssertTrue(homeIsReady(in: app))
        try capture("iphone-home-baseline", app: app)

        openSection("Inbox", tabIdentifier: "phone.tab.inbox", sidebarIdentifier: "sidebar.Inbox", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["inbox.view"].waitForExistence(timeout: 8))
        try capture("iphone-inbox-baseline", app: app)

        openSection("Tasks", tabIdentifier: "phone.tab.tasks", sidebarIdentifier: "sidebar.Tasks", in: app)
        let firstTaskRow = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "tasks.row."))
            .firstMatch
        XCTAssertTrue(
            waitForElement(
                firstTaskRow,
                timeout: 8,
                diagnosticName: "tasks-first-row",
                in: app
            )
        )
        try capture("iphone-tasks-baseline", app: app)

        activate(firstTaskRow)
        XCTAssertTrue(taskDetailIsReady(in: app))
        try capture("iphone-task-detail-baseline", app: app)

        openSection("Focus", tabIdentifier: "phone.tab.focus", sidebarIdentifier: "sidebar.Pomodoro", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["pomodoro.view"].waitForExistence(timeout: 8))
        try capture("iphone-focus-baseline", app: app)

        openSection("Analytics", tabIdentifier: "phone.tab.analytics", sidebarIdentifier: "sidebar.Analytics", in: app)
        XCTAssertTrue(analyticsIsReady(in: app))
        try capture("iphone-analytics-baseline", app: app)

        openSettings(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["settings.view"].waitForExistence(timeout: 8))
        try capture("iphone-settings-baseline", app: app)
    }

    @MainActor
    func testTodayPrimaryTimerActionOpensTaskPicker() throws {
        #if os(macOS)
        throw XCTSkip("The Today interaction screenshots require an iOS simulator.")
        #else
        let app = launchApp()
        XCTAssertTrue(homeIsReady(in: app))
        try exerciseTodayTimerPicker(
            in: app,
            overviewCaptureName: "today-overview",
            pickerCaptureName: "today-task-picker"
        )
        #endif
    }

    @MainActor
    func testTodayLandscapeLayoutOpensTaskPicker() throws {
        #if os(macOS)
        throw XCTSkip("The Today landscape interaction screenshot requires an iOS simulator.")
        #else
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchApp()
        XCTAssertTrue(homeIsReady(in: app))
        try exerciseTodayTimerPicker(
            in: app,
            overviewCaptureName: "ipad-today-landscape-overview",
            pickerCaptureName: "ipad-today-landscape-task-picker"
        )
        #endif
    }

    @MainActor
    private func exerciseTodayTimerPicker(
        in app: XCUIApplication,
        overviewCaptureName: String,
        pickerCaptureName: String
    ) throws {
        let startTimer = app.buttons["home.startTimer"].firstMatch
        scrollUntilHittable(startTimer, direction: .up, in: app)
        XCTAssertTrue(
            waitForElement(startTimer, timeout: 5, diagnosticName: "today-start-timer", in: app)
                && startTimer.isHittable
        )
        try capture(overviewCaptureName, app: app)

        activate(startTimer)
        let picker = app.descendants(matching: .any)["timer.taskPicker"].firstMatch
        XCTAssertTrue(waitForElement(picker, timeout: 5, diagnosticName: "today-task-picker", in: app))
        try capture(pickerCaptureName, app: app)
    }

    @MainActor
    func testCountdownTitleDraftShowsInlineValidation() throws {
        #if os(macOS)
        throw XCTSkip("The countdown draft interaction screenshot is iPhone-specific.")
        #else
        let app = launchApp()
        XCTAssertTrue(homeIsReady(in: app))
        openSettings(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["settings.view"].waitForExistence(timeout: 8))

        let generalCategory = app.buttons["settings.category.general"].firstMatch
        XCTAssertTrue(waitForElement(generalCategory, timeout: 3, diagnosticName: "settings-general", in: app))
        activate(generalCategory)

        let addEvent = app.buttons["Add Event"].firstMatch
        scrollUntilHittable(addEvent, direction: .up, in: app)
        XCTAssertTrue(
            waitForElement(addEvent, timeout: 5, diagnosticName: "countdown-add", in: app) && addEvent.isHittable
        )
        activate(addEvent)

        let titleField = app.descendants(matching: .any)["settings.countdown.title.field"].firstMatch
        scrollUntilHittable(titleField, direction: .down, in: app)
        XCTAssertTrue(
            waitForElement(titleField, timeout: 5, diagnosticName: "countdown-title", in: app) && titleField.isHittable
        )
        titleField.tap()
        titleField.typeText(" Draft")

        let saveTitle = app.buttons["settings.countdown.title.save"].firstMatch
        XCTAssertTrue(waitForElement(saveTitle, timeout: 3, diagnosticName: "countdown-save", in: app))
        try capture("iphone-countdown-title-draft", app: app)

        let currentTitle = (titleField.value as? String) ?? "New Event Draft"
        titleField.typeText(
            String(
                repeating: XCUIKeyboardKey.delete.rawValue,
                count: max(currentTitle.count + 16, 32)
            )
        )
        activate(saveTitle)

        let inlineError = app.descendants(matching: .any)["settings.countdown.title.error"].firstMatch
        XCTAssertTrue(waitForElement(inlineError, timeout: 3, diagnosticName: "countdown-title-error", in: app))
        XCTAssertTrue(titleField.exists)
        let scrollStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.55))
        let scrollEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.48))
        scrollStart.press(forDuration: 0.1, thenDragTo: scrollEnd)
        try capture("iphone-countdown-title-validation", app: app)

        titleField.tap()
        titleField.typeText("Release")
        activate(saveTitle)
        XCTAssertFalse(inlineError.waitForExistence(timeout: 1))
        try capture("iphone-countdown-title-saved", app: app)
        #endif
    }

    @MainActor
    func testSidebarTaskOpensTaskDetailWhenSidebarIsVisible() throws {
        let app = launchApp()

        XCTAssertTrue(homeIsReady(in: app))
        let revealSidebar = app.descendants(matching: .any)["sidebar.show"].firstMatch
        if revealSidebar.waitForExistence(timeout: 1), revealSidebar.isHittable {
            activate(revealSidebar)
        }

        let sidebarTask = app.staticTexts
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sidebar.task."))
            .firstMatch
        guard sidebarTask.waitForExistence(timeout: 3) else {
            throw XCTSkip("Sidebar is not visible in this size class.")
        }

        activate(sidebarTask)

        XCTAssertTrue(taskDetailIsReady(in: app))
        XCTAssertFalse(app.descendants(matching: .any)["task.editor"].waitForExistence(timeout: 1))
        try capture("ipad-sidebar-task-detail-fix", app: app)
    }

    @MainActor
    private func launchApp(route: String = "today") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-TimeTrackerAutomaticDemoDataModeOverride", "seedIfEmpty",
            "-TimeTrackerAutomaticDemoSeedingDisabled", "NO"
        ]
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"
        app.launchEnvironment["TIMETRACKER_UI_AUDIT_ROUTE"] = route
        app.launch()
        app.activate()
        return app
    }

    @MainActor
    private func homeIsReady(in app: XCUIApplication) -> Bool {
        if app.descendants(matching: .any)["home.view"].waitForExistence(timeout: 8) {
            return true
        }
        return app.buttons["home.startTimer"].waitForExistence(timeout: 2)
    }

    @MainActor
    private func analyticsIsReady(in app: XCUIApplication) -> Bool {
        guard app.descendants(matching: .any)["analytics.view"].waitForExistence(timeout: 8),
              app.descendants(matching: .any)["analytics.periodFilter"]
                .waitForExistence(timeout: 8) else {
            return false
        }
        return app.descendants(matching: .any)["analytics.summary"]
            .firstMatch
            .waitForExistence(timeout: 8)
    }

    @MainActor
    private func taskDetailIsReady(in app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)["task.detail"].waitForExistence(timeout: 5)
    }

    @MainActor
    private func openSection(
        _ tabTitle: String,
        tabIdentifier: String,
        sidebarIdentifier: String,
        in app: XCUIApplication
    ) {
        #if os(macOS)
        let sidebarRow = app.outlines
            .descendants(matching: .cell)
            .containing(.staticText, identifier: sidebarIdentifier)
            .firstMatch
        if sidebarRow.waitForExistence(timeout: 1), sidebarRow.isHittable {
            sidebarRow.click()
            return
        }
        #endif

        let identifiedElement = app.descendants(matching: .any)[sidebarIdentifier]
        if identifiedElement.waitForExistence(timeout: 1) {
            activate(identifiedElement.firstMatch)
            return
        }

        let identifiedTab = app.descendants(matching: .any)[tabIdentifier]
        if identifiedTab.waitForExistence(timeout: 2) {
            activate(identifiedTab.firstMatch)
            return
        }

        if app.tabBars.buttons[tabTitle].waitForExistence(timeout: 3) {
            activate(app.tabBars.buttons[tabTitle])
            return
        }

        if app.buttons[tabTitle].waitForExistence(timeout: 1) {
            activate(app.buttons[tabTitle].firstMatch)
            return
        }

        if app.staticTexts[tabTitle].waitForExistence(timeout: 1) {
            activate(app.staticTexts[tabTitle].firstMatch)
            return
        }

        XCTFail("Could not open section \(tabTitle)")
    }

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        let settingsButton = app.descendants(matching: .any)["settings.open"]
        if settingsButton.waitForExistence(timeout: 1), settingsButton.firstMatch.isHittable {
            activate(settingsButton.firstMatch)
            return
        }

        let sidebarSettings = app.descendants(matching: .any)["sidebar.Settings"]
        if sidebarSettings.waitForExistence(timeout: 1), sidebarSettings.firstMatch.isHittable {
            activate(sidebarSettings.firstMatch)
            return
        }

        #if os(macOS)
        let appMenu = app.menuBars.menuBarItems["Time Tracker"]
        if appMenu.waitForExistence(timeout: 1) {
            appMenu.click()
            let settingsMenuItem = app.menuItems["Settings…"]
            if settingsMenuItem.waitForExistence(timeout: 1) {
                settingsMenuItem.click()
                if app.descendants(matching: .any)["settings.view"].waitForExistence(timeout: 3) {
                    return
                }
            }
        }

        XCTFail("Could not open Settings from the macOS app menu")
        return
        #else
        openSection("Today", tabIdentifier: "phone.tab.today", sidebarIdentifier: "sidebar.Today", in: app)
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        activate(settingsButton.firstMatch)
        #endif
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) throws {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = ProcessInfo.processInfo.environment["UI_SCREENSHOT_DIR"], !directory.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try screenshot.pngRepresentation.write(to: url.appendingPathComponent("\(name).png"))
    }

    @MainActor
    private func closePresentedEditor(in app: XCUIApplication) {
        let identifiedCancel = app.buttons["task.editor.cancel"].firstMatch
        if identifiedCancel.waitForExistence(timeout: 2), identifiedCancel.isHittable {
            activate(identifiedCancel)
            return
        }

        let cancel = app.buttons["取消"].exists ? app.buttons["取消"].firstMatch : app.buttons["Cancel"].firstMatch
        if cancel.exists, cancel.isHittable {
            activate(cancel)
            return
        }

        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    private func activate(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    @MainActor
    private func scrollUntilHittable(
        _ element: XCUIElement,
        direction: ScrollDirection,
        in app: XCUIApplication
    ) {
        for _ in 0..<6 where !element.isHittable {
            switch direction {
            case .up:
                app.swipeUp()
            case .down:
                app.swipeDown()
            }
        }
    }

    @MainActor
    private func scrollUntilFullyVisibleAboveSystemChrome(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) {
        for _ in 0..<12 where !isFullyVisibleAboveSystemChrome(element, in: app) {
            let unobscuredBottom = systemChromeTop(in: app)
            let frame = element.frame

            if element.exists,
               frame.minY < unobscuredBottom,
               frame.maxY > unobscuredBottom - 8 {
                dragContentUp(
                    by: frame.maxY - unobscuredBottom + 20,
                    in: app
                )
            } else {
                app.swipeUp()
            }
        }
    }

    @MainActor
    private func isFullyVisibleAboveSystemChrome(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        guard element.exists, element.isHittable else { return false }

        let unobscuredBottom = systemChromeTop(in: app)
        return element.frame.minY >= app.frame.minY
            && element.frame.maxY <= unobscuredBottom - 8
    }

    @MainActor
    private func systemChromeTop(in app: XCUIApplication) -> CGFloat {
        let tabBar = app.tabBars.firstMatch
        return tabBar.exists ? tabBar.frame.minY : app.frame.maxY
    }

    @MainActor
    private func dragContentUp(by distance: CGFloat, in app: XCUIApplication) {
        let normalizedDistance = min(max(distance / app.frame.height, 0.06), 0.25)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let end = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72 - normalizedDistance)
        )
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func anyStaticText(_ labels: [String], in app: XCUIApplication) -> Bool {
        labels.contains { app.staticTexts[$0].waitForExistence(timeout: 1) }
    }

    @MainActor
    private func waitForElement(
        _ element: XCUIElement,
        timeout: TimeInterval,
        diagnosticName: String,
        in app: XCUIApplication
    ) -> Bool {
        guard !element.waitForExistence(timeout: timeout) else { return true }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Failure - \(diagnosticName)"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Accessibility - \(diagnosticName)"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        return false
    }
}
