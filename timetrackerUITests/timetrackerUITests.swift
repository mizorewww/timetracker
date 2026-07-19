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
    func testTrailingMenusStayReachableAtTaskCardEdges() throws {
        #if os(macOS)
        throw XCTSkip("Card-edge geometry is verified on iPhone.")
        #else
        let tasksApp = launchApp(route: "tasks")
        XCTAssertTrue(
            tasksApp.descendants(matching: .any)["tasks.view"]
                .waitForExistence(timeout: 8)
        )
        let categoryMenu = tasksApp.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "tasks.category.actions."
            ))
            .firstMatch
        let firstTaskRow = tasksApp.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "tasks.row."
            ))
            .firstMatch
        XCTAssertTrue(categoryMenu.waitForExistence(timeout: 5) && categoryMenu.isHittable)
        XCTAssertTrue(firstTaskRow.waitForExistence(timeout: 5) && firstTaskRow.isHittable)
        XCTAssertGreaterThanOrEqual(categoryMenu.frame.width, 44)
        XCTAssertEqual(
            categoryMenu.frame.maxX,
            firstTaskRow.frame.maxX,
            accuracy: 2,
            "The category action target must share the task card's trailing content edge."
        )
        try capture("iphone-task-category-trailing-menu", app: tasksApp)
        tasksApp.terminate()

        let homeApp = launchApp()
        XCTAssertTrue(homeIsReady(in: homeApp))
        let timelineMenu = homeApp.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "timeline.more."
            ))
            .firstMatch
        scrollUntilHittable(timelineMenu, direction: .up, in: homeApp)
        XCTAssertTrue(timelineMenu.waitForExistence(timeout: 5) && timelineMenu.isHittable)
        XCTAssertGreaterThanOrEqual(timelineMenu.frame.width, 44)
        try capture("iphone-home-timeline-trailing-menu", app: homeApp)
        #endif
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
    func testTaskAnalysisRangeSwitchKeepsItsScrollPosition() throws {
        #if os(macOS)
        throw XCTSkip("This scroll-position regression is exercised on iPhone.")
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
                diagnosticName: "task-analysis-study-disclosure",
                in: app
            ) && studyDisclosure.isHittable
        )
        activate(studyDisclosure)

        let task = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "tasks.row."))
            .matching(NSPredicate(format: "label == %@", "Read Apple HIG"))
            .firstMatch
        XCTAssertTrue(
            waitForElement(
                task,
                timeout: 5,
                diagnosticName: "task-analysis-demo-task",
                in: app
            ) && task.isHittable
        )
        activate(task)
        XCTAssertTrue(taskDetailIsReady(in: app))

        let rangePicker = app.segmentedControls.firstMatch
        scrollUntilHittable(rangePicker, direction: .up, in: app)
        XCTAssertTrue(
            waitForElement(
                rangePicker,
                timeout: 5,
                diagnosticName: "task-analysis-range-picker",
                in: app
            ) && rangePicker.isHittable
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["task.detail.identity"].firstMatch.isHittable
        )

        for rangeName in ["Day", "Month", "Week"] {
            let originalFrame = rangePicker.frame
            let rangeButton = rangePicker.buttons[rangeName].firstMatch
            XCTAssertTrue(
                rangeButton.waitForExistence(timeout: 3) && rangeButton.isHittable
            )
            activate(rangeButton)

            let selectionExpectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "selected == true"),
                object: rangeButton
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [selectionExpectation], timeout: 3),
                .completed
            )

            XCTAssertTrue(
                rangePicker.exists && rangePicker.isHittable,
                "Changing to \(rangeName) must not scroll Task Analysis off screen."
            )
            XCTAssertLessThan(
                abs(rangePicker.frame.minY - originalFrame.minY),
                16,
                "Changing to \(rangeName) unexpectedly moved the Task Analysis picker."
            )
            XCTAssertFalse(
                app.descendants(matching: .any)["task.detail.identity"].firstMatch.isHittable,
                "Changing to \(rangeName) unexpectedly jumped to the top of Task Detail."
            )
        }

        try capture("iphone-task-analysis-range-scroll-preserved", app: app)
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
    func testInboxItemMovesThroughTheSharedTaskHierarchyPicker() throws {
        #if os(macOS)
        throw XCTSkip("The Inbox task-routing interaction requires an iOS simulator.")
        #else
        let app = launchApp()
        openSection(
            "Inbox",
            tabIdentifier: "phone.tab.inbox",
            sidebarIdentifier: "sidebar.Inbox",
            in: app
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["inbox.view"]
                .waitForExistence(timeout: 8)
        )

        let field = app.descendants(matching: .any)["inbox.capture.field"].firstMatch
        let addButton = app.buttons["inbox.capture.add"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3) && field.isHittable)
        XCTAssertTrue(addButton.waitForExistence(timeout: 3) && addButton.isHittable)
        activate(field)
        field.typeText("Route release checklist")
        activate(addButton)

        let menu = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "inbox.item.menu."
            ))
            .firstMatch
        XCTAssertTrue(
            waitForElement(
                menu,
                timeout: 5,
                diagnosticName: "inbox-route-menu",
                in: app
            ) && menu.isHittable
        )
        activate(menu)

        let move = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "inbox.moveToTask."
            ))
            .firstMatch
        XCTAssertTrue(move.waitForExistence(timeout: 3) && move.isHittable)
        activate(move)

        let picker = app.descendants(matching: .any)["inbox.taskPicker"].firstMatch
        XCTAssertTrue(
            waitForElement(
                picker,
                timeout: 5,
                diagnosticName: "inbox-shared-task-picker",
                in: app
            )
        )
        try capture("iphone-inbox-shared-task-picker", app: app)

        let search = app.searchFields["Search tasks, paths, or notes"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3) && search.isHittable)
        activate(search)
        search.typeText("SwiftData Docs")

        let target = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "inbox.taskPicker.select."
            ))
            .matching(NSPredicate(format: "label == %@", "SwiftData Docs"))
            .firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 3) && target.isHittable)
        activate(target)

        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertTrue(menu.waitForNonExistence(timeout: 5))
        try capture("iphone-inbox-routed-to-task", app: app)
        #endif
    }

    @MainActor
    func testInboxNativeCardsShowAndApplyTheGeneratedVisualSuggestion() throws {
        #if os(macOS)
        throw XCTSkip("Inset-grouped card geometry is verified on iPhone and iPad.")
        #else
        let app = launchApp(
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: ["--uitesting-inbox-suggestion"]
        )
        openSection(
            "Inbox",
            tabIdentifier: "phone.tab.inbox",
            sidebarIdentifier: "sidebar.Inbox",
            in: app
        )
        let inbox = app.descendants(matching: .any)["inbox.view"].firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 8))

        let captureField = app.textFields["inbox.capture.field"].firstMatch
        let itemField = app.textFields
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "inbox.item."
            ))
            .firstMatch
        let suggestion = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "inbox.suggestion.ready."
            ))
            .firstMatch
        let apply = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "inbox.suggestion.apply."
            ))
            .firstMatch
        let targetLabel = app.staticTexts["Suggested task: Design System"].firstMatch

        XCTAssertTrue(captureField.waitForExistence(timeout: 5))
        XCTAssertTrue(itemField.waitForExistence(timeout: 5))
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        XCTAssertTrue(targetLabel.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(
            targetLabel.frame.width,
            120,
            "The generated task label must not collapse behind the action buttons."
        )
        XCTAssertTrue(
            app.buttons["inbox.completed.disclosure"].firstMatch
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(apply.waitForExistence(timeout: 3) && apply.isHittable)
        XCTAssertGreaterThanOrEqual(apply.frame.width, 44)
        XCTAssertGreaterThanOrEqual(apply.frame.height, 44)

        let captureCard = app.cells
            .containing(.textField, identifier: captureField.identifier)
            .firstMatch
        let itemCard = app.cells
            .containing(.textField, identifier: itemField.identifier)
            .firstMatch
        XCTAssertTrue(captureCard.exists)
        XCTAssertTrue(itemCard.exists)
        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(captureCard.frame.minX, windowFrame.minX + 12)
        XCTAssertLessThan(captureCard.frame.maxX, windowFrame.maxX - 12)
        XCTAssertGreaterThan(itemCard.frame.minX, windowFrame.minX + 12)
        XCTAssertLessThan(itemCard.frame.maxX, windowFrame.maxX - 12)
        try capture("inbox-native-cards-ready-suggestion", app: app)

        activate(apply)
        XCTAssertTrue(suggestion.waitForNonExistence(timeout: 5))
        XCTAssertTrue(itemCard.waitForNonExistence(timeout: 5))
        try capture("inbox-native-cards-suggestion-applied", app: app)
        #endif
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
    func testAITaskPlanDraftReviewAtomicCreateAndInstructionsEditor() throws {
        #if os(macOS)
        throw XCTSkip("Task-plan review geometry is verified on iPhone and iPad.")
        #else
        let app = launchApp(
            route: "tasks",
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: ["--uitesting-ai-task-plan"]
        )
        openSection(
            "Tasks",
            tabIdentifier: "phone.tab.tasks",
            sidebarIdentifier: "sidebar.Tasks",
            in: app
        )
        let tasksView = app.descendants(matching: .any)["tasks.view"].firstMatch
        XCTAssertTrue(tasksView.waitForExistence(timeout: 8))

        let addMenu = app.descendants(matching: .any)["tasks.add"].firstMatch
        XCTAssertTrue(addMenu.waitForExistence(timeout: 3) && addMenu.isHittable)
        activate(addMenu)

        let generatePlan = app.descendants(matching: .any)[
            "tasks.generatePlan"
        ].firstMatch
        XCTAssertTrue(
            generatePlan.waitForExistence(timeout: 3) && generatePlan.isHittable
        )
        activate(generatePlan)

        let request = app.descendants(matching: .any)["aiTaskPlan.request"].firstMatch
        if !request.waitForExistence(timeout: 5),
           addMenu.waitForExistence(timeout: 2),
           addMenu.isHittable {
            activate(addMenu)
            if generatePlan.waitForExistence(timeout: 2), generatePlan.isHittable {
                activate(generatePlan)
            }
        }
        let generate = app.buttons["aiTaskPlan.generate"].firstMatch
        XCTAssertTrue(request.waitForExistence(timeout: 5) && request.isHittable)
        XCTAssertTrue(generate.waitForExistence(timeout: 3))
        XCTAssertFalse(generate.isEnabled)
        activate(request)
        request.typeText("Build a practical daily fitness and learning plan")
        XCTAssertTrue(generate.isEnabled)
        try capture("ai-task-plan-request", app: app)

        let cancelPlan = app.buttons["aiTaskPlan.cancel"].firstMatch
        XCTAssertTrue(cancelPlan.waitForExistence(timeout: 3) && cancelPlan.isHittable)
        activate(cancelPlan)
        let discardRequest = discardDialogButton(
            identifier: "editor.discard.confirm",
            localizedLabels: ["Discard Changes", "放弃更改", "放棄變更"],
            in: app
        )
        XCTAssertTrue(
            discardRequest.waitForExistence(timeout: 3) && discardRequest.isHittable
        )
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(discardRequest.waitForNonExistence(timeout: 3))
        XCTAssertTrue(request.waitForExistence(timeout: 3))
        XCTAssertTrue(generate.waitForExistence(timeout: 3) && generate.isHittable)

        activate(generate)

        let create = app.buttons["aiTaskPlan.create"].firstMatch
        let editRequest = app.buttons["aiTaskPlan.editRequest"].firstMatch
        let summary = app.staticTexts[
            "2 categories · 3 tasks · 4 checklist items"
        ].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 8) && create.isHittable)
        XCTAssertTrue(editRequest.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(create.frame.height, 28)
        try capture("ai-task-plan-preview", app: app)

        activate(editRequest)
        let discardDraft = discardDialogButton(
            identifier: "editor.discard.confirm",
            localizedLabels: ["Discard Changes", "放弃更改", "放棄變更"],
            in: app
        )
        XCTAssertTrue(
            discardDraft.waitForExistence(timeout: 3) && discardDraft.isHittable
        )
        activate(discardDraft)
        XCTAssertTrue(discardDraft.waitForNonExistence(timeout: 3))
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        XCTAssertTrue(
            generate.waitForExistence(timeout: 3) &&
                generate.isEnabled &&
                generate.isHittable
        )
        activate(generate)
        XCTAssertTrue(create.waitForExistence(timeout: 8) && create.isHittable)

        activate(create)
        XCTAssertTrue(
            app.descendants(matching: .any)["aiTaskPlan.sheet"]
                .waitForNonExistence(timeout: 8)
        )
        XCTAssertTrue(taskDetailIsReady(in: app))
        try capture("ai-task-plan-created-detail", app: app)

        app.terminate()
        let settingsApp = launchApp(route: "settings")
        let settingsView = settingsApp.descendants(matching: .any)[
            "settings.view"
        ].firstMatch
        if !settingsView.waitForExistence(timeout: 3) {
            openSettings(in: settingsApp)
        }
        XCTAssertTrue(settingsView.waitForExistence(timeout: 8))

        let intelligence = settingsApp.descendants(matching: .any)[
            "settings.category.intelligence"
        ].firstMatch
        XCTAssertTrue(
            intelligence.waitForExistence(timeout: 3) && intelligence.isHittable
        )
        activate(intelligence)

        let editInstructions = settingsApp.descendants(matching: .any)[
            "settings.llm.taskPlanInstructions.edit"
        ].firstMatch
        XCTAssertTrue(
            editInstructions.waitForExistence(timeout: 5) &&
                editInstructions.isHittable
        )
        activate(editInstructions)

        let editor = settingsApp.descendants(matching: .any)[
            "settings.llm.taskPlanInstructions.editor"
        ].firstMatch
        let byteCount = settingsApp.descendants(matching: .any)[
            "settings.llm.taskPlanInstructions.byteCount"
        ].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5) && editor.isHittable)
        XCTAssertTrue(byteCount.waitForExistence(timeout: 3))
        try capture("ai-task-plan-instructions-editor", app: settingsApp)
        #endif
    }

    @MainActor
    func testTaskEditorSymbolPickerPushPreservesTheOuterDraft() throws {
        #if os(macOS)
        throw XCTSkip("The pushed symbol picker is an iPhone navigation flow.")
        #else
        let app = launchApp(route: "tasks", seedsDemoData: false)

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
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        titleField.typeText(XCUIKeyboardKey.return.rawValue)
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 3))

        let symbolColor = app.descendants(matching: .any)[
            "symbol.picker.open.task"
        ].firstMatch
        scrollUntilHittable(symbolColor, direction: .up, in: app)
        XCTAssertTrue(symbolColor.waitForExistence(timeout: 3) && symbolColor.isHittable)
        activate(symbolColor)

        let picker = app.descendants(matching: .any)["symbol.picker.view"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(app.sheets.count, editorSheetCount)
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 3))

        var searchField = app.descendants(matching: .any)["symbol.picker.search"].firstMatch
        if searchField.waitForExistence(timeout: 2) == false {
            searchField = app.textFields["Search symbol names"].firstMatch
        }
        XCTAssertTrue(searchField.waitForExistence(timeout: 3) && searchField.isHittable)
        searchField.tap()

        let symbolViewport = app.descendants(matching: .any)["symbol.picker.symbols"].firstMatch
        let firstVisibleSymbol = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "symbol.picker.symbol."
            )
        ).firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        XCTAssertTrue(symbolViewport.waitForExistence(timeout: 3))
        XCTAssertTrue(
            firstVisibleSymbol.waitForExistence(timeout: 3) &&
                firstVisibleSymbol.isHittable
        )
        XCTAssertGreaterThanOrEqual(
            symbolViewport.frame.height,
            44,
            "The software keyboard must leave at least one tappable symbol row visible."
        )
        XCTAssertLessThanOrEqual(
            symbolViewport.frame.maxY,
            keyboard.frame.minY + 1,
            "The symbol viewport must stay above the software keyboard."
        )
        XCTAssertLessThanOrEqual(
            firstVisibleSymbol.frame.maxY,
            keyboard.frame.minY + 1,
            "A visible symbol must stay above the software keyboard."
        )
        try capture("task-symbol-picker-keyboard-clearance", app: app)

        let colorWell = app.descendants(matching: .any)["symbol.picker.color.well"].firstMatch
        XCTAssertTrue(colorWell.waitForExistence(timeout: 3) && colorWell.isHittable)
        XCTAssertGreaterThanOrEqual(colorWell.frame.width, 44)
        XCTAssertGreaterThanOrEqual(colorWell.frame.height, 44)
        let initialColorName = try XCTUnwrap(colorWell.value as? String)
        activate(colorWell)
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 3))

        let blossom = app.descendants(matching: .any)[
            "symbol.picker.color.blossom"
        ].firstMatch
        XCTAssertTrue(blossom.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(blossom.frame.width, 280)
        XCTAssertGreaterThanOrEqual(blossom.frame.height, 280)
        XCTAssertEqual(app.sheets.count, editorSheetCount)
        try capture("task-symbol-color-blossom", app: app)

        let petalOffsets = [
            CGVector(dx: 0.5, dy: 0.32),
            CGVector(dx: 0.68, dy: 0.5),
            CGVector(dx: 0.5, dy: 0.40)
        ]
        var previousColorName = initialColorName
        for offset in petalOffsets {
            blossom.coordinate(withNormalizedOffset: offset).tap()
            XCTAssertTrue(
                waitUntil(timeout: 3) {
                    guard let currentColorName = colorWell.value as? String else {
                        return false
                    }
                    return currentColorName != previousColorName
                },
                "Each visible Blossom ring must update the shared color binding."
            )
            previousColorName = try XCTUnwrap(colorWell.value as? String)
        }
        let selectedColorName = previousColorName

        let selectedPetal = blossom.coordinate(
            withNormalizedOffset: petalOffsets.last!
        )
        selectedPetal.tap()
        XCTAssertTrue(blossom.waitForNonExistence(timeout: 3))
        try capture("task-symbol-and-color-picker-selected", app: app)

        XCTAssertTrue(searchField.waitForExistence(timeout: 3) && searchField.isHittable)
        searchField.tap()
        searchField.typeText("calendar")

        let calendar = app.descendants(matching: .any)[
            "symbol.picker.symbol.calendar"
        ].firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 3) && calendar.isHittable)
        activate(calendar)
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 3))
        XCTAssertTrue(calendar.isSelected)

        let back = app.navigationBars.buttons["New Task"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 3) && back.isHittable)
        activate(back)

        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(titleField.value as? String, draftTitle)
        XCTAssertFalse(picker.exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertEqual(symbolColor.value as? String, selectedColorName)
        try capture("task-editor-symbol-return", app: app)
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
    func testAnalyticsQuestionsExposeAnswersAndOpenTimeDetails() throws {
        #if os(macOS)
        throw XCTSkip("The question-led Analytics path requires an iOS simulator.")
        #else
        let app = launchApp(route: "analytics")
        XCTAssertTrue(analyticsIsReady(in: app))

        let expectations: [
            (id: String, question: String, answer: String, destination: String)
        ] = [
            (
                "overview",
                "How much time did I spend?",
                "across all task timers",
                "Totals & Definitions"
            ),
            (
                "time",
                "When was my time most concentrated?",
                "Busiest at",
                "Time Patterns"
            ),
            (
                "tasks",
                "Which task took the most time?",
                "Read Apple HIG",
                "Task Breakdown"
            ),
            (
                "pomodoro",
                "How many focus rounds did I finish?",
                "completed",
                "Focus Rounds"
            ),
            (
                "decisions",
                "What deserves attention?",
                "Range Change",
                "Review Signals"
            ),
            (
                "quality",
                "Can I rely on these totals?",
                "overlap",
                "Tracking Checks"
            )
        ]

        for expectation in expectations {
            let row = app.descendants(matching: .any)[
                "analytics.category.\(expectation.id)"
            ].firstMatch
            scrollUntilHittable(row, direction: .up, in: app)
            XCTAssertTrue(
                waitForElement(
                    row,
                    timeout: 5,
                    diagnosticName: "analytics-question-\(expectation.id)",
                    in: app
                ) && row.isHittable
            )

            let label = row.label
            XCTAssertTrue(
                label.contains(expectation.question),
                "\(expectation.id) must state the question it answers. Label: \(label)"
            )
            XCTAssertTrue(
                label.localizedCaseInsensitiveContains(expectation.answer),
                "\(expectation.id) must expose a direct answer. Label: \(label)"
            )
            XCTAssertTrue(
                label.contains("View details: \(expectation.destination)"),
                "\(expectation.id) must name its detail destination. Label: \(label)"
            )
        }

        let quality = app.descendants(matching: .any)["analytics.category.quality"].firstMatch
        scrollUntilFullyVisibleAboveSystemChrome(quality, in: app)
        XCTAssertTrue(isFullyVisibleAboveSystemChrome(quality, in: app))
        try capture("iphone-analytics-questions-bottom", app: app)

        let periodFilter = app.descendants(matching: .any)["analytics.periodFilter"].firstMatch
        scrollUntilHittable(periodFilter, direction: .down, in: app)
        XCTAssertTrue(periodFilter.waitForExistence(timeout: 5) && periodFilter.isHittable)
        XCTAssertTrue(app.segmentedControls.buttons["Day"].firstMatch.isSelected)
        try capture("iphone-analytics-questions-top", app: app)

        let time = app.descendants(matching: .any)["analytics.category.time"].firstMatch
        scrollUntilHittable(time, direction: .down, in: app)
        XCTAssertTrue(time.waitForExistence(timeout: 5) && time.isHittable)
        activate(time)

        let detail = app.descendants(matching: .any)["analytics.categoryDetail.time"].firstMatch
        let distribution = app.descendants(matching: .any)[
            "analytics.hourDistribution.content"
        ].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        XCTAssertTrue(distribution.waitForExistence(timeout: 8))
        try capture("iphone-analytics-time-details", app: app)
        #endif
    }

    @MainActor
    func testAnalyticsFocusRoundsAndForecastsRespectSelectedPeriod() throws {
        #if os(macOS)
        throw XCTSkip("Analytics period evidence requires an iOS simulator.")
        #else
        let app = launchApp(route: "analytics")
        if app.descendants(matching: .any)["analytics.view"]
            .waitForExistence(timeout: 5) == false {
            openSection(
                "Analytics",
                tabIdentifier: "phone.tab.analytics",
                sidebarIdentifier: "sidebar.Analytics",
                in: app
            )
        }
        XCTAssertTrue(analyticsIsReady(in: app))

        let focusRounds = app.descendants(matching: .any)[
            "analytics.category.pomodoro"
        ].firstMatch
        scrollUntilHittable(focusRounds, direction: .up, in: app)
        XCTAssertTrue(focusRounds.waitForExistence(timeout: 5) && focusRounds.isHittable)
        activate(focusRounds)

        let focusDetail = app.descendants(matching: .any)[
            "analytics.categoryDetail.pomodoro"
        ].firstMatch
        let focusSummary = app.descendants(matching: .any)[
            "analytics.focusRounds.summary"
        ].firstMatch
        XCTAssertTrue(focusDetail.waitForExistence(timeout: 8))
        XCTAssertTrue(focusSummary.waitForExistence(timeout: 8))
        let reconciledFocusRounds = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "latest 2 of 2"),
            object: focusSummary
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [reconciledFocusRounds], timeout: 5),
            .completed,
            "The expired demo focus must reconcile before Analytics presents completed rounds. Label: \(focusSummary.label)"
        )
        try capture("iphone-analytics-current-focus-rounds", app: app)

        let firstBackButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(firstBackButton.waitForExistence(timeout: 3) && firstBackButton.isHittable)
        activate(firstBackButton)
        XCTAssertTrue(
            app.descendants(matching: .any)["analytics.view"]
                .waitForExistence(timeout: 8)
        )

        let decisions = app.descendants(matching: .any)[
            "analytics.category.decisions"
        ].firstMatch
        scrollUntilHittable(decisions, direction: .up, in: app)
        XCTAssertTrue(decisions.waitForExistence(timeout: 5) && decisions.isHittable)
        activate(decisions)

        let decisionsDetail = app.descendants(matching: .any)[
            "analytics.categoryDetail.decisions"
        ].firstMatch
        let currentForecasts = app.staticTexts["Current Task Forecasts"].firstMatch
        XCTAssertTrue(decisionsDetail.waitForExistence(timeout: 8))
        scrollUntilHittable(currentForecasts, direction: .up, in: app)
        XCTAssertTrue(
            currentForecasts.waitForExistence(timeout: 5) && currentForecasts.isHittable,
            "The current Analytics period must disclose its live task forecasts."
        )
        try capture("iphone-analytics-current-task-forecasts", app: app)

        let secondBackButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(secondBackButton.waitForExistence(timeout: 3) && secondBackButton.isHittable)
        activate(secondBackButton)
        XCTAssertTrue(
            app.descendants(matching: .any)["analytics.view"]
                .waitForExistence(timeout: 8)
        )

        let periodFilter = app.descendants(matching: .any)["analytics.periodFilter"].firstMatch
        scrollUntilHittable(periodFilter, direction: .down, in: app)
        XCTAssertTrue(periodFilter.waitForExistence(timeout: 5))
        let previous = app.buttons["analytics.period.previous"].firstMatch
        let next = app.buttons["analytics.period.next"].firstMatch
        XCTAssertTrue(previous.waitForExistence(timeout: 5) && previous.isHittable)
        activate(previous)

        let nextEnabledExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: next
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [nextEnabledExpectation], timeout: 5),
            .completed
        )

        scrollUntilHittable(decisions, direction: .up, in: app)
        XCTAssertTrue(decisions.waitForExistence(timeout: 5) && decisions.isHittable)
        activate(decisions)
        XCTAssertTrue(decisionsDetail.waitForExistence(timeout: 8))
        let historicalDecisionSummary = app.descendants(matching: .any)[
            "analytics.decisionSummary"
        ].firstMatch
        XCTAssertTrue(
            historicalDecisionSummary.waitForExistence(timeout: 8),
            "Historical review signals must finish loading before forecast visibility is checked."
        )
        XCTAssertFalse(
            app.staticTexts["Current Task Forecasts"].exists,
            "A historical Analytics period must not present current forecasts as historical evidence."
        )
        try capture("iphone-analytics-historical-review-signals", app: app)
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
    func testHomeAndAnalyticsShareReadableTimelineVisuals() throws {
        let app = launchApp()

        XCTAssertTrue(homeIsReady(in: app))
        let homeTimeline = app.descendants(matching: .any)["home.timeline"].firstMatch
        scrollUntilHittable(homeTimeline, direction: .up, in: app)
        XCTAssertTrue(homeTimeline.waitForExistence(timeout: 5) && homeTimeline.isHittable)
        #if os(macOS)
        try capture("mac-home-centered-timeline", app: app)
        #else
        try capture("iphone-home-centered-timeline", app: app)
        #endif

        app.terminate()
        let analyticsApp = launchApp(route: "analytics")
        XCTAssertTrue(analyticsIsReady(in: analyticsApp))

        let time = analyticsApp.descendants(matching: .any)[
            "analytics.category.time"
        ].firstMatch
        scrollUntilHittable(time, direction: .up, in: analyticsApp)
        XCTAssertTrue(time.waitForExistence(timeout: 5) && time.isHittable)
        activate(time)

        let detail = analyticsApp.descendants(matching: .any)[
            "analytics.categoryDetail.time"
        ].firstMatch
        let analyticsTimeline = analyticsApp.descendants(matching: .any)[
            "analytics.timeline.section"
        ].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        scrollUntilHittable(
            analyticsTimeline,
            direction: .up,
            in: analyticsApp
        )
        XCTAssertTrue(
            analyticsTimeline.waitForExistence(timeout: 5) &&
                analyticsTimeline.isHittable
        )
        scroll(
            direction: .up,
            toward: analyticsTimeline,
            in: analyticsApp
        )
        #if os(macOS)
        try capture("mac-analytics-centered-timeline", app: analyticsApp)
        #else
        try capture("iphone-analytics-centered-timeline", app: analyticsApp)
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

        let quickStartHeading = app.staticTexts["Quick Start"].firstMatch
        scrollTodayUntilHittable(quickStartHeading, in: app)
        XCTAssertTrue(
            waitForElement(
                quickStartHeading,
                timeout: 5,
                diagnosticName: "quick-start-heading",
                in: app
            ) && quickStartHeading.isHittable
        )

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
        scrollTodayUntilHittable(root, in: app)
        XCTAssertTrue(
            waitForElement(
                root,
                timeout: 5,
                diagnosticName: "quick-start-root",
                in: app
            )
        )
        scrollTodayUntilHittable(child, in: app)
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

        XCTAssertTrue(child.isHittable)
        let childTimerAction = app.buttons[
            "home.quickStart.timer.\(child.identifier.replacingOccurrences(of: "home.quickStart.task.", with: ""))"
        ].firstMatch
        XCTAssertTrue(childTimerAction.waitForExistence(timeout: 5) && childTimerAction.isHittable)
        #if os(iOS)
        let usesIPadShell = app.descendants(matching: .any)["ipad.splitNavigation"]
            .waitForExistence(timeout: 1)
        if usesIPadShell {
            XCTAssertGreaterThan(
                childTimerAction.frame.width,
                childTimerAction.frame.height + 8,
                "iPad must preserve the visible Start label."
            )
        } else {
            XCTAssertEqual(
                childTimerAction.frame.width,
                childTimerAction.frame.height,
                accuracy: 3,
                "iPhone must use a centered square Start icon button."
            )
        }
        #endif
        try capture("quick-start-separate-actions-ready", app: app)
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
        XCTAssertEqual(
            stopAction.frame.height,
            child.frame.height,
            accuracy: 4,
            "The timer action and task target should stay visually aligned."
        )
        XCTAssertEqual(
            stopAction.frame.midY,
            child.frame.midY,
            accuracy: 4,
            "The timer action and task target should share a vertical center."
        )
        XCTAssertGreaterThan(
            stopAction.frame.minX,
            child.frame.maxX,
            "Navigation and timer actions must remain separate hit targets."
        )
        #if os(iOS)
        if usesIPadShell {
            XCTAssertGreaterThan(
                stopAction.frame.width,
                stopAction.frame.height + 8,
                "iPad must preserve the visible Stop label."
            )
        } else {
            XCTAssertEqual(
                stopAction.frame.width,
                stopAction.frame.height,
                accuracy: 3,
                "iPhone must use a centered square Stop icon button."
            )
        }
        #endif
        activate(stopAction)
        let stopped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Time Tracker App"),
            object: child
        )
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 5), .completed)

        #if os(macOS)
        return
        #else
        guard usesIPadShell == false else { return }

        let edit = app.buttons["home.quickStart.edit"].firstMatch
        scrollTodayUntilHittable(edit, in: app)
        XCTAssertTrue(edit.waitForExistence(timeout: 3) && edit.isHittable)
        activate(edit)

        XCTAssertTrue(app.navigationBars["Edit Quick Start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Time Tracker App"].waitForExistence(timeout: 3))
        try capture("quick-start-editor-task-identity", app: app)
        #endif
    }

    @MainActor
    func testRunningQuickStartOpensTaskDetailInsteadOfStopping() throws {
        #if os(macOS)
        throw XCTSkip("The phone Quick Start interaction requires an iOS simulator.")
        #else
        let app = launchApp()
        XCTAssertTrue(homeIsReady(in: app))
        if app.descendants(matching: .any)["ipad.splitNavigation"]
            .waitForExistence(timeout: 1) {
            throw XCTSkip("The compact Quick Start action is verified on iPhone.")
        }

        let child = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "home.quickStart.task."
            )
        ).matching(
            NSPredicate(format: "label == %@", "Design System")
        ).firstMatch
        scrollTodayUntilHittable(child, in: app)
        XCTAssertTrue(child.waitForExistence(timeout: 5) && child.isHittable)

        let childTimerAction = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "home.quickStart.timer."
            )
        ).matching(
            NSPredicate(format: "label == %@", "Start Design System")
        ).firstMatch
        scrollTodayUntilHittable(childTimerAction, in: app)
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

        let todayBack = app.navigationBars.buttons["Today"].firstMatch
        XCTAssertTrue(
            waitForElement(
                todayBack,
                timeout: 5,
                diagnosticName: "quick-start-detail-today-back",
                in: app
            ) && todayBack.isHittable,
            "A task opened from Today must return to Today."
        )
        activate(todayBack)
        XCTAssertTrue(homeIsReady(in: app))
        let phoneTabView = app.descendants(matching: .any)["phone.tabView"].firstMatch
        if phoneTabView.exists {
            XCTAssertTrue(
                app.descendants(matching: .any)["phone.tab.today"].firstMatch.isSelected
            )
        }
        XCTAssertFalse(app.descendants(matching: .any)["tasks.view"].exists)
        try capture("quick-start-detail-returned-to-today", app: app)
        #endif
    }

    @MainActor
    func testTodayQuickStartTaskReturnsToToday() throws {
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
        scrollTodayUntilHittable(child, in: app)
        XCTAssertTrue(
            waitForElement(
                child,
                timeout: 5,
                diagnosticName: "today-quick-start-task",
                in: app
            ) && child.isHittable
        )

        #if os(iOS)
        let usesIPadShell = app.descendants(matching: .any)["ipad.splitNavigation"]
            .waitForExistence(timeout: 1)
        #endif

        activate(child)
        XCTAssertTrue(taskDetailIsReady(in: app))
        XCTAssertTrue(app.staticTexts["Design System"].waitForExistence(timeout: 3))
        try capture("today-quick-start-task-detail", app: app)

        let more = app.descendants(matching: .any)["task.detail.more"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 3) && more.isHittable)
        activate(more)
        let contextEdit = app.descendants(matching: .any)["task.context.edit"].firstMatch
        XCTAssertTrue(contextEdit.waitForExistence(timeout: 3) && contextEdit.isHittable)
        activate(contextEdit)

        let editor = app.descendants(matching: .any)["task.editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["tasks.view"].exists)
        try capture("today-quick-start-context-edit", app: app)
        let save = app.buttons["task.editor.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 3) && save.isHittable)
        activate(save)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        XCTAssertTrue(taskDetailIsReady(in: app))
        XCTAssertFalse(app.descendants(matching: .any)["tasks.view"].exists)

        #if os(macOS)
        let todayBack = app.buttons["Back"].firstMatch
        #else
        let todayBack = app.navigationBars.buttons["Today"].firstMatch
        #endif
        XCTAssertTrue(
            waitForElement(
                todayBack,
                timeout: 5,
                diagnosticName: "today-quick-start-source-back",
                in: app
            ) && todayBack.isHittable,
            "A task opened from Today must expose the source stack's back action."
        )
        activate(todayBack)

        XCTAssertTrue(homeIsReady(in: app))
        #if os(iOS)
        if usesIPadShell == false {
            XCTAssertTrue(
                app.descendants(matching: .any)["phone.tab.today"].firstMatch.isSelected
            )
        }
        #endif
        XCTAssertFalse(app.descendants(matching: .any)["tasks.view"].exists)
        try capture("today-quick-start-returned-to-today", app: app)
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
    func testTaskRowsSeparateIdentityProgressAndTimerMetadataAtNormalTextSize() throws {
        #if os(macOS)
        throw XCTSkip("The task-row geometry is verified on iPhone and iPad.")
        #else
        let app = launchApp(
            route: "tasks",
            replacesDemoDataOnLaunch: true
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["tasks.view"]
                .waitForExistence(timeout: 8)
        )

        for title in ["Time Tracker App", "Design System"] {
            let disclosure = app.buttons
                .matching(NSPredicate(
                    format: "identifier BEGINSWITH %@ AND value == %@",
                    "tasks.disclosure.",
                    title
                ))
                .firstMatch
            XCTAssertTrue(
                waitForElement(
                    disclosure,
                    timeout: 5,
                    diagnosticName: "task-row-disclosure-\(title)",
                    in: app
                ) && disclosure.isHittable
            )
            activate(disclosure)
        }

        let checklistRow = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "tasks.row.",
                "Design macOS UI"
            ))
            .firstMatch
        XCTAssertTrue(
            waitForElement(
                checklistRow,
                timeout: 5,
                diagnosticName: "task-row-checklist-metadata",
                in: app
            ) && checklistRow.isHittable
        )
        let checklistValue = (checklistRow.value as? String ?? "").lowercased()
        XCTAssertTrue(checklistValue.contains("2/3"))
        XCTAssertTrue(checklistValue.contains("worked"))
        XCTAssertFalse(checklistValue.contains("stop"))
        try capture("task-row-checklist-metadata", app: app)

        let studyDisclosure = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND value == %@",
                "tasks.disclosure.",
                "Study"
            ))
            .firstMatch
        scrollUntilHittable(studyDisclosure, direction: .up, in: app)
        XCTAssertTrue(
            waitForElement(
                studyDisclosure,
                timeout: 5,
                diagnosticName: "task-row-study-disclosure",
                in: app
            ) && studyDisclosure.isHittable
        )
        activate(studyDisclosure)

        let runningRow = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "tasks.row.",
                "Read Apple HIG"
            ))
            .firstMatch
        scrollUntilHittable(runningRow, direction: .up, in: app)
        XCTAssertTrue(
            waitForElement(
                runningRow,
                timeout: 5,
                diagnosticName: "task-row-running-metadata",
                in: app
            ) && runningRow.isHittable
        )
        let runningValue = (runningRow.value as? String ?? "").lowercased()
        XCTAssertTrue(runningValue.contains("running"))
        XCTAssertTrue(runningValue.contains("worked"))
        XCTAssertFalse(runningValue.contains("stop"))
        try capture("task-row-running-icon-metadata", app: app)

        let addTaskMenu = app.descendants(matching: .any)["tasks.add"].firstMatch
        XCTAssertTrue(addTaskMenu.waitForExistence(timeout: 3) && addTaskMenu.isHittable)
        activate(addTaskMenu)
        let addRootTask = app.descendants(matching: .any)["tasks.addRoot"].firstMatch
        XCTAssertTrue(addRootTask.waitForExistence(timeout: 3) && addRootTask.isHittable)
        activate(addRootTask)

        let editor = app.descendants(matching: .any)["task.editor"].firstMatch
        let titleField = app.descendants(matching: .any)[
            "task.editor.title.field"
        ].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(titleField.waitForExistence(timeout: 3) && titleField.isHittable)
        let longTitle = """
        Review the complete interaction hierarchy for every task surface \
        while keeping the task name readable before checklist and timing metadata
        """
        titleField.typeText(longTitle)
        titleField.typeText(XCUIKeyboardKey.return.rawValue)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        let save = app.buttons["task.editor.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 3) && save.isHittable)
        activate(save)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))

        let longRow = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "tasks.row.",
                longTitle
            ))
            .firstMatch
        scrollUntilHittable(longRow, direction: .up, in: app)
        XCTAssertTrue(longRow.waitForExistence(timeout: 5) && longRow.isHittable)

        let ordinaryRow = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "tasks.row.",
                "Standalone Task"
            ))
            .firstMatch
        scrollUntilHittable(ordinaryRow, direction: .down, in: app)
        XCTAssertTrue(ordinaryRow.waitForExistence(timeout: 5) && ordinaryRow.isHittable)
        let ordinaryRowHeight = ordinaryRow.frame.height
        scrollUntilHittable(longRow, direction: .up, in: app)
        XCTAssertGreaterThan(
            longRow.frame.height,
            ordinaryRowHeight + 8,
            "A long task title must wrap instead of competing with metadata."
        )
        try capture("task-row-long-title-wrapped", app: app)
        #endif
    }

    @MainActor
    func testTimerPickerRunningRowsExposeStopWithoutDuplicateRunningBadge() throws {
        #if os(macOS)
        throw XCTSkip("The compact timer-picker action grammar is verified on iOS.")
        #else
        let app = launchApp(replacesDemoDataOnLaunch: true)
        XCTAssertTrue(homeIsReady(in: app))

        let startTimer = app.buttons["home.startTimer"].firstMatch
        scrollUntilHittable(startTimer, direction: .up, in: app)
        XCTAssertTrue(startTimer.waitForExistence(timeout: 5) && startTimer.isHittable)
        activate(startTimer)

        let picker = app.descendants(matching: .any)["timer.taskPicker"].firstMatch
        XCTAssertTrue(
            waitForElement(
                picker,
                timeout: 5,
                diagnosticName: "timer-picker-stop-only",
                in: app
            )
        )
        let guideStop = picker.buttons["Stop Read Apple HIG"].firstMatch
        let runningHeader = app.staticTexts[
            "timer.taskPicker.runningHeader"
        ].firstMatch
        XCTAssertTrue(runningHeader.waitForExistence(timeout: 5))
        XCTAssertTrue(guideStop.waitForExistence(timeout: 5))

        let stopButtons = picker.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@",
            "timer.taskPicker.stop."
        ))
        XCTAssertGreaterThanOrEqual(stopButtons.count, 1)
        for index in 0..<stopButtons.count {
            let stop = stopButtons.element(boundBy: index)
            XCTAssertTrue(stop.isHittable)
            XCTAssertGreaterThanOrEqual(stop.frame.width, 44)
            XCTAssertGreaterThanOrEqual(stop.frame.height, 44)
        }
        let runningRows = picker.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "timer.taskPicker.running."
            )
        )
        XCTAssertEqual(
            runningRows.count,
            stopButtons.count,
            "Each active task must expose one passive summary and one explicit Stop action."
        )
        for index in 0..<runningRows.count {
            let runningRow = runningRows.element(boundBy: index)
            let value = (runningRow.value as? String ?? "").lowercased()
            XCTAssertFalse(
                value.contains("running"),
                "The Running Timers section owns status context; row values must not repeat it."
            )
        }
        try capture("timer-picker-stop-without-running-badge", app: app)

        XCTAssertTrue(guideStop.isHittable)
        activate(guideStop)
        XCTAssertTrue(guideStop.waitForNonExistence(timeout: 5))
        XCTAssertTrue(picker.exists)

        let search = app.searchFields[
            "Search tasks, paths, or notes"
        ].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3) && search.isHittable)
        activate(search)
        search.typeText("Read Apple HIG")
        let stoppedTask = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "timer.taskPicker.select.",
                "Read Apple HIG"
            ))
            .firstMatch
        XCTAssertTrue(
            waitForElement(
                stoppedTask,
                timeout: 5,
                diagnosticName: "timer-picker-stopped-task-selectable",
                in: app
            ) && stoppedTask.isHittable
        )
        try capture("timer-picker-stopped-task-selectable", app: app)
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
    func testIPadTodayUsesNativeTitleAndUnindentedRootLeaf() throws {
        #if os(macOS)
        throw XCTSkip("The native iPad shell requires an iOS simulator.")
        #else
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchApp()
        guard app.descendants(matching: .any)["ipad.splitNavigation"]
            .waitForExistence(timeout: 5) else {
            throw XCTSkip("This shell audit only runs on iPad.")
        }
        XCTAssertTrue(homeIsReady(in: app))

        let navigationBar = app.navigationBars["Today"].firstMatch
        XCTAssertTrue(
            navigationBar.waitForExistence(timeout: 5),
            "Today must use a native navigation title on iPad."
        )
        let expandedHeight = navigationBar.frame.height
        try capture("ipad-today-native-title-expanded", app: app)

        let home = app.descendants(matching: .any)["home.view"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 3))
        for _ in 0..<3 where navigationBar.frame.height >= expandedHeight - 12 {
            home.swipeUp()
        }
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 3))
        XCTAssertLessThan(
            navigationBar.frame.height,
            expandedHeight - 12,
            "The large Today title must collapse into the top navigation bar while scrolling."
        )
        XCTAssertTrue(navigationBar.staticTexts["Today"].firstMatch.exists)
        try capture("ipad-today-native-title-collapsed", app: app)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.descendants(matching: .any)["ipad.splitNavigation"].waitForExistence(timeout: 3))

        let rootLeaf = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "sidebar.task.",
                "Standalone Task"
            ))
            .firstMatch
        if !rootLeaf.waitForExistence(timeout: 2) {
            let systemToggle = app.buttons["Show Sidebar"].firstMatch
            if systemToggle.waitForExistence(timeout: 2), systemToggle.isHittable {
                activate(systemToggle)
            }
        }
        XCTAssertTrue(rootLeaf.waitForExistence(timeout: 5) && rootLeaf.isHittable)

        let rootDisclosure = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
                "sidebar.disclosure.",
                "Time Tracker App"
            ))
            .firstMatch
        XCTAssertTrue(
            rootDisclosure.waitForExistence(timeout: 3) && rootDisclosure.isHittable
        )
        XCTAssertGreaterThanOrEqual(rootDisclosure.frame.width, 44)
        XCTAssertGreaterThanOrEqual(rootDisclosure.frame.height, 44)
        XCTAssertLessThanOrEqual(
            rootLeaf.frame.minX,
            rootDisclosure.frame.minX - 12,
            "A root leaf must start at the list edge instead of reserving an empty disclosure slot."
        )

        let studyDisclosure = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
                "sidebar.disclosure.",
                "Study"
            ))
            .firstMatch
        XCTAssertTrue(
            studyDisclosure.waitForExistence(timeout: 3) && studyDisclosure.isHittable
        )
        activate(studyDisclosure)

        let nestedLeaf = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "sidebar.task.",
                "Read Apple HIG"
            ))
            .firstMatch
        XCTAssertTrue(nestedLeaf.waitForExistence(timeout: 3) && nestedLeaf.isHittable)
        try capture("ipad-sidebar-root-and-nested-alignment", app: app)
        #endif
    }

    @MainActor
    private func launchApp(
        route: String = "today",
        contentSizeCategory: String? = nil,
        seedsDemoData: Bool = true,
        replacesDemoDataOnLaunch: Bool = false,
        additionalLaunchArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let demoDataMode: String
        if seedsDemoData == false {
            demoDataMode = "off"
        } else if replacesDemoDataOnLaunch {
            demoDataMode = "replaceOnLaunch"
        } else {
            demoDataMode = "seedIfEmpty"
        }
        app.launchArguments = [
            "--uitesting",
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-TimeTrackerAutomaticDemoDataModeOverride",
            demoDataMode,
            "-TimeTrackerAutomaticDemoSeedingDisabled",
            seedsDemoData ? "NO" : "YES"
        ]
        app.launchArguments.append(contentsOf: additionalLaunchArguments)
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
            scroll(direction: direction, toward: element, in: app)
        }
    }

    @MainActor
    private func scrollTodayUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) {
        let home = app.descendants(matching: .any)["home.view"].firstMatch
        guard home.waitForExistence(timeout: 3) else {
            scrollUntilHittable(element, direction: .up, in: app)
            return
        }

        for _ in 0..<6 where !element.isHittable {
            #if os(macOS)
            scroll(direction: .up, toward: element, in: app)
            #else
            home.swipeUp()
            #endif
        }
    }

    @MainActor
    private func scroll(
        direction: ScrollDirection,
        toward element: XCUIElement,
        in app: XCUIApplication
    ) {
        #if os(macOS)
        let targetX = element.exists
            ? element.frame.midX
            : app.windows.firstMatch.frame.midX
        let targetScrollView = app.scrollViews.allElementsBoundByIndex
            .filter { scrollView in
                let frame = scrollView.frame
                return frame.width > 0 &&
                    frame.minX <= targetX &&
                    frame.maxX >= targetX
            }
            .min { $0.frame.width < $1.frame.width }
            ?? app.scrollViews.firstMatch
        let deltaY: CGFloat = direction == .up ? -420 : 420
        targetScrollView.scroll(byDeltaX: 0, deltaY: deltaY)
        #else
        switch direction {
        case .up:
            app.swipeUp()
        case .down:
            app.swipeDown()
        }
        #endif
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
    private func discardDialogButton(
        identifier: String,
        localizedLabels: [String],
        in app: XCUIApplication
    ) -> XCUIElement {
        let identifiedButton = app.buttons[identifier].firstMatch
        let deadline = Date().addingTimeInterval(3)
        repeat {
            if identifiedButton.exists, identifiedButton.isHittable {
                return identifiedButton
            }

            for label in localizedLabels {
                let matchingButtons = app.buttons
                    .matching(NSPredicate(format: "label == %@", label))
                    .allElementsBoundByIndex
                if let button = matchingButtons.first(where: \.isHittable) {
                    return button
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        if identifiedButton.exists {
            return identifiedButton
        }

        for label in localizedLabels {
            let button = app.buttons[label].firstMatch
            if button.exists {
                return button
            }
        }

        return identifiedButton
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

    @MainActor
    private func waitUntil(
        timeout: TimeInterval,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }
}
