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
    func testPhoneSettingsSheetDismissesToAnUnmodifiedTodayStack() throws {
        #if os(macOS)
        throw XCTSkip("The phone Settings sheet requires an iOS simulator.")
        #else
        let app = launchApp(route: "settings")
        let settings = app.descendants(matching: .any)["settings.view"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        try capture("iphone-settings-scene-sheet", app: app)

        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 3) && done.isHittable)
        activate(done)

        XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
        XCTAssertTrue(homeIsReady(in: app))
        XCTAssertFalse(app.buttons["Back"].exists)
        try capture("iphone-settings-dismissed-today", app: app)
        #endif
    }

    @MainActor
    func testRunningTimeRecordEditorStagesAnExplicitCurrentEnd() throws {
        #if os(macOS)
        throw XCTSkip("The compact time-record editor requires an iOS simulator.")
        #else
        let app = launchApp()
        let more = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "timeline.more.timer."
            ))
            .element(boundBy: 0)
        scrollUntilHittable(more, direction: .up, in: app)
        XCTAssertTrue(more.waitForExistence(timeout: 5) && more.isHittable)
        activate(more)

        let edit = app.buttons["Edit Time Record"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 3) && edit.isHittable)
        activate(edit)

        let editor = app.descendants(matching: .any)["segmentEditor.view"]
        let endNow = app.buttons["segmentEditor.endNow"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(endNow.waitForExistence(timeout: 3) && endNow.isHittable)
        XCTAssertFalse(app.switches["In Progress"].exists)
        try capture("iphone-time-record-running", app: app)

        activate(endNow)
        let keepRunning = app.buttons["segmentEditor.keepRunning"]
        XCTAssertTrue(
            keepRunning.waitForExistence(timeout: 3) && keepRunning.isHittable
        )
        try capture("iphone-time-record-ended-at-current-time", app: app)

        activate(app.buttons["Cancel"].firstMatch)
        let discard = app.buttons["Discard Changes"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 3) && discard.isHittable)
        activate(discard)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        #endif
    }

    @MainActor
    func testActiveFocusDeletionExplainsWholeSessionImpact() throws {
        #if os(macOS)
        throw XCTSkip("The compact time-record confirmation requires an iOS simulator.")
        #else
        let app = launchApp(route: "focus")
        let startFocus = app.buttons["pomodoro.startFocus"].firstMatch
        XCTAssertTrue(startFocus.waitForExistence(timeout: 8) && startFocus.isHittable)
        activate(startFocus)
        XCTAssertTrue(
            app.descendants(matching: .any)["pomodoro.active"]
                .waitForExistence(timeout: 5)
        )

        openSection(
            "Today",
            tabIdentifier: "phone.tab.today",
            sidebarIdentifier: "sidebar.Today",
            in: app
        )
        let more = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "timeline.more.pomodoro."
            ))
            .firstMatch
        scrollUntilHittable(more, direction: .up, in: app)
        XCTAssertTrue(more.waitForExistence(timeout: 5) && more.isHittable)
        activate(more)

        let delete = app.buttons["Delete Time Record"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3) && delete.isHittable)
        activate(delete)

        let destructiveConfirmation = app.buttons["End Focus and Delete"].firstMatch
        XCTAssertTrue(
            destructiveConfirmation.waitForExistence(timeout: 3) &&
                destructiveConfirmation.isHittable
        )
        XCTAssertTrue(
            app.staticTexts[
                "This ends the active focus and removes all time records linked to this focus from totals and analytics."
            ].exists
        )
        try capture("iphone-active-focus-delete-impact", app: app)
        #endif
    }

    @MainActor
    func testSyncRecoveryUsesExplicitDestructiveConfirmations() throws {
        #if os(macOS)
        throw XCTSkip("The compact Settings recovery flow requires an iOS simulator.")
        #else
        let app = launchApp()
        openSettings(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["settings.view"].waitForExistence(timeout: 8))

        let dataAndSync = app.buttons["settings.category.dataAndSync"].firstMatch
        XCTAssertTrue(
            waitForElement(dataAndSync, timeout: 3, diagnosticName: "settings-data-and-sync", in: app)
                && dataAndSync.isHittable
        )
        activate(dataAndSync)

        let recoveryDisclosure = app.descendants(matching: .any)[
            "settings.syncRecovery.disclosure"
        ].firstMatch
        scrollUntilHittable(recoveryDisclosure, direction: .up, in: app)
        XCTAssertTrue(
            waitForElement(
                recoveryDisclosure,
                timeout: 5,
                diagnosticName: "settings-sync-recovery-disclosure",
                in: app
            ) && recoveryDisclosure.isHittable
        )
        XCTAssertFalse(app.buttons["settings.syncRecovery.replaceCloud"].firstMatch.exists)
        XCTAssertFalse(app.buttons["settings.syncRecovery.replaceDevice"].firstMatch.exists)
        try capture("iphone-settings-sync-recovery-collapsed", app: app)
        activate(recoveryDisclosure)

        let replaceCloud = app.buttons["settings.syncRecovery.replaceCloud"].firstMatch
        scrollUntilHittable(replaceCloud, direction: .up, in: app)
        XCTAssertTrue(
            waitForElement(replaceCloud, timeout: 5, diagnosticName: "settings-replace-cloud", in: app)
                && replaceCloud.isHittable
        )
        try capture("iphone-settings-sync-recovery-expanded", app: app)

        activate(replaceCloud)
        let replaceCloudConfirmation = app.buttons["Replace iCloud"].firstMatch
        XCTAssertTrue(
            waitForElement(
                replaceCloudConfirmation,
                timeout: 3,
                diagnosticName: "settings-replace-cloud-confirmation",
                in: app
            )
        )
        try capture("iphone-settings-replace-cloud-confirmation", app: app)
        let dismissUpload = app.descendants(matching: .any)["PopoverDismissRegion"].firstMatch
        XCTAssertTrue(dismissUpload.waitForExistence(timeout: 2))
        activate(dismissUpload)

        let replaceDevice = app.buttons["settings.syncRecovery.replaceDevice"].firstMatch
        scrollUntilHittable(replaceDevice, direction: .up, in: app)
        XCTAssertTrue(
            waitForElement(replaceDevice, timeout: 3, diagnosticName: "settings-replace-device", in: app)
                && replaceDevice.isHittable
        )
        activate(replaceDevice)
        let replaceDeviceConfirmation = app.buttons["Replace This Device"].firstMatch
        XCTAssertTrue(
            waitForElement(
                replaceDeviceConfirmation,
                timeout: 3,
                diagnosticName: "settings-replace-device-confirmation",
                in: app
            )
        )
        try capture("iphone-settings-replace-device-confirmation", app: app)
        let dismissDownload = app.descendants(matching: .any)["PopoverDismissRegion"].firstMatch
        XCTAssertTrue(dismissDownload.waitForExistence(timeout: 2))
        activate(dismissDownload)
        #endif
    }

    @MainActor
    func testSyncConflictNoticeRoutesToSummariesBeforeAnyDestructiveChoice() throws {
        #if os(macOS)
        throw XCTSkip("The compact conflict notice flow requires an iOS simulator.")
        #else
        let app = launchApp(route: "sync-conflict")
        let notice = app.descendants(matching: .any)["sync.conflict.notice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Replace iCloud"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Replace This Device"].firstMatch.exists)
        try capture("iphone-sync-conflict-notice", app: app)

        let review = app.buttons["sync.conflict.notice.review"].firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 3) && review.isHittable)
        activate(review)
        XCTAssertTrue(app.descendants(matching: .any)["settings.view"].waitForExistence(timeout: 5))

        let dataAndSync = app.buttons["settings.category.dataAndSync"].firstMatch
        XCTAssertTrue(dataAndSync.waitForExistence(timeout: 3) && dataAndSync.isHittable)
        activate(dataAndSync)
        let localSummary = app.descendants(matching: .any)[
            "settings.syncRecovery.localSummary"
        ].firstMatch
        let cloudSummary = app.descendants(matching: .any)[
            "settings.syncRecovery.cloudSummary"
        ].firstMatch
        scrollUntilHittable(localSummary, direction: .up, in: app)
        XCTAssertTrue(localSummary.waitForExistence(timeout: 3) && localSummary.isHittable)
        XCTAssertTrue(cloudSummary.waitForExistence(timeout: 3))
        try capture("iphone-sync-conflict-summaries", app: app)
        #endif
    }

    @MainActor
    func testSettingsCategoryNavigationRemainsReachableAtLargeTextSizes() throws {
        let app = launchApp(
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )
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
        let app = launchApp(
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )
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
        let firstTaskValue = firstTask.value as? String ?? ""
        XCTAssertTrue(
            firstTaskValue.localizedCaseInsensitiveContains("worked"),
            "The task row must preserve worked-time context at Accessibility XXXL."
        )
        try capture("iphone-tasks-accessibility-list", app: app)

        activate(firstTask)
        XCTAssertTrue(taskDetailIsReady(in: app))
    }

    @MainActor
    func testTaskDetailSystemBackPreservesExpandedTaskTree() throws {
        #if os(macOS)
        throw XCTSkip("This route-preservation screenshot runs on iPhone and iPad simulators.")
        #else
        let app = launchApp(route: "tasks")
        XCTAssertTrue(app.descendants(matching: .any)["tasks.view"].waitForExistence(timeout: 8))

        let studyDisclosure = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "tasks.disclosure."))
            .matching(NSPredicate(format: "value == %@", "Study"))
            .firstMatch
        XCTAssertTrue(
            waitForElement(
                studyDisclosure,
                timeout: 5,
                diagnosticName: "tasks-study-disclosure",
                in: app
            ) && studyDisclosure.isHittable
        )
        activate(studyDisclosure)

        let child = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "tasks.row."))
            .matching(NSPredicate(format: "label == %@", "Read Apple HIG"))
            .firstMatch
        XCTAssertTrue(
            waitForElement(
                child,
                timeout: 5,
                diagnosticName: "tasks-expanded-child",
                in: app
            ) && child.isHittable
        )
        activate(child)

        XCTAssertTrue(taskDetailIsReady(in: app))
        let systemBack = app.navigationBars.buttons["Tasks"].firstMatch
        XCTAssertTrue(
            waitForElement(
                systemBack,
                timeout: 5,
                diagnosticName: "task-detail-system-back",
                in: app
            ) && systemBack.isHittable
        )
        try capture("tasks-route-detail-system-back", app: app)
        activate(systemBack)

        XCTAssertTrue(app.descendants(matching: .any)["tasks.view"].waitForExistence(timeout: 5))
        XCTAssertTrue(child.waitForExistence(timeout: 5) && child.isHittable)
        try capture("tasks-route-expanded-tree-restored", app: app)
        #endif
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

        activate(field)
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
        try capture("iphone-inbox-captured-item", app: app)
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
        try capture("scene-router-task-editor", app: app)
        closePresentedEditor(in: app)

        openSection("Focus", tabIdentifier: "phone.tab.focus", sidebarIdentifier: "sidebar.Pomodoro", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["pomodoro.view"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testTaskEditorSymbolPickerPushPreservesTheOuterDraft() throws {
        #if os(macOS)
        throw XCTSkip("The pushed symbol picker is an iPhone navigation flow.")
        #else
        let app = launchApp()

        XCTAssertTrue(homeIsReady(in: app))
        openSection("Tasks", tabIdentifier: "phone.tab.tasks", sidebarIdentifier: "sidebar.Tasks", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["tasks.view"].waitForExistence(timeout: 8))
        let addTaskMenu = app.descendants(matching: .any)["tasks.add"].firstMatch
        XCTAssertTrue(addTaskMenu.waitForExistence(timeout: 3) && addTaskMenu.isHittable)
        activate(addTaskMenu)

        let addRootTask = app.descendants(matching: .any)["tasks.addRoot"].firstMatch
        XCTAssertTrue(addRootTask.waitForExistence(timeout: 3) && addRootTask.isHittable)
        activate(addRootTask)

        let editor = app.descendants(matching: .any)["task.editor"].firstMatch
        let titleField = app.descendants(matching: .any)["task.editor.title.field"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(titleField.waitForExistence(timeout: 3) && titleField.isHittable)
        let editorSheetCount = app.sheets.count

        let draftTitle = "Navigation draft"
        titleField.typeText(draftTitle)
        titleField.typeText(XCUIKeyboardKey.return.rawValue)
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))

        let symbolColor = app.buttons["symbol.picker.open"].firstMatch
        scrollUntilHittable(symbolColor, direction: .up, in: app)
        XCTAssertTrue(symbolColor.waitForExistence(timeout: 3) && symbolColor.isHittable)
        activate(symbolColor)

        let picker = app.descendants(matching: .any)["symbol.picker.view"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(app.sheets.count, editorSheetCount)

        let searchField = app.textFields["Search symbol names"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3) && searchField.isHittable)
        searchField.tap()
        searchField.typeText("calendar")

        let calendar = app.buttons["Symbol calendar"].firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 3) && calendar.isHittable)
        activate(calendar)
        try capture("iphone-task-symbol-picker-pushed", app: app)

        let back = app.navigationBars.buttons["New Task"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 3) && back.isHittable)
        activate(back)

        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(titleField.value as? String, draftTitle)
        XCTAssertFalse(picker.exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        try capture("iphone-task-editor-symbol-return", app: app)
        #endif
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
    func testFocusTaskPickerSearchesAndSelectsWithoutStartingFocus() throws {
        #if os(macOS)
        throw XCTSkip("The Focus task picker interaction requires an iOS simulator.")
        #else
        let app = launchApp(route: "focus")
        XCTAssertTrue(app.descendants(matching: .any)["pomodoro.view"].waitForExistence(timeout: 8))

        let openPicker = app.buttons["pomodoro.taskPicker.open"].firstMatch
        scrollUntilHittable(openPicker, direction: .up, in: app)
        XCTAssertTrue(openPicker.waitForExistence(timeout: 5) && openPicker.isHittable)
        activate(openPicker)

        let picker = app.descendants(matching: .any)["pomodoro.taskPicker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let search = app.searchFields["Search tasks, paths, or notes"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3) && search.isHittable)
        search.tap()
        search.typeText("SwiftData Docs")

        let selectedTask = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "pomodoro.taskPicker.select.")
        ).matching(
            NSPredicate(format: "label == %@", "SwiftData Docs")
        ).firstMatch
        XCTAssertTrue(selectedTask.waitForExistence(timeout: 3) && selectedTask.isHittable)
        activate(selectedTask)

        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SwiftData Docs"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["pomodoro.active"].exists)
        try capture("iphone-focus-task-picker-selection", app: app)
        #endif
    }

    @MainActor
    func testAnalyticsFinalCategoryScrollsAboveSystemChrome() throws {
        #if os(macOS)
        throw XCTSkip("Analytics system-chrome clearance requires an iOS simulator.")
        #else
        let app = launchApp(route: "analytics")

        XCTAssertTrue(analyticsIsReady(in: app))
        let finalCategory = app.descendants(matching: .any)["analytics.category.overview"].firstMatch
        scrollUntilHittable(finalCategory, direction: .up, in: app)
        XCTAssertTrue(
            waitForElement(
                finalCategory,
                timeout: 5,
                diagnosticName: "analytics-final-category",
                in: app
            )
        )
        scrollUntilFullyVisibleAboveSystemChrome(finalCategory, in: app)
        XCTAssertTrue(
            isFullyVisibleAboveSystemChrome(finalCategory, in: app),
            "The final Analytics category must be completely visible above the floating tab bar."
        )
        try capture("iphone-analytics-final-category", app: app)
        #endif
    }

    @MainActor
    func testAnalyticsMetricsExplainTheMatchedComparisonWindow() throws {
        #if os(macOS)
        throw XCTSkip("Analytics metric layout screenshots require an iOS simulator.")
        #else
        let app = launchApp(route: "analytics")

        XCTAssertTrue(analyticsIsReady(in: app))
        let metrics = app.descendants(matching: .any)["analytics.category.overview"].firstMatch
        scrollUntilHittable(metrics, direction: .up, in: app)
        XCTAssertTrue(metrics.waitForExistence(timeout: 5) && metrics.isHittable)
        activate(metrics)

        let detail = app.descendants(matching: .any)["analytics.categoryDetail.overview"].firstMatch
        let wallMetric = app.descendants(matching: .any)["analytics.metric.wall"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        XCTAssertTrue(wallMetric.waitForExistence(timeout: 8))
        XCTAssertTrue(
            wallMetric.label.contains("same point in the previous period"),
            "The live comparison must disclose that it uses matched period progress."
        )
        try capture("iphone-analytics-matched-comparison", app: app)
        #endif
    }

    @MainActor
    func testAnalyticsDailyTrendShowsWallAndGrossLegend() throws {
        #if os(macOS)
        throw XCTSkip("Analytics trend layout screenshots require an iOS simulator.")
        #else
        let app = launchApp(route: "analytics")

        XCTAssertTrue(analyticsIsReady(in: app))
        let week = app.segmentedControls.buttons["Week"].firstMatch
        XCTAssertTrue(week.waitForExistence(timeout: 5) && week.isHittable)
        activate(week)

        let time = app.descendants(matching: .any)["analytics.category.time"].firstMatch
        scrollUntilHittable(time, direction: .up, in: app)
        XCTAssertTrue(time.waitForExistence(timeout: 5) && time.isHittable)
        activate(time)

        let detail = app.descendants(matching: .any)["analytics.categoryDetail.time"].firstMatch
        let chart = app.descendants(matching: .any)["analytics.dailyTrend.chart"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        XCTAssertTrue(chart.waitForExistence(timeout: 8))
        try capture("iphone-analytics-daily-trend-legend", app: app)
        #endif
    }

    @MainActor
    func testAnalyticsTodayDistributionUsesSharedScale() throws {
        #if os(macOS)
        throw XCTSkip("Analytics hourly distribution screenshots require an iOS simulator.")
        #else
        try verifyAnalyticsTodayDistribution(
            screenshotName: "iphone-analytics-hour-distribution",
            contentSizeCategory: nil
        )
        #endif
    }

    @MainActor
    func testAnalyticsTodayDistributionAtAccessibilitySize() throws {
        #if os(macOS)
        throw XCTSkip("Analytics hourly distribution screenshots require an iOS simulator.")
        #else
        try verifyAnalyticsTodayDistribution(
            screenshotName: "iphone-analytics-hour-distribution-accessibility",
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        #endif
    }

    @MainActor
    func testAnalyticsMonthNavigationReturnsToTheCurrentPeriod() throws {
        #if os(macOS)
        throw XCTSkip("Analytics month navigation screenshots require an iOS simulator.")
        #else
        let app = launchApp(route: "analytics")

        XCTAssertTrue(analyticsIsReady(in: app))
        let month = app.segmentedControls.buttons["Month"].firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 5) && month.isHittable)
        activate(month)
        XCTAssertTrue(analyticsIsReady(in: app))

        let previous = app.buttons["analytics.period.previous"].firstMatch
        let next = app.buttons["analytics.period.next"].firstMatch
        XCTAssertTrue(previous.waitForExistence(timeout: 5) && previous.isHittable)
        XCTAssertFalse(next.isEnabled)

        activate(previous)
        let enabledExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: next
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabledExpectation], timeout: 5), .completed)
        try capture("iphone-analytics-previous-month", app: app)

        activate(next)
        let disabledExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == false"),
            object: next
        )
        XCTAssertEqual(XCTWaiter.wait(for: [disabledExpectation], timeout: 5), .completed)
        try capture("iphone-analytics-current-month-restored", app: app)
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
    func testQuickStartShowsRootAndChildIdentityWithSeparateTimerActions() throws {
        let app = launchApp()
        XCTAssertTrue(homeIsReady(in: app))

        let quickStartRows = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "home.quickStart.task."
            )
        )
        let root = quickStartRows.matching(
            NSPredicate(format: "label == %@", "Time Tracker App")
        ).firstMatch
        let child = quickStartRows.matching(
            NSPredicate(format: "label == %@", "Design System")
        ).firstMatch
        XCTAssertTrue(
            waitForElement(
                root,
                timeout: 5,
                diagnosticName: "quick-start-root",
                in: app
            )
        )
        XCTAssertTrue(
            waitForElement(
                child,
                timeout: 5,
                diagnosticName: "quick-start-child",
                in: app
            )
        )
        XCTAssertTrue((root.value as? String ?? "").isEmpty)
        XCTAssertEqual(child.value as? String, "Time Tracker App")

        scrollUntilHittable(child, direction: .up, in: app)
        XCTAssertTrue(child.isHittable)
        let childTimerAction = app.buttons[
            "home.quickStart.timer.\(child.identifier.replacingOccurrences(of: "home.quickStart.task.", with: ""))"
        ].firstMatch
        XCTAssertTrue(childTimerAction.waitForExistence(timeout: 5) && childTimerAction.isHittable)
        activate(childTimerAction)
        let running = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Running"),
            object: child
        )
        XCTAssertEqual(XCTWaiter.wait(for: [running], timeout: 5), .completed)
        let childTaskIdentifier = child.identifier.replacingOccurrences(
            of: "home.quickStart.task.",
            with: ""
        )
        let timerIdentifier = "home.quickStart.timer.\(childTaskIdentifier)"
        let stopAction = app.buttons[timerIdentifier].firstMatch
        XCTAssertTrue(stopAction.waitForExistence(timeout: 5))
        try capture("quick-start-separate-actions-running", app: app)
        scrollUntilFullyVisibleAboveSystemChrome(stopAction, in: app)
        XCTAssertTrue(stopAction.isHittable)
        XCTAssertEqual(stopAction.label, "Stop Design System")
        activate(stopAction)
        let stopped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Time Tracker App"),
            object: child
        )
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 5), .completed)

        let edit = app.buttons["home.quickStart.edit"].firstMatch
        scrollUntilHittable(edit, direction: .up, in: app)
        XCTAssertTrue(edit.waitForExistence(timeout: 3) && edit.isHittable)
        activate(edit)

        XCTAssertTrue(app.navigationBars["Edit Quick Start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Time Tracker App"].waitForExistence(timeout: 3))
        try capture("quick-start-editor-task-identity", app: app)
    }

    @MainActor
    func testRunningQuickStartOpensTaskDetailInsteadOfStopping() throws {
        #if os(macOS)
        throw XCTSkip("The phone Quick Start interaction requires an iOS simulator.")
        #else
        let app = launchApp()
        XCTAssertTrue(homeIsReady(in: app))

        let child = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "home.quickStart.task."
            )
        ).matching(
            NSPredicate(format: "label == %@", "Design System")
        ).firstMatch
        scrollUntilHittable(child, direction: .up, in: app)
        XCTAssertTrue(child.waitForExistence(timeout: 5) && child.isHittable)

        let childTimerAction = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "home.quickStart.timer."
            )
        ).matching(
            NSPredicate(format: "label == %@", "Start Design System")
        ).firstMatch
        scrollUntilHittable(childTimerAction, direction: .up, in: app)
        XCTAssertTrue(childTimerAction.waitForExistence(timeout: 5) && childTimerAction.isHittable)
        activate(childTimerAction)
        let running = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Running"),
            object: child
        )
        XCTAssertEqual(XCTWaiter.wait(for: [running], timeout: 5), .completed)

        activate(child)
        XCTAssertTrue(taskDetailIsReady(in: app))
        XCTAssertTrue(app.staticTexts["Design System"].waitForExistence(timeout: 3))
        try capture("quick-start-running-opens-detail", app: app)
        #endif
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
    func testTodayPrimaryTimerActionKeepsVisibleTextAtLargestAccessibilitySize() throws {
        #if os(macOS)
        throw XCTSkip("The Today Accessibility XXXL screenshot requires an iOS simulator.")
        #else
        let app = launchApp(
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        XCTAssertTrue(homeIsReady(in: app))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.activeTimer."))
                .firstMatch
                .waitForExistence(timeout: 5),
            "Demo data must expose an active timer so this test covers the active-state action."
        )

        let startTimer = app.buttons["home.startTimer"].firstMatch
        scrollUntilHittable(startTimer, direction: .up, in: app)
        XCTAssertTrue(startTimer.waitForExistence(timeout: 5) && startTimer.isHittable)
        XCTAssertTrue(
            ["Start Another Timer", "Switch Timer"].contains(startTimer.label),
            "The active-state timer action must keep its visible verb label at Accessibility XXXL."
        )
        try capture("iphone-today-primary-action-accessibility", app: app)
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
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif

        let app = launchApp()

        XCTAssertTrue(homeIsReady(in: app))
        XCTAssertTrue(app.descendants(matching: .any)["ipad.splitNavigation"].waitForExistence(timeout: 3))

        let sidebarTask = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sidebar.task."))
            .firstMatch
        if !sidebarTask.waitForExistence(timeout: 1) {
            let identifiedToggle = app.descendants(matching: .any)["sidebar.show"].firstMatch
            let systemToggle = app.buttons["Show Sidebar"].firstMatch
            if identifiedToggle.waitForExistence(timeout: 1), identifiedToggle.isHittable {
                activate(identifiedToggle)
            } else if systemToggle.waitForExistence(timeout: 1), systemToggle.isHittable {
                activate(systemToggle)
            }
        }
        XCTAssertTrue(sidebarTask.waitForExistence(timeout: 3), "The iPad sidebar must expose seeded tasks")

        activate(sidebarTask)

        XCTAssertTrue(taskDetailIsReady(in: app))
        XCTAssertFalse(app.descendants(matching: .any)["task.editor"].waitForExistence(timeout: 1))
        try capture("ipad-sidebar-task-detail-portrait", app: app)

        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.descendants(matching: .any)["ipad.splitNavigation"].waitForExistence(timeout: 3))
        XCTAssertTrue(taskDetailIsReady(in: app))
        try capture("ipad-sidebar-task-detail-landscape", app: app)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.descendants(matching: .any)["ipad.splitNavigation"].waitForExistence(timeout: 3))
        XCTAssertTrue(taskDetailIsReady(in: app))
        try capture("ipad-sidebar-task-detail-restored", app: app)
        #endif
    }

    @MainActor
    private func launchApp(
        route: String = "today",
        contentSizeCategory: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-TimeTrackerAutomaticDemoDataModeOverride", "seedIfEmpty",
            "-TimeTrackerAutomaticDemoSeedingDisabled", "NO"
        ]
        if let contentSizeCategory {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                contentSizeCategory
            ]
        }
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"
        app.launchEnvironment["TIMETRACKER_UI_AUDIT_ROUTE"] = route
        app.launch()
        app.activate()
        return app
    }

    @MainActor
    private func verifyAnalyticsTodayDistribution(
        screenshotName: String,
        contentSizeCategory: String?
    ) throws {
        let app = launchApp(
            route: "analytics",
            contentSizeCategory: contentSizeCategory
        )

        XCTAssertTrue(analyticsIsReady(in: app))
        let time = app.descendants(matching: .any)["analytics.category.time"].firstMatch
        scrollUntilHittable(time, direction: .up, in: app)
        XCTAssertTrue(time.waitForExistence(timeout: 5) && time.isHittable)
        activate(time)

        let detail = app.descendants(matching: .any)["analytics.categoryDetail.time"].firstMatch
        let distribution = app.descendants(matching: .any)[
            "analytics.hourDistribution.content"
        ].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        XCTAssertTrue(distribution.waitForExistence(timeout: 8))
        if contentSizeCategory != nil {
            app.swipeUp()
        }
        try capture(screenshotName, app: app)
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

        if openCollapsedSidebarDestination(sidebarIdentifier, in: app) {
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
    private func openCollapsedSidebarDestination(
        _ sidebarIdentifier: String,
        in app: XCUIApplication
    ) -> Bool {
        let identifiedToggle = app.descendants(matching: .any)["sidebar.show"].firstMatch
        if identifiedToggle.waitForExistence(timeout: 1), identifiedToggle.isHittable {
            activate(identifiedToggle)
        } else {
            // NavigationSplitView owns the platform-standard toggle, so SwiftUI
            // does not currently expose an application accessibility identifier.
            // UI audit launches are pinned to English to keep this fallback stable.
            let systemToggle = app.buttons["Show Sidebar"].firstMatch
            guard systemToggle.waitForExistence(timeout: 1), systemToggle.isHittable else {
                return false
            }
            activate(systemToggle)
        }

        let destination = app.descendants(matching: .any)[sidebarIdentifier].firstMatch
        guard destination.waitForExistence(timeout: 3), destination.isHittable else {
            return false
        }
        activate(destination)
        return true
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
        #if os(iOS)
        let screenshot = XCUIScreen.main.screenshot()
        #else
        let screenshot = app.screenshot()
        #endif
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

// MARK: - TEMP Analytics review screenshots (remove after review)

final class AnalyticsReviewScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    @MainActor
    private func launchAnalytics() -> XCUIApplication {
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
        app.launchEnvironment["TIMETRACKER_UI_AUDIT_ROUTE"] = "analytics"
        app.launch()
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["analytics.summary"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
    }

    @MainActor
    private func openCategory(_ identifier: String, in app: XCUIApplication) {
        let row = app.descendants(matching: .any)[identifier].firstMatch
        scrollToHittable(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5) && row.isHittable)
        row.tap()
        sleep(1)
    }

    @MainActor
    private func backToAnalyticsHome(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        if back.waitForExistence(timeout: 3) && back.isHittable {
            back.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["analytics.summary"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testReviewAnalyticsTodayFlow() throws {
        let app = launchAnalytics()
        shot("review-01-home-today", app)

        openCategory("analytics.category.time", in: app)
        shot("review-02-time-today-distribution", app)
        app.swipeUp()
        app.swipeUp()
        shot("review-03-time-today-timeline", app)
        backToAnalyticsHome(in: app)

        openCategory("analytics.category.tasks", in: app)
        shot("review-04-tasks-donut", app)
        app.swipeUp()
        shot("review-05-tasks-breakdowns", app)
        backToAnalyticsHome(in: app)

        openCategory("analytics.category.decisions", in: app)
        shot("review-06-decisions", app)
        app.swipeUp()
        shot("review-07-decisions-forecasts", app)
        backToAnalyticsHome(in: app)

        openCategory("analytics.category.quality", in: app)
        shot("review-08-quality", app)
        app.swipeUp()
        shot("review-09-quality-overlap", app)
        backToAnalyticsHome(in: app)

        openCategory("analytics.category.pomodoro", in: app)
        shot("review-10-pomodoro", app)
        backToAnalyticsHome(in: app)
    }

    @MainActor
    func testReviewAnalyticsMonth() throws {
        let app = launchAnalytics()

        for _ in 0..<4 { app.swipeDown() }
        let month = app.segmentedControls.buttons["Month"].firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 5) && month.isHittable)
        month.tap()
        sleep(1)
        shot("review-13-home-month", app)

        openCategory("analytics.category.time", in: app)
        shot("review-14-time-month-trend", app)
        backToAnalyticsHome(in: app)

        for _ in 0..<4 { app.swipeDown() }
        let week = app.segmentedControls.buttons["Week"].firstMatch
        XCTAssertTrue(week.waitForExistence(timeout: 5) && week.isHittable)
        week.tap()
        sleep(1)
        shot("review-15-home-week", app)

        openCategory("analytics.category.tasks", in: app)
        shot("review-16-tasks-week-donut", app)
        backToAnalyticsHome(in: app)
    }
}
