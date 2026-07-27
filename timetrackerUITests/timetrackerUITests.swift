import XCTest
#if os(macOS)
import AppKit
#endif

final class timetrackerUITests: XCTestCase {
    private enum ScrollDirection {
        case up
        case down
    }

    private struct InboxUITestItem {
        let id: String
        let menu: XCUIElement
        let titleField: XCUIElement
    }

    private struct LiveLLMUITestConfiguration {
        let endpoint: String
        let apiKey: String
        let modelID: String
    }

    private enum LiveLLMUITestConfigurationError: Error {
        case emptyValue
    }

    private var screenshotRunDirectoryURL: URL?

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
        let root = try liveLLMUIScreenshotDirectoryURL() ??
            FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]
            .appendingPathComponent("UITestScreenshots", isDirectory: true)
        let testDirectoryName = name.map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let testDirectory = root.appendingPathComponent(
            String(testDirectoryName),
            isDirectory: true
        )
        if FileManager.default.fileExists(atPath: testDirectory.path) {
            try FileManager.default.removeItem(at: testDirectory)
        }
        try FileManager.default.createDirectory(
            at: testDirectory,
            withIntermediateDirectories: true
        )
        screenshotRunDirectoryURL = testDirectory
        #endif
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    @MainActor
    func testLaunchSmokeShowsHome() {
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
        #if os(macOS)
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.category.general"]
                .waitForExistence(timeout: 3)
        )
        let settingsWindow = try XCTUnwrap(
            app.windows.allElementsBoundByIndex.first { window in
                window.descendants(matching: .any)["settings.category.general"].exists
            }
        )
        let generalCategory = settingsWindow.descendants(matching: .any)
            .matching(identifier: "settings.category.general")
            .firstMatch
        XCTAssertTrue(generalCategory.exists && generalCategory.isHittable)
        XCTAssertFalse(settingsWindow.buttons["Show Sidebar"].exists)
        XCTAssertFalse(settingsWindow.buttons["Hide Sidebar"].exists)
        try recordScreenshot(
            settingsWindow.screenshot(),
            name: "mac-settings-fixed-sidebar"
        )
        #endif
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
    func testTaskCategoryDisclosureCollapsesAndRestoresHierarchy() throws {
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif
        let app = launchApp(
            route: "tasks",
            replacesDemoDataOnLaunch: true
        )
        #if os(macOS)
        try placeMainWindowOnPrimaryScreen(in: app)
        #endif
        XCTAssertTrue(
            app.descendants(matching: .any)["tasks.view"]
                .waitForExistence(timeout: 8)
        )

        let workDisclosure = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "tasks.category.disclosure.",
                "Work"
            )
        ).firstMatch
        let studyDisclosure = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "tasks.category.disclosure.",
                "Study"
            )
        ).firstMatch
        let workRoot = taskRow(named: "Time Tracker App", in: app)
        let workChild = taskRow(named: "Design System", in: app)

        scrollUntilHittable(
            workDisclosure,
            direction: .down,
            maximumScrolls: 8,
            in: app
        )
        XCTAssertTrue(
            workDisclosure.waitForExistence(timeout: 5) &&
                workDisclosure.isHittable,
            "A non-empty Category must expose an actionable disclosure."
        )
        XCTAssertTrue(workRoot.waitForExistence(timeout: 5))
        let rootIdentifierPrefix = "tasks.row."
        XCTAssertTrue(workRoot.identifier.hasPrefix(rootIdentifierPrefix))
        let rootTaskID = workRoot.identifier.dropFirst(rootIdentifierPrefix.count)
        let rootDisclosure = app.buttons[
            "tasks.disclosure.\(rootTaskID)"
        ].firstMatch
        XCTAssertTrue(
            rootDisclosure.waitForExistence(timeout: 5) &&
                rootDisclosure.isHittable
        )
        activate(rootDisclosure)
        XCTAssertTrue(
            workChild.waitForExistence(timeout: 5),
            "The fixture must expose Category → root task → child task."
        )

        scrollUntilHittable(
            workDisclosure,
            direction: .down,
            maximumScrolls: 8,
            in: app
        )
        XCTAssertTrue(workDisclosure.isHittable)
        let prefix = platformScreenshotPrefix(in: app)
        try capture("\(prefix)-tasks-category-expanded", app: app)

        let sectionID = workDisclosure.identifier.dropFirst(
            "tasks.category.disclosure.".count
        )
        let workActions = app.descendants(matching: .any)[
            "tasks.category.actions.\(sectionID)"
        ].firstMatch
        activate(workDisclosure)
        XCTAssertTrue(
            workRoot.waitForNonExistence(timeout: 5),
            "Collapsing Work must hide its root tasks."
        )
        XCTAssertTrue(
            workChild.waitForNonExistence(timeout: 5),
            "Collapsing Work must hide its expanded descendants."
        )
        XCTAssertTrue(workDisclosure.exists)
        XCTAssertTrue(workActions.waitForExistence(timeout: 3))
        XCTAssertTrue(
            studyDisclosure.waitForExistence(timeout: 5),
            "Collapsing one Category must leave the other Category available."
        )
        waitForScreenshotTransition()
        try capture("\(prefix)-tasks-category-collapsed", app: app)

        XCTAssertTrue(workDisclosure.isHittable)
        activate(workDisclosure)
        XCTAssertTrue(workRoot.waitForExistence(timeout: 5))
        XCTAssertTrue(
            workChild.waitForExistence(timeout: 5),
            "Re-expanding Work must preserve the nested task expansion state."
        )
        waitForScreenshotTransition()
        try capture("\(prefix)-tasks-category-restored", app: app)

        #if os(iOS)
        if prefix == "ipad" {
            XCUIDevice.shared.orientation = .landscapeLeft
            waitForScreenshotTransition()
            scrollUntilHittable(
                workDisclosure,
                direction: .down,
                maximumScrolls: 8,
                in: app
            )
            XCTAssertTrue(workDisclosure.isHittable && workChild.exists)
            try capture(
                "ipad-tasks-category-restored-landscape",
                app: app
            )
        }
        #endif

        scrollUntilHittable(workChild, direction: .up, in: app)
        XCTAssertTrue(workChild.isHittable)
        activate(workChild)
        XCTAssertTrue(
            app.descendants(matching: .any)["task.detail"]
                .waitForExistence(timeout: 8),
            "Category disclosure must not break task navigation."
        )
    }

    @MainActor
    func testSidebarCategoryDisclosurePreservesHierarchyAndAutoExpandsCurrentTask() throws {
        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif

        let app = launchApp(
            route: "tasks",
            replacesDemoDataOnLaunch: true
        )
        #if os(macOS)
        try placeMainWindowOnPrimaryScreen(in: app)
        #endif
        XCTAssertTrue(
            app.descendants(matching: .any)["tasks.view"]
                .waitForExistence(timeout: 8)
        )

        let prefix = platformScreenshotPrefix(in: app)
        #if os(iOS)
        guard prefix == "ipad" else {
            throw XCTSkip("The persistent Sidebar is verified on iPad and macOS.")
        }
        #endif

        let mainWorkDisclosure = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "tasks.category.disclosure.",
                "Work"
            )
        ).firstMatch
        scrollUntilHittable(
            mainWorkDisclosure,
            direction: .down,
            maximumScrolls: 8,
            in: app
        )
        XCTAssertTrue(
            mainWorkDisclosure.waitForExistence(timeout: 5) &&
                mainWorkDisclosure.isHittable
        )
        let sectionID = mainWorkDisclosure.identifier.dropFirst(
            "tasks.category.disclosure.".count
        )
        let sidebarCategory = app.descendants(matching: .any)[
            "sidebar.category.disclosure.\(sectionID)"
        ].firstMatch

        if !sidebarCategory.waitForExistence(timeout: 2) ||
            !sidebarCategory.isHittable
        {
            let identifiedToggle = app.descendants(matching: .any)[
                "sidebar.show"
            ].firstMatch
            let systemToggle = app.buttons["Show Sidebar"].firstMatch
            if identifiedToggle.waitForExistence(timeout: 2),
               identifiedToggle.isHittable
            {
                activate(identifiedToggle)
            } else if systemToggle.waitForExistence(timeout: 2),
                      systemToggle.isHittable
            {
                activate(systemToggle)
            }
        }
        XCTAssertTrue(
            sidebarCategory.waitForExistence(timeout: 5) &&
                sidebarCategory.isHittable,
            "The Work Category must expose its native Sidebar disclosure header."
        )

        let sidebarRoot = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "sidebar.task.",
                "Time Tracker App"
            )
        ).firstMatch
        let sidebarRootDisclosure = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
                "sidebar.disclosure.",
                "Time Tracker App"
            )
        ).firstMatch
        let sidebarChild = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "sidebar.task.",
                "Design System"
            )
        ).firstMatch

        XCTAssertTrue(sidebarRoot.waitForExistence(timeout: 5))
        XCTAssertTrue(
            sidebarRootDisclosure.waitForExistence(timeout: 5) &&
                sidebarRootDisclosure.isHittable
        )
        activate(sidebarRootDisclosure)
        XCTAssertTrue(
            sidebarChild.waitForExistence(timeout: 5),
            "The Sidebar fixture must expose Category → root task → child task."
        )
        try capture("\(prefix)-sidebar-category-expanded", app: app)

        activate(sidebarCategory)
        XCTAssertTrue(
            sidebarRoot.waitForNonExistence(timeout: 5) &&
                sidebarChild.waitForNonExistence(timeout: 5),
            "Collapsing a Sidebar Category must hide its full task hierarchy."
        )
        let studyCategory = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "sidebar.category.disclosure.",
                "Study"
            )
        ).firstMatch
        XCTAssertTrue(
            studyCategory.waitForExistence(timeout: 5),
            "Collapsing Work must leave the Study Sidebar Category available."
        )
        let mainWorkRoot = taskRow(named: "Time Tracker App", in: app)
        XCTAssertTrue(
            mainWorkRoot.waitForExistence(timeout: 5),
            "Sidebar and Tasks-list Category expansion must stay independent."
        )
        waitForScreenshotTransition()
        try capture("\(prefix)-sidebar-category-collapsed", app: app)

        XCTAssertTrue(sidebarCategory.isHittable)
        activate(sidebarCategory)
        XCTAssertTrue(sidebarRoot.waitForExistence(timeout: 5))
        XCTAssertTrue(
            sidebarChild.waitForExistence(timeout: 5),
            "Re-expanding the Sidebar Category must preserve nested task expansion."
        )
        waitForScreenshotTransition()
        try capture("\(prefix)-sidebar-category-restored", app: app)

        activate(sidebarCategory)
        XCTAssertTrue(sidebarRoot.waitForNonExistence(timeout: 5))
        scrollUntilHittable(mainWorkRoot, direction: .up, in: app)
        XCTAssertTrue(mainWorkRoot.isHittable)
        activate(mainWorkRoot)
        XCTAssertTrue(
            app.descendants(matching: .any)["task.detail"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(
            sidebarRoot.waitForExistence(timeout: 5),
            "Navigating to a task must automatically reveal its collapsed Sidebar Category."
        )
        waitForScreenshotTransition()
        try capture("\(prefix)-sidebar-category-auto-expanded", app: app)
    }

    @MainActor
    func testTaskCategorySortingUpdatesTasksAndPersistentSidebarOrder() throws {
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif

        let app = launchApp(
            route: "tasks",
            replacesDemoDataOnLaunch: true
        )
        #if os(macOS)
        try placeMainWindowOnPrimaryScreen(in: app)
        #endif
        let screenshotPrefix = platformScreenshotPrefix(in: app)
        #if os(iOS)
        if screenshotPrefix == "ipad" {
            XCUIDevice.shared.orientation = .landscapeLeft
            waitForScreenshotTransition()
        }
        #endif

        let tasksView = app.descendants(matching: .any)[
            "tasks.view"
        ].firstMatch
        XCTAssertTrue(tasksView.waitForExistence(timeout: 8))

        let addMenu = app.descendants(matching: .any)[
            "tasks.add"
        ].firstMatch
        XCTAssertTrue(
            addMenu.waitForExistence(timeout: 5) && addMenu.isHittable
        )
        activate(addMenu)

        let sortCategories = app.descendants(matching: .any)[
            "tasks.sortCategories"
        ].firstMatch
        XCTAssertTrue(
            sortCategories.waitForExistence(timeout: 5) &&
                sortCategories.isHittable
        )
        activate(sortCategories)

        let sorter = app.descendants(matching: .any)[
            "taskCategory.sorter"
        ].firstMatch
        XCTAssertTrue(sorter.waitForExistence(timeout: 8))

        let workRow = taskCategorySortRow(
            named: "Work",
            in: sorter
        )
        let studyRow = taskCategorySortRow(
            named: "Study",
            in: sorter
        )
        XCTAssertTrue(
            workRow.waitForExistence(timeout: 5) && workRow.isHittable
        )
        XCTAssertTrue(
            studyRow.waitForExistence(timeout: 5) && studyRow.isHittable
        )
        XCTAssertLessThan(
            workRow.frame.minY,
            studyRow.frame.minY,
            "The deterministic demo must begin with Work before Study."
        )

        let workCategoryID = try taskCategoryID(fromSortRow: workRow)
        let studyCategoryID = try taskCategoryID(fromSortRow: studyRow)
        let studyMoveUp = sorter.descendants(matching: .any)[
            "taskCategory.sort.moveUp.\(studyCategoryID)"
        ].firstMatch
        let workMoveDown = sorter.descendants(matching: .any)[
            "taskCategory.sort.moveDown.\(workCategoryID)"
        ].firstMatch

        if studyMoveUp.waitForExistence(timeout: 3),
           studyMoveUp.isHittable
        {
            activate(studyMoveUp)
        } else {
            XCTAssertTrue(
                workMoveDown.waitForExistence(timeout: 3) &&
                    workMoveDown.isHittable,
                "The sorter must expose a semantic button for either equivalent move."
            )
            activate(workMoveDown)
        }

        let reorderedStudyRow = taskCategorySortRow(
            named: "Study",
            in: sorter
        )
        let reorderedWorkRow = taskCategorySortRow(
            named: "Work",
            in: sorter
        )
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                reorderedStudyRow.exists &&
                    reorderedWorkRow.exists &&
                    reorderedStudyRow.isHittable &&
                    reorderedWorkRow.isHittable &&
                    reorderedStudyRow.frame.minY <
                    reorderedWorkRow.frame.minY
            },
            "Moving Study up must immediately update the sorter order."
        )
        waitForScreenshotTransition()
        try capture(
            "\(screenshotPrefix)-task-category-sorter-study-first",
            app: app
        )

        let done = app.descendants(matching: .any)[
            "taskCategory.sort.done"
        ].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 3) && done.isHittable)
        activate(done)
        XCTAssertTrue(sorter.waitForNonExistence(timeout: 5))

        let studySectionID =
            "tasks.category.disclosure.category-\(studyCategoryID)"
        let workSectionID =
            "tasks.category.disclosure.category-\(workCategoryID)"
        let studySection = app.descendants(matching: .any)[
            studySectionID
        ].firstMatch
        XCTAssertTrue(
            studySection.waitForExistence(timeout: 8) &&
                studySection.isHittable
        )
        activate(studySection)

        let refreshedStudySection = app.descendants(matching: .any)[
            studySectionID
        ].firstMatch
        let refreshedWorkSection = app.descendants(matching: .any)[
            workSectionID
        ].firstMatch
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                refreshedStudySection.exists &&
                    refreshedWorkSection.exists &&
                    refreshedStudySection.isHittable &&
                    refreshedWorkSection.isHittable &&
                    refreshedStudySection.frame.minY <
                    refreshedWorkSection.frame.minY
            },
            "Tasks must render the persisted Study-before-Work Category order."
        )

        if screenshotPrefix == "ipad" || screenshotPrefix == "mac" {
            let studySidebarID =
                "sidebar.category.disclosure.category-\(studyCategoryID)"
            let workSidebarID =
                "sidebar.category.disclosure.category-\(workCategoryID)"
            var studySidebar = app.descendants(matching: .any)[
                studySidebarID
            ].firstMatch
            if !studySidebar.waitForExistence(timeout: 2) ||
                !studySidebar.isHittable
            {
                let identifiedToggle = app.descendants(matching: .any)[
                    "sidebar.show"
                ].firstMatch
                let systemToggle = app.buttons["Show Sidebar"].firstMatch
                if identifiedToggle.waitForExistence(timeout: 2),
                   identifiedToggle.isHittable
                {
                    activate(identifiedToggle)
                } else {
                    XCTAssertTrue(
                        systemToggle.waitForExistence(timeout: 3) &&
                            systemToggle.isHittable,
                        "A collapsed persistent Sidebar must expose a scriptable toggle."
                    )
                    activate(systemToggle)
                }
                studySidebar = app.descendants(matching: .any)[
                    studySidebarID
                ].firstMatch
            }
            XCTAssertTrue(
                studySidebar.waitForExistence(timeout: 5) &&
                    studySidebar.isHittable
            )
            activate(studySidebar)

            let refreshedStudySidebar = app.descendants(matching: .any)[
                studySidebarID
            ].firstMatch
            let refreshedWorkSidebar = app.descendants(matching: .any)[
                workSidebarID
            ].firstMatch
            XCTAssertTrue(
                waitUntil(timeout: 5) {
                    refreshedStudySidebar.exists &&
                        refreshedWorkSidebar.exists &&
                        refreshedStudySidebar.isHittable &&
                        refreshedWorkSidebar.isHittable &&
                        refreshedStudySidebar.frame.minY <
                        refreshedWorkSidebar.frame.minY
                },
                "The persistent Sidebar must mirror the Tasks Category order."
            )
        }

        waitForScreenshotTransition()
        try capture(
            "\(screenshotPrefix)-task-category-study-before-work",
            app: app
        )
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
    func testAnalyticsHistoryRecordReusesSegmentEditorForDeletion() throws {
        let app = launchApp(
            route: "analytics",
            replacesDemoDataOnLaunch: true
        )
        XCTAssertTrue(analyticsIsReady(in: app))

        let time = app.descendants(matching: .any)[
            "analytics.category.time"
        ].firstMatch
        scrollUntilHittable(time, direction: .up, in: app)
        XCTAssertTrue(time.waitForExistence(timeout: 5) && time.isHittable)
        activate(time)

        let detail = app.descendants(matching: .any)[
            "analytics.categoryDetail.time"
        ].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        let timeline = app.descendants(matching: .any)[
            "analytics.timeline.section"
        ].firstMatch
        scrollUntilHittable(
            timeline,
            direction: .up,
            maximumScrolls: 12,
            in: app
        )
        XCTAssertTrue(
            timeline.waitForExistence(timeout: 8) && timeline.isHittable
        )
        let record = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "analytics.timeline.entry.trackedSegment."
            )
        ).firstMatch
        scrollUntilHittable(
            record,
            direction: .up,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(record.waitForExistence(timeout: 8) && record.isHittable)
        XCTAssertEqual(record.elementType, .button)
        let deletedIdentifier = record.identifier
        activate(record)

        let editor = app.descendants(matching: .any)["segmentEditor.view"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        try capture(
            "\(platformScreenshotPrefix(in: app))-analytics-segment-editor",
            app: app
        )

        let delete = app.buttons["segmentEditor.delete"].firstMatch
        scrollUntilHittable(delete, direction: .up, in: app)
        XCTAssertTrue(delete.waitForExistence(timeout: 3) && delete.isHittable)
        activate(delete)
        let confirm = app.buttons["segmentEditor.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3) && confirm.isHittable)
        activate(confirm)

        XCTAssertTrue(editor.waitForNonExistence(timeout: 8))
        XCTAssertTrue(
            app.descendants(matching: .any)[deletedIdentifier]
                .waitForNonExistence(timeout: 8),
            "Deleting from Analytics must refresh the exact timeline record."
        )
    }

    @MainActor
    func testTaskDetailHistoryRecordReusesSegmentEditorForSaving() throws {
        let app = launchApp(
            route: "task-detail",
            replacesDemoDataOnLaunch: true,
            taskTitle: "Read Apple HIG"
        )
        XCTAssertTrue(taskDetailIsReady(in: app))

        let record = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "task.detail.history.trackedSegment."
            )
        ).firstMatch
        scrollUntilHittable(
            record,
            direction: .up,
            maximumScrolls: 24,
            in: app
        )
        XCTAssertTrue(record.waitForExistence(timeout: 8) && record.isHittable)
        XCTAssertEqual(record.elementType, .button)
        let recordIdentifier = record.identifier
        activate(record)

        let editor = app.descendants(matching: .any)["segmentEditor.view"]
        let note = app.descendants(matching: .any)["segmentEditor.note"]
            .firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(note.waitForExistence(timeout: 3) && note.isHittable)
        activate(note)
        note.typeKey("a", modifierFlags: .command)
        replaceText("Edited from Task Detail", in: note)
        activate(app.buttons["segmentEditor.save"].firstMatch)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 8))

        let refreshedRecord = app.buttons[recordIdentifier].firstMatch
        scrollUntilHittable(
            refreshedRecord,
            direction: .up,
            maximumScrolls: 24,
            in: app
        )
        XCTAssertTrue(
            refreshedRecord.waitForExistence(timeout: 8) &&
                refreshedRecord.isHittable
        )
        activate(refreshedRecord)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(
            note.value as? String ?? note.label,
            "Edited from Task Detail"
        )
        try capture(
            "\(platformScreenshotPrefix(in: app))-task-detail-segment-editor",
            app: app
        )
        activate(app.buttons["segmentEditor.cancel"].firstMatch)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
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
    func testTodayHeatmapSettingsReuseHierarchyPickerAndPersistSelection() throws {
        #if os(macOS)
        throw XCTSkip("The Today Heatmap navigation path is verified on iPhone and iPad.")
        #else
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchApp(
            route: "settings",
            replacesDemoDataOnLaunch: true
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.view"]
                .waitForExistence(timeout: 8)
        )
        let screenshotPrefix = app.windows.firstMatch.frame.width >= 700
            ? "ipad"
            : "iphone"

        let general = app.buttons["settings.category.general"].firstMatch
        XCTAssertTrue(
            waitForElement(
                general,
                timeout: 5,
                diagnosticName: "heatmap-settings-general",
                in: app
            ) && general.isHittable
        )
        activate(general)

        let heatmapSettings = app.descendants(matching: .any)[
            "settings.todayHeatmap.tasks"
        ].firstMatch
        scrollUntilHittable(heatmapSettings, direction: .up, in: app)
        XCTAssertTrue(
            waitForElement(
                heatmapSettings,
                timeout: 5,
                diagnosticName: "heatmap-settings-row",
                in: app
            ) && heatmapSettings.isHittable
        )
        XCTAssertEqual(heatmapSettings.value as? String, "Off")
        try capture("\(screenshotPrefix)-settings-today-heatmap-off", app: app)
        activate(heatmapSettings)

        let picker = app.descendants(matching: .any)[
            "settings.todayHeatmap.taskPicker"
        ].firstMatch
        XCTAssertTrue(
            waitForElement(
                picker,
                timeout: 5,
                diagnosticName: "heatmap-task-picker",
                in: app
            )
        )
        let choicePrefix = "settings.todayHeatmap.taskPicker.select."
        let choices = ["Time Tracker App", "Client Work"].map { title in
            app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                choicePrefix,
                title
            )).firstMatch
        }
        XCTAssertTrue(choices.allSatisfy {
            $0.waitForExistence(timeout: 3) && $0.isHittable
        })
        try capture(
            "\(screenshotPrefix)-settings-today-heatmap-picker",
            app: app
        )

        for choice in choices {
            activate(choice)
            XCTAssertTrue(waitUntil(timeout: 3) {
                choice.isSelected
            })
        }
        try capture(
            "\(screenshotPrefix)-settings-today-heatmap-selected",
            app: app
        )

        let backToGeneral = app.navigationBars["Heatmap Tasks"]
            .buttons["General"]
            .firstMatch
        XCTAssertTrue(backToGeneral.waitForExistence(timeout: 3))
        activate(backToGeneral)
        XCTAssertTrue(picker.waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitUntil(timeout: 3) {
            heatmapSettings.value as? String == "2 Selections"
        })
        try capture(
            "\(screenshotPrefix)-settings-today-heatmap-summary",
            app: app
        )

        activate(heatmapSettings)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        for choice in choices {
            XCTAssertTrue(waitUntil(timeout: 3) {
                choice.isSelected
            })
        }

        let firstChoice = choices[0]
        activate(firstChoice)
        XCTAssertTrue(waitUntil(timeout: 3) {
            firstChoice.isSelected == false
        })

        let clear = app.buttons[
            "settings.todayHeatmap.taskPicker.clear"
        ].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 3) && clear.isHittable)
        activate(clear)
        let secondChoice = choices[1]
        XCTAssertTrue(waitUntil(timeout: 3) {
            secondChoice.isSelected == false && clear.isEnabled == false
        })
        try capture(
            "\(screenshotPrefix)-settings-today-heatmap-cleared",
            app: app
        )

        XCTAssertTrue(backToGeneral.waitForExistence(timeout: 3))
        activate(backToGeneral)
        XCTAssertTrue(waitUntil(timeout: 3) {
            heatmapSettings.value as? String == "Off"
        })
        #endif
    }

    @MainActor
    func testTodayHeatmapPeriodAdaptsAndPersistsAcrossRelaunch() throws {
        defer { cleanupPersistentUITestStore() }
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif

        let app = launchApp(
            route: "settings",
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: [
                "--uitesting-today-heatmap",
                "--uitesting-reset-demo-preferences",
                "--uitesting-persistent-store",
                "--uitesting-reset-persistent-store",
            ]
        )
        #if os(macOS)
        openSettings(in: app)
        #endif
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.view"]
                .waitForExistence(timeout: 8)
        )

        #if os(macOS)
        let generalSettingsWindow = try XCTUnwrap(
            app.windows.allElementsBoundByIndex.first { window in
                window.descendants(matching: .any)["settings.view"].exists
            }
        )
        let general = generalSettingsWindow.descendants(matching: .any)
            .matching(identifier: "settings.category.general")
            .firstMatch
        #else
        let general = app.buttons["settings.category.general"].firstMatch
        #endif
        #if os(macOS)
        XCTAssertTrue(
            waitForElement(
                general,
                timeout: 5,
                diagnosticName: "heatmap-period-settings-general",
                in: app
            )
        )
        #else
        XCTAssertTrue(
            waitForElement(
                general,
                timeout: 5,
                diagnosticName: "heatmap-period-settings-general",
                in: app
            ) && general.isHittable
        )
        activate(general)
        #endif

        #if os(macOS)
        let periodPicker = generalSettingsWindow.descendants(matching: .any)[
            "settings.todayHeatmap.period"
        ].firstMatch
        let settingsScrollView = generalSettingsWindow.scrollViews[
            "settings.view"
        ].firstMatch
        for _ in 0 ..< 10 where !periodPicker.isHittable {
            settingsScrollView.scroll(byDeltaX: 0, deltaY: -420)
        }
        #else
        let periodPicker = app.descendants(matching: .any)[
            "settings.todayHeatmap.period"
        ].firstMatch
        scrollUntilHittable(
            periodPicker,
            direction: .up,
            maximumScrolls: 10,
            in: app
        )
        #endif
        XCTAssertTrue(
            waitForElement(
                periodPicker,
                timeout: 5,
                diagnosticName: "heatmap-period-picker",
                in: app
            ) && periodPicker.isHittable
        )
        let periodPresentation = {
            [
                periodPicker.label,
                periodPicker.value.map { String(describing: $0) } ?? "",
            ].joined(separator: " ")
        }
        XCTAssertTrue(
            periodPresentation().contains("1 Year"),
            "The reset preference must expose the one-year default."
        )

        activate(periodPicker)
        let oneMonthOptionIdentifier =
            "settings.todayHeatmap.period.oneMonth"
        #if os(macOS)
        let oneMonth = app.menuItems.matching(
            NSPredicate(
                format: "identifier == %@ OR label == %@",
                oneMonthOptionIdentifier,
                "1 Month"
            )
        ).firstMatch
        #else
        let oneMonth = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ OR label == %@",
                oneMonthOptionIdentifier,
                "1 Month"
            )
        ).firstMatch
        #endif
        XCTAssertTrue(
            waitForElement(
                oneMonth,
                timeout: 5,
                diagnosticName: "heatmap-period-one-month-option",
                in: app
            ) && oneMonth.isHittable
        )
        activate(oneMonth)
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                periodPresentation().contains("1 Month")
            },
            "Choosing one month must update the native Picker immediately."
        )

        let prefix = platformScreenshotPrefix(in: app)
        waitForScreenshotTransition()
        #if os(macOS)
        let settingsWindow = try XCTUnwrap(
            app.windows.allElementsBoundByIndex.first { window in
                window.descendants(matching: .any)["settings.view"].exists
            },
            "The macOS Settings window must exist for screenshot acceptance."
        )
        try placeWindowOnPrimaryScreen(settingsWindow, in: app)
        try capture(
            "\(prefix)-settings-today-heatmap-one-month",
            element: settingsWindow
        )
        #else
        try capture(
            "\(prefix)-settings-today-heatmap-one-month",
            app: app
        )
        #endif

        try dismissSettingsPresentationIfNeeded(in: app)
        openSection(
            "Today",
            tabIdentifier: "phone.tab.today",
            sidebarIdentifier: "sidebar.Today",
            in: app
        )
        XCTAssertTrue(homeIsReady(in: app))

        let checklistGrid = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@",
                "Time Tracker App activity Heatmap"
            )
        ).firstMatch
        let heatmapsHeader = app.descendants(matching: .any)[
            "home.heatmaps.header"
        ].firstMatch
        scrollUntilHittable(
            heatmapsHeader,
            direction: .up,
            maximumScrolls: 10,
            in: app
        )
        XCTAssertTrue(heatmapsHeader.waitForExistence(timeout: 8))
        scrollUntilFullyVisibleAboveSystemChrome(checklistGrid, in: app)
        XCTAssertTrue(
            waitForElement(
                checklistGrid,
                timeout: 8,
                diagnosticName: "heatmap-period-checklist-grid",
                in: app
            )
        )
        let gridIdentifierPrefix = "home.heatmap.grid."
        XCTAssertTrue(checklistGrid.identifier.hasPrefix(gridIdentifierPrefix))
        let taskID = String(
            checklistGrid.identifier.dropFirst(gridIdentifierPrefix.count)
        )
        XCTAssertNotNil(UUID(uuidString: taskID))
        let checklistGridIdentifier = checklistGrid.identifier

        let rangeIdentifier = "home.heatmap.range.\(taskID)"
        let chartIdentifier = "home.heatmap.chart.\(taskID)"
        let scrollerIdentifier = "home.heatmap.scroller.\(taskID)"
        let range = app.descendants(matching: .any)[rangeIdentifier].firstMatch
        let chart = app.descendants(matching: .any)[chartIdentifier].firstMatch
        let scroller = app.descendants(matching: .any)[
            scrollerIdentifier
        ].firstMatch
        XCTAssertTrue(
            waitForElement(
                range,
                timeout: 5,
                diagnosticName: "heatmap-period-range",
                in: app
            )
        )
        XCTAssertTrue(
            waitForElement(
                chart,
                timeout: 5,
                diagnosticName: "heatmap-period-chart",
                in: app
            )
        )
        XCTAssertTrue(
            waitForElement(
                scroller,
                timeout: 5,
                diagnosticName: "heatmap-period-scroller",
                in: app
            )
        )
        let oneMonthRange = [
            range.label,
            range.value.map { String(describing: $0) } ?? "",
        ].joined(separator: " ")
        XCTAssertFalse(oneMonthRange.trimmingCharacters(in: .whitespaces).isEmpty)
        XCTAssertGreaterThanOrEqual(
            chart.frame.height,
            210,
            "A one-month Heatmap must use the 24-point readable cell cap."
        )
        XCTAssertGreaterThanOrEqual(
            chart.frame.width,
            168,
            "A one-month Heatmap must not remain the old 116–121 point cluster."
        )
        XCTAssertLessThanOrEqual(
            chart.frame.width,
            scroller.frame.width + 2,
            "A one-month Heatmap must fit its card without horizontal overflow."
        )
        XCTAssertLessThanOrEqual(
            chart.frame.maxY,
            range.frame.minY + 2,
            "The chart and range footer must keep separate visual regions."
        )
        let oneMonthChartSize = chart.frame.size
        waitForScreenshotTransition()
        #if os(macOS)
        try capture(
            "\(prefix)-home-today-heatmap-one-month",
            element: checklistGrid
        )
        #else
        try capture(
            "\(prefix)-home-today-heatmap-one-month",
            app: app
        )
        #endif

        app.terminate()

        let relaunchedApp = launchApp(
            route: "settings",
            additionalLaunchArguments: [
                "--uitesting-today-heatmap",
                "--uitesting-persistent-store",
            ]
        )
        #if os(macOS)
        openSettings(in: relaunchedApp)
        #endif
        XCTAssertTrue(
            relaunchedApp.descendants(matching: .any)["settings.view"]
                .waitForExistence(timeout: 8)
        )

        #if os(macOS)
        let persistedSettingsWindow = try XCTUnwrap(
            relaunchedApp.windows.allElementsBoundByIndex.first { window in
                window.descendants(matching: .any)["settings.view"].exists
            }
        )
        let persistedGeneral = persistedSettingsWindow
            .descendants(matching: .any)
            .matching(identifier: "settings.category.general")
            .firstMatch
        #else
        let persistedGeneral = relaunchedApp.buttons[
            "settings.category.general"
        ].firstMatch
        #endif
        #if os(macOS)
        XCTAssertTrue(
            waitForElement(
                persistedGeneral,
                timeout: 5,
                diagnosticName: "heatmap-period-persisted-general",
                in: relaunchedApp
            )
        )
        #else
        XCTAssertTrue(
            waitForElement(
                persistedGeneral,
                timeout: 5,
                diagnosticName: "heatmap-period-persisted-general",
                in: relaunchedApp
            ) && persistedGeneral.isHittable
        )
        activate(persistedGeneral)
        #endif

        #if os(macOS)
        let persistedPeriodPicker = persistedSettingsWindow
            .descendants(matching: .any)[
                "settings.todayHeatmap.period"
            ].firstMatch
        let persistedSettingsScrollView = persistedSettingsWindow.scrollViews[
            "settings.view"
        ].firstMatch
        for _ in 0 ..< 10 where !persistedPeriodPicker.isHittable {
            persistedSettingsScrollView.scroll(
                byDeltaX: 0,
                deltaY: -420
            )
        }
        #else
        let persistedPeriodPicker = relaunchedApp.descendants(matching: .any)[
            "settings.todayHeatmap.period"
        ].firstMatch
        scrollUntilHittable(
            persistedPeriodPicker,
            direction: .up,
            maximumScrolls: 10,
            in: relaunchedApp
        )
        #endif
        XCTAssertTrue(
            waitForElement(
                persistedPeriodPicker,
                timeout: 5,
                diagnosticName: "heatmap-period-persisted-picker",
                in: relaunchedApp
            ) && persistedPeriodPicker.isHittable
        )
        let persistedPeriodPresentation = [
            persistedPeriodPicker.label,
            persistedPeriodPicker.value.map {
                String(describing: $0)
            } ?? "",
        ].joined(separator: " ")
        XCTAssertTrue(
            persistedPeriodPresentation.contains("1 Month"),
            "The one-month period must survive a process relaunch."
        )

        relaunchedApp.terminate()
        let persistedHomeApp = launchApp(
            route: "today",
            additionalLaunchArguments: [
                "--uitesting-today-heatmap",
                "--uitesting-persistent-store",
            ]
        )
        #if os(macOS)
        try placeMainWindowOnPrimaryScreen(in: persistedHomeApp)
        #endif
        openSection(
            "Today",
            tabIdentifier: "phone.tab.today",
            sidebarIdentifier: "sidebar.Today",
            in: persistedHomeApp
        )
        XCTAssertTrue(homeIsReady(in: persistedHomeApp))

        let persistedGrid = persistedHomeApp.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@",
                "Time Tracker App activity Heatmap"
            )
        ).firstMatch
        let persistedHeatmapsHeader = persistedHomeApp.descendants(matching: .any)[
            "home.heatmaps.header"
        ].firstMatch
        scrollUntilHittable(
            persistedHeatmapsHeader,
            direction: .up,
            maximumScrolls: 10,
            in: persistedHomeApp
        )
        XCTAssertTrue(persistedHeatmapsHeader.waitForExistence(timeout: 8))
        scrollUntilFullyVisibleAboveSystemChrome(
            persistedGrid,
            in: persistedHomeApp
        )
        XCTAssertTrue(
            waitForElement(
                persistedGrid,
                timeout: 8,
                diagnosticName: "heatmap-period-persisted-grid",
                in: persistedHomeApp
            )
        )
        XCTAssertEqual(persistedGrid.identifier, checklistGridIdentifier)

        let persistedRange = persistedHomeApp.descendants(matching: .any)[
            rangeIdentifier
        ].firstMatch
        let persistedChart = persistedHomeApp.descendants(matching: .any)[
            chartIdentifier
        ].firstMatch
        XCTAssertTrue(
            waitForElement(
                persistedRange,
                timeout: 5,
                diagnosticName: "heatmap-period-persisted-range",
                in: persistedHomeApp
            )
        )
        XCTAssertTrue(
            waitForElement(
                persistedChart,
                timeout: 5,
                diagnosticName: "heatmap-period-persisted-chart",
                in: persistedHomeApp
            )
        )
        let persistedRangePresentation = [
            persistedRange.label,
            persistedRange.value.map { String(describing: $0) } ?? "",
        ].joined(separator: " ")
        XCTAssertFalse(
            persistedRangePresentation
                .trimmingCharacters(in: .whitespaces)
                .isEmpty
        )
        XCTAssertEqual(
            persistedChart.frame.width,
            oneMonthChartSize.width,
            accuracy: 1
        )
        XCTAssertEqual(
            persistedChart.frame.height,
            oneMonthChartSize.height,
            accuracy: 1
        )
        waitForScreenshotTransition()
        #if os(macOS)
        try capture(
            "\(platformScreenshotPrefix(in: persistedHomeApp))-home-today-heatmap-one-month-persisted",
            element: persistedGrid
        )
        #else
        try capture(
            "\(platformScreenshotPrefix(in: persistedHomeApp))-home-today-heatmap-one-month-persisted",
            app: persistedHomeApp
        )
        #endif
    }

    @MainActor
    private func cleanupPersistentUITestStore() {
        let app = launchApp(
            seedsDemoData: false,
            additionalLaunchArguments: [
                "--uitesting-clean-persistent-store",
            ]
        )
        app.terminate()
    }

    @MainActor
    private func dismissSettingsPresentationIfNeeded(
        in app: XCUIApplication
    ) throws {
        #if os(macOS)
        guard let discoveredSettingsWindow = app.windows.allElementsBoundByIndex
            .first(where: { window in
                window.descendants(matching: .any)["settings.view"].exists
            })
        else {
            XCTFail("The macOS Settings window must exist before dismissal.")
            return
        }
        let settingsWindowIdentifier = discoveredSettingsWindow.identifier
        let settingsWindow = settingsWindowIdentifier.isEmpty
            ? discoveredSettingsWindow
            : app.windows.matching(
                identifier: settingsWindowIdentifier
            ).firstMatch
        try placeWindowOnPrimaryScreen(settingsWindow, in: app)
        settingsWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.view"]
                .firstMatch.waitForNonExistence(timeout: 5),
            "Closing macOS Settings must uncover the main window."
        )
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3))
        #elseif os(iOS)
        guard platformScreenshotPrefix(in: app) == "iphone" else {
            return
        }

        let settingsBack = app.navigationBars["General"]
            .buttons["Settings"]
            .firstMatch
        if settingsBack.waitForExistence(timeout: 2), settingsBack.isHittable {
            activate(settingsBack)
        }

        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(
            done.waitForExistence(timeout: 3) && done.isHittable,
            "The phone Settings sheet must expose its system Done action."
        )
        activate(done)
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.view"]
                .firstMatch.waitForNonExistence(timeout: 5),
            "Dismissing phone Settings must restore the tab shell."
        )
        #endif
    }

    @MainActor
    func testTaskPickerShowsRunningAndSelectedPassiveIndicatorsTogether() throws {
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif

        let app = launchApp(
            route: "settings",
            replacesDemoDataOnLaunch: true
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.view"]
                .waitForExistence(timeout: 8)
        )

        #if os(iOS)
        let general = app.buttons["settings.category.general"].firstMatch
        XCTAssertTrue(
            general.waitForExistence(timeout: 5) && general.isHittable
        )
        activate(general)
        #endif

        let heatmapSettings = app.descendants(matching: .any)[
            "settings.todayHeatmap.tasks"
        ].firstMatch
        scrollUntilHittable(heatmapSettings, direction: .up, in: app)
        XCTAssertTrue(
            heatmapSettings.waitForExistence(timeout: 5) &&
                heatmapSettings.isHittable
        )
        activate(heatmapSettings)

        let picker = app.descendants(matching: .any)[
            "settings.todayHeatmap.taskPicker"
        ].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))

        #if os(macOS)
        let settingsWindow = app.windows.containing(
            .any,
            identifier: "settings.todayHeatmap.taskPicker"
        ).firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 3))
        let search = settingsWindow.searchFields.allElementsBoundByIndex.first(where: {
            $0.isHittable
        }) ?? settingsWindow.searchFields.firstMatch
        #else
        let search = app.searchFields[
            "Search tasks, paths, or notes"
        ].firstMatch
        #endif
        XCTAssertTrue(search.waitForExistence(timeout: 3) && search.isHittable)
        activate(search)
        replaceText("Read Apple HIG", in: search)
        #if os(iOS)
        search.typeText(XCUIKeyboardKey.return.rawValue)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        #endif

        let choicePrefix = "settings.todayHeatmap.taskPicker.select."
        let runningChoice = picker.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                choicePrefix,
                "Read Apple HIG"
            ))
            .firstMatch
        XCTAssertTrue(
            runningChoice.waitForExistence(timeout: 5) &&
                runningChoice.isHittable
        )
        XCTAssertFalse(runningChoice.isSelected)
        let runningIdentifier = runningChoice.identifier
        XCTAssertTrue(runningIdentifier.hasPrefix(choicePrefix))
        XCTAssertNotNil(
            UUID(uuidString: String(runningIdentifier.dropFirst(choicePrefix.count)))
        )
        let unselectedValue = String(describing: runningChoice.value ?? "")
        XCTAssertTrue(unselectedValue.contains("Running"))
        XCTAssertTrue(unselectedValue.contains("Not selected"))

        activate(runningChoice)
        let selectedChoice = picker.buttons[runningIdentifier].firstMatch
        XCTAssertTrue(waitUntil(timeout: 3) {
            selectedChoice.exists && selectedChoice.isSelected
        })
        let selectedValue = String(describing: selectedChoice.value ?? "")
        XCTAssertTrue(selectedValue.contains("Running"))
        XCTAssertTrue(selectedValue.contains("Selected"))
        XCTAssertFalse(selectedValue.contains("Not selected"))

        #if os(iOS)
        let screenshotPrefix = app.windows.firstMatch.frame.width >= 700
            ? "ipad"
            : "iphone"
        waitForScreenshotTransition()
        try capture(
            "\(screenshotPrefix)-task-picker-running-selected-passive-status",
            app: app
        )
        #endif
    }

    @MainActor
    func testTaskArchiveAndSettingsUnarchiveRoundTrip() throws {
        let app = launchApp(
            route: "tasks",
            replacesDemoDataOnLaunch: true
        )
        let screenshotPrefix = platformScreenshotPrefix(in: app)
        if app.descendants(matching: .any)["tasks.view"]
            .waitForExistence(timeout: 3) == false
        {
            openSection(
                "Tasks",
                tabIdentifier: "phone.tab.tasks",
                sidebarIdentifier: "sidebar.Tasks",
                in: app
            )
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["tasks.view"]
                .waitForExistence(timeout: 8)
        )
        let taskTitle = "Standalone Task"
        let task = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "tasks.row.",
                taskTitle
            ))
            .firstMatch
        scrollUntilHittable(task, direction: .up, in: app)
        XCTAssertTrue(task.waitForExistence(timeout: 5) && task.isHittable)

        #if os(macOS)
        XCTAssertGreaterThanOrEqual(task.frame.height, 28)
        task.rightClick()
        let contextArchive = app.menuItems["Archive"].firstMatch
        XCTAssertTrue(
            contextArchive.waitForExistence(timeout: 3) &&
                contextArchive.isHittable
        )
        try capture("\(screenshotPrefix)-task-context-menu-archive", app: app)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        activate(task)
        let taskMenu = app.menuBars.menuBarItems["Task"].firstMatch
        XCTAssertTrue(taskMenu.waitForExistence(timeout: 3) && taskMenu.isHittable)
        activate(taskMenu)
        let archiveSelected = app.menuItems["Archive Selected Task"].firstMatch
        XCTAssertTrue(
            archiveSelected.waitForExistence(timeout: 3) &&
                archiveSelected.isHittable
        )
        try capture("\(screenshotPrefix)-task-menu-archive-selected", app: app)
        activate(archiveSelected)
        #else
        XCTAssertGreaterThanOrEqual(task.frame.height, 44)
        task.swipeLeft()
        let archive = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "task.swipe.archive."
            ))
            .firstMatch
        XCTAssertTrue(archive.waitForExistence(timeout: 3) && archive.isHittable)
        XCTAssertGreaterThanOrEqual(archive.frame.width, 44)
        XCTAssertGreaterThanOrEqual(archive.frame.height, 44)
        try capture("\(screenshotPrefix)-task-swipe-archive", app: app)
        activate(archive)
        #endif
        XCTAssertTrue(task.waitForNonExistence(timeout: 5))

        openSettings(in: app)
        let archivedCategory = app.descendants(matching: .any)[
            "settings.category.archivedTasks"
        ].firstMatch
        XCTAssertTrue(
            archivedCategory.waitForExistence(timeout: 5) &&
                archivedCategory.isHittable
        )
        activate(archivedCategory)

        let unarchive = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "settings.archivedTasks.unarchive."
            ))
            .firstMatch
        XCTAssertTrue(unarchive.waitForExistence(timeout: 5) && unarchive.isHittable)
        XCTAssertTrue(unarchive.isEnabled)
        #if os(macOS)
        XCTAssertGreaterThanOrEqual(unarchive.frame.width, 28)
        XCTAssertGreaterThanOrEqual(unarchive.frame.height, 28)
        #else
        XCTAssertGreaterThanOrEqual(unarchive.frame.width, 44)
        XCTAssertGreaterThanOrEqual(unarchive.frame.height, 44)
        #endif
        XCTAssertTrue(app.staticTexts[taskTitle].waitForExistence(timeout: 3))
        try capture("\(screenshotPrefix)-settings-archived-task", app: app)

        activate(unarchive)
        let errorAlert = app.alerts.firstMatch
        if errorAlert.waitForExistence(timeout: 1) {
            let errorText = errorAlert.staticTexts.allElementsBoundByIndex
                .map(\.label)
                .joined(separator: " — ")
            XCTFail("Unarchive presented an error: \(errorText)")
            return
        }
        XCTAssertTrue(unarchive.waitForNonExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["No Archived Tasks"].waitForExistence(timeout: 3)
        )
        try capture("\(screenshotPrefix)-settings-archived-empty", app: app)

        #if os(macOS)
        guard let settingsWindow = app.windows.allElementsBoundByIndex.first(where: {
            $0.descendants(matching: .any)["settings.category.archivedTasks"].exists
        }) else {
            XCTFail("Could not find the macOS Settings window")
            return
        }
        settingsWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(archivedCategory.waitForNonExistence(timeout: 5))
        app.activate()
        #else
        let settingsBack = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(
            settingsBack.waitForExistence(timeout: 3) &&
                settingsBack.isHittable
        )
        activate(settingsBack)
        if screenshotPrefix == "iphone" {
            let done = app.buttons["Done"].firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 3) && done.isHittable)
            activate(done)
            XCTAssertTrue(
                app.descendants(matching: .any)["settings.view"]
                    .waitForNonExistence(timeout: 5)
            )
        }
        #endif
        openSection(
            "Tasks",
            tabIdentifier: "phone.tab.tasks",
            sidebarIdentifier: "sidebar.Tasks",
            in: app
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["tasks.view"]
                .waitForExistence(timeout: 5)
        )
        let restoredTask = taskRow(named: taskTitle, in: app)
        scrollUntilHittable(restoredTask, direction: .up, in: app)
        XCTAssertTrue(
            restoredTask.waitForExistence(timeout: 5) &&
                restoredTask.isHittable
        )
        try capture("\(screenshotPrefix)-task-restored-from-settings", app: app)
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
    func testTaskDetailIdentityCardShowsTaskNameAndParentPath() throws {
        let app = launchApp(
            route: "task-detail",
            contentSizeCategory: "UICTContentSizeCategoryL",
            replacesDemoDataOnLaunch: true,
            taskTitle: "Read Apple HIG"
        )
        let detail = app.descendants(matching: .any)["task.detail"].firstMatch
        let identity = app.descendants(matching: .any)[
            "task.detail.identity"
        ].firstMatch

        XCTAssertTrue(
            detail.waitForExistence(timeout: 15),
            "The audited detail route must finish loading after a cold simulator launch."
        )
        XCTAssertTrue(identity.waitForExistence(timeout: 5))
        let titleField = app.descendants(matching: .any)[
            "task.editor.title.field"
        ].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertTrue(
            (titleField.value as? String ?? titleField.label)
                .localizedCaseInsensitiveContains("Read Apple HIG"),
            "The visible identity card must include the task name, not only its parent path."
        )
        XCTAssertTrue(app.staticTexts["Study"].waitForExistence(timeout: 3))
        XCTAssertGreaterThan(identity.frame.width, 0)
        XCTAssertGreaterThan(identity.frame.height, 0)
        XCTAssertGreaterThanOrEqual(identity.frame.minY, detail.frame.minY)
        XCTAssertLessThanOrEqual(identity.frame.maxY, detail.frame.maxY)
        try capture("task-detail-visible-title", app: app)
    }

    @MainActor
    func testTaskDetailHeatmapTrackingDefaultsOffAndSyncsToToday() throws {
        #if os(macOS)
        throw XCTSkip("Task-detail Heatmap screenshots are verified on iPhone and iPad simulators.")
        #else
        let taskTitle = "Read Apple HIG"
        let app = launchApp(
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: [
                "--uitesting-today-heatmap",
                "--uitesting-reset-demo-preferences",
            ]
        )
        XCTAssertTrue(initialConfigurationIsReady(in: app))
        XCTAssertTrue(homeIsReady(in: app))
        let configuredHeatmaps = app.descendants(matching: .any)[
            "home.heatmaps.header"
        ].firstMatch
        XCTAssertTrue(configuredHeatmaps.waitForExistence(timeout: 8))
        openSection(
            "Tasks",
            tabIdentifier: "phone.tab.tasks",
            sidebarIdentifier: "sidebar.Tasks",
            in: app
        )
        let tasksView = app.descendants(matching: .any)["tasks.view"].firstMatch
        XCTAssertTrue(tasksView.waitForExistence(timeout: 8))
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(
            searchField.waitForExistence(timeout: 5) && searchField.isHittable
        )
        activate(searchField)
        replaceText(taskTitle, in: searchField)
        let task = taskRow(named: taskTitle, in: app)
        XCTAssertTrue(task.waitForExistence(timeout: 8) && task.isHittable)
        activate(task)
        XCTAssertTrue(taskDetailIsReady(in: app))
        let toggle = app.switches["task.detail.heatmapTracking"].firstMatch
        scrollUntilHittable(toggle, direction: .up, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5) && toggle.isHittable)
        XCTAssertEqual(toggle.value as? String, "0")
        let prefix = app.windows.firstMatch.frame.width >= 700
            ? "ipad"
            : "iphone"
        try capture("\(prefix)-task-detail-heatmap-off", app: app)

        toggle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
        XCTAssertTrue(waitUntil(timeout: 5) {
            toggle.value as? String == "1"
        })
        let palette = app.descendants(matching: .any)[
            "task.detail.heatmapPalette"
        ].firstMatch
        XCTAssertTrue(palette.waitForExistence(timeout: 5))
        try capture("\(prefix)-task-detail-heatmap-on", app: app)

        openSection(
            "Today",
            tabIdentifier: "phone.tab.today",
            sidebarIdentifier: "sidebar.Today",
            in: app
        )
        XCTAssertTrue(homeIsReady(in: app))
        let grid = app.otherElements.matching(
            NSPredicate(
                format: "label == %@",
                "Read Apple HIG activity Heatmap"
            )
        ).firstMatch
        scrollUntilHittable(grid, direction: .up, in: app)
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        try capture("\(prefix)-task-detail-heatmap-enabled-today", app: app)
        #endif
    }

    @MainActor
    func testTaskDetailIconOpensSymbolColorPicker() throws {
        let taskTitle = "Read Apple HIG"
        let app = launchApp(
            route: "task-detail",
            replacesDemoDataOnLaunch: true,
            taskTitle: taskTitle,
            additionalLaunchArguments: ["--uitesting-reset-demo-preferences"]
        )
        let detail = app.descendants(matching: .any)["task.detail"].firstMatch
        XCTAssertTrue(
            detail.waitForExistence(timeout: 15),
            "Task detail must open before the icon can be activated."
        )

        let iconButton = app.descendants(matching: .any)[
            "task.detail.icon.edit"
        ].firstMatch
        scrollUntilHittable(iconButton, direction: .up, in: app)
        XCTAssertTrue(
            iconButton.waitForExistence(timeout: 5),
            "The task detail identity icon must be an interactive editor link."
        )
        XCTAssertTrue(
            iconButton.isHittable,
            "The task detail identity icon must keep an interactive hit target."
        )

        let titleField = app.descendants(matching: .any)[
            "task.editor.title.field"
        ].firstMatch
        XCTAssertTrue(
            titleField.waitForExistence(timeout: 5),
            "The task title field must exist beside the identity icon."
        )

        let prefix = platformScreenshotPrefix(in: app)
        try capture("\(prefix)-task-detail-icon-row", app: app)

        let iconFrame = iconButton.frame
        let titleFrame = titleField.frame
        let iconToTitleSpacing = titleFrame.minX - iconFrame.maxX
        XCTAssertGreaterThanOrEqual(
            iconFrame.width,
            42,
            "The identity icon must retain its 44pt control width."
        )
        XCTAssertGreaterThanOrEqual(
            iconFrame.height,
            42,
            "The identity icon must retain its 44pt interactive height."
        )
        XCTAssertLessThanOrEqual(
            iconFrame.width,
            48,
            "The identity icon must not reserve trailing navigation-indicator space. "
                + "iconFrame=\(iconFrame), titleFrame=\(titleFrame)"
        )
        XCTAssertGreaterThanOrEqual(
            iconToTitleSpacing,
            10,
            "The identity icon must retain the designed 14pt leading gap. "
                + "iconFrame=\(iconFrame), titleFrame=\(titleFrame)"
        )
        XCTAssertLessThanOrEqual(
            iconToTitleSpacing,
            18,
            "The identity icon must not leave unexplained space before the title. "
                + "iconFrame=\(iconFrame), titleFrame=\(titleFrame)"
        )
        activate(iconButton)

        let pickerView = app.descendants(matching: .any)[
            "symbol.picker.view"
        ].firstMatch
        XCTAssertTrue(
            pickerView.waitForExistence(timeout: 8),
            "Activating the task icon must present the symbol picker."
        )
        let pickerSearch = app.descendants(matching: .any)[
            "symbol.picker.search"
        ].firstMatch
        XCTAssertTrue(
            pickerSearch.waitForExistence(timeout: 5),
            "The presented symbol picker must include its search field."
        )

        try capture("\(prefix)-task-detail-icon-editor", app: app)
    }

    @MainActor
    func testRecurringOccurrenceHeatmapToggleControlsTheParentCard() throws {
        let taskTitle = "Daily Push-ups · Today"
        let templateTaskID = UUID().uuidString.uppercased()
        let app = launchApp(
            route: "task-detail",
            replacesDemoDataOnLaunch: true,
            taskTitle: taskTitle,
            additionalLaunchArguments: [
                "--uitesting-today-heatmap",
                "--uitesting-today-heatmap-template-id",
                templateTaskID,
                "--uitesting-reset-demo-preferences",
            ]
        )
        #if os(macOS)
        try placeMainWindowOnPrimaryScreen(in: app)
        #else
        XCTAssertTrue(initialConfigurationIsReady(in: app))
        #endif
        ensureTaskDetailIsReady(named: taskTitle, in: app)

        #if os(macOS)
        let toggle = app.checkBoxes[
            "task.detail.heatmapTracking"
        ].firstMatch
        #else
        let toggle = app.switches[
            "task.detail.heatmapTracking"
        ].firstMatch
        #endif
        scrollUntilHittable(toggle, direction: .up, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5) && toggle.isHittable)
        let palette = app.descendants(matching: .any)[
            "task.detail.heatmapPalette"
        ].firstMatch
        XCTAssertTrue(palette.waitForExistence(timeout: 3))
        XCTAssertTrue(
            toggle.label.localizedCaseInsensitiveContains(
                "repeating parent"
            )
        )
        let recurringFooter = app.staticTexts[
            "Work stays recorded on this occurrence. Its repeating parent owns the Heatmap and combines every occurrence."
        ].firstMatch
        XCTAssertTrue(recurringFooter.waitForExistence(timeout: 3))
        let prefix = platformScreenshotPrefix(in: app)
        try capture(
            "\(prefix)-task-detail-recurring-parent-heatmap",
            app: app
        )

        #if os(macOS)
        activate(toggle)
        #else
        toggle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
        #endif
        XCTAssertTrue(palette.waitForNonExistence(timeout: 5))
        #if os(macOS)
        activate(toggle)
        #else
        toggle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
        #endif
        XCTAssertTrue(palette.waitForExistence(timeout: 5))

        openSection(
            "Today",
            tabIdentifier: "phone.tab.today",
            sidebarIdentifier: "sidebar.Today",
            in: app
        )
        XCTAssertTrue(homeIsReady(in: app))
        let parentCard = app.descendants(matching: .any)[
            "home.heatmap.card.\(templateTaskID)"
        ].firstMatch
        let parentGrid = app.descendants(matching: .any)[
            "home.heatmap.grid.\(templateTaskID)"
        ].firstMatch
        scrollUntilHittable(parentGrid, direction: .up, in: app)
        scrollUntilFullyVisibleAboveSystemChrome(parentGrid, in: app)
        XCTAssertTrue(parentCard.waitForExistence(timeout: 8))
        XCTAssertTrue(parentGrid.waitForExistence(timeout: 8))
        XCTAssertTrue(
            parentGrid.label.localizedCaseInsensitiveContains(
                "Daily Push-ups"
            )
        )
        #if os(iOS)
        XCTAssertEqual(
            parentGrid.value as? String,
            "Quantity · reps. Total 75 reps across 2 active days; busiest day 45 reps."
        )
        #else
        let parentHeader = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "(label CONTAINS[c] %@ OR value CONTAINS[c] %@) AND (label CONTAINS[c] %@ OR value CONTAINS[c] %@)",
                "Daily Push-ups",
                "Daily Push-ups",
                "Quantity",
                "Quantity"
            )
        ).firstMatch
        XCTAssertTrue(parentHeader.waitForExistence(timeout: 3))
        let parentHeaderSummary = [
            parentHeader.label,
            parentHeader.value as? String ?? "",
        ].joined(separator: " ")
        XCTAssertTrue(parentHeaderSummary.contains("75"))
        #endif
        let occurrenceGrid = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@",
                "Daily Push-ups · Today activity Heatmap"
            )
        ).firstMatch
        XCTAssertFalse(
            occurrenceGrid.exists,
            "A generated occurrence must not own a separate Heatmap card."
        )
        try capture(
            "\(prefix)-home-today-heatmap-recurring-parent-toggle",
            app: app
        )
    }

    @MainActor
    func testTaskDetailPromotesTimerAndManualTimeActions() throws {
        let app = launchApp(
            route: "task-detail",
            contentSizeCategory: "UICTContentSizeCategoryL",
            replacesDemoDataOnLaunch: true,
            taskTitle: "Read Apple HIG"
        )
        let detail = app.descendants(matching: .any)["task.detail"].firstMatch
        let identity = app.descendants(matching: .any)["task.detail.identity"].firstMatch
        let titleField = app.descendants(matching: .any)["task.editor.title.field"].firstMatch
        let timer = app.buttons["task.detail.timer"].firstMatch
        let addTime = app.buttons["task.detail.addTime"].firstMatch
        let more = app.descendants(matching: .any)["task.detail.more"].firstMatch

        XCTAssertTrue(
            detail.waitForExistence(timeout: 15),
            "The audited detail route must finish loading after a cold simulator launch."
        )
        XCTAssertTrue(identity.waitForExistence(timeout: 5))
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertTrue(timer.waitForExistence(timeout: 5) && timer.isHittable)
        XCTAssertTrue(addTime.waitForExistence(timeout: 5) && addTime.isHittable)
        XCTAssertTrue(more.waitForExistence(timeout: 5) && more.isHittable)
        XCTAssertEqual(timer.label, "Stop Read Apple HIG")
        XCTAssertFalse(app.descendants(matching: .any)["task.detail.actions"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["task.detail.edit"].exists)

        XCTAssertLessThan(titleField.frame.maxX, timer.frame.minX)
        XCTAssertGreaterThanOrEqual(timer.frame.midY, titleField.frame.minY)
        XCTAssertLessThanOrEqual(timer.frame.midY, identity.frame.maxY)
        #if os(iOS)
        let usesIPadShell = app.descendants(matching: .any)["ipad.splitNavigation"]
            .waitForExistence(timeout: 1)
        XCTAssertGreaterThanOrEqual(timer.frame.width, 44)
        XCTAssertGreaterThanOrEqual(timer.frame.height, 44)
        if usesIPadShell {
            XCTAssertGreaterThan(
                timer.frame.width,
                88,
                "iPad must keep the visible Start or Stop title instead of collapsing to the phone icon-only control."
            )
        }
        #else
        XCTAssertGreaterThanOrEqual(timer.frame.width, 28)
        XCTAssertGreaterThanOrEqual(timer.frame.height, 28)
        #endif
        XCTAssertEqual(addTime.frame.midY, more.frame.midY, accuracy: 2)
        XCTAssertLessThan(addTime.frame.minX, more.frame.minX)
        XCTAssertLessThanOrEqual(
            addTime.frame.maxY,
            identity.frame.minY + 2,
            "The toolbar action must remain above the identity card, allowing for platform pixel rounding."
        )

        #if os(macOS)
        try capture("mac-task-detail-top-actions", app: app)
        #else
        try capture(
            usesIPadShell
                ? "ipad-task-detail-top-actions"
                : "iphone-task-detail-top-actions",
            app: app
        )
        #endif

        activate(timer)
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                timer.exists && timer.label == "Start Read Apple HIG"
            },
            "Stopping from the identity card must leave the shared Start action in place."
        )

        activate(addTime)
        let manualTimeNote = app.descendants(matching: .any)["manualTime.note"].firstMatch
        XCTAssertTrue(manualTimeNote.waitForExistence(timeout: 5))
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3) && cancel.isHittable)
        activate(cancel)
        XCTAssertTrue(manualTimeNote.waitForNonExistence(timeout: 5))

        XCTAssertTrue(timer.waitForExistence(timeout: 3) && timer.isHittable)
        activate(timer)
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                timer.exists && timer.label == "Stop Read Apple HIG"
            },
            "Starting from the identity card must restore the shared Stop action."
        )
    }

    @MainActor
    func testTaskDetailAutosavesInlineChangesWithStableActions() throws {
        let app = launchApp(
            route: "task-detail",
            contentSizeCategory: "UICTContentSizeCategoryL",
            replacesDemoDataOnLaunch: true,
            taskTitle: "Read Apple HIG"
        )
        let detail = app.descendants(matching: .any)["task.detail"].firstMatch
        let titleField = app.descendants(matching: .any)[
            "task.editor.title.field"
        ].firstMatch
        let cancel = app.buttons["task.editor.cancel"].firstMatch
        let save = app.buttons["task.editor.save"].firstMatch
        let addTime = app.descendants(matching: .any)[
            "task.detail.addTime"
        ].firstMatch
        let more = app.descendants(matching: .any)[
            "task.detail.more"
        ].firstMatch
        let timer = app.buttons["task.detail.timer"].firstMatch
        let firstSavedTitle = "Read Apple HIG Focused"
        let updatedTitle = "\(firstSavedTitle) Autosaved"

        ensureTaskDetailIsReady(named: "Read Apple HIG", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        let screenshotPrefix = platformScreenshotPrefix(in: app)
        XCTAssertTrue(titleField.waitForExistence(timeout: 5) && titleField.isHittable)
        XCTAssertTrue(addTime.waitForExistence(timeout: 5) && addTime.isHittable)
        XCTAssertTrue(more.waitForExistence(timeout: 5) && more.isHittable)
        XCTAssertTrue(timer.waitForExistence(timeout: 5) && timer.isHittable)
        XCTAssertFalse(cancel.exists)
        XCTAssertFalse(save.exists)
        enterTaskTitle(
            firstSavedTitle,
            appending: " Focused",
            in: titleField
        )

        XCTAssertTrue(
            waitUntil(timeout: 5) {
                timer.exists &&
                    timer.label.localizedCaseInsensitiveContains(firstSavedTitle)
            },
            "The first edit must autosave while the title field remains focused."
        )
        XCTAssertEqual(
            titleField.value as? String ?? titleField.label,
            firstSavedTitle
        )
        titleField.typeText(" Autosaved")
        XCTAssertEqual(
            titleField.value as? String ?? titleField.label,
            updatedTitle,
            "Input typed after the first autosave must keep its leading space."
        )
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                timer.exists &&
                    timer.label.localizedCaseInsensitiveContains(updatedTitle)
            },
            "The follow-up input must autosave without an explicit Save."
        )
        XCTAssertFalse(cancel.exists)
        XCTAssertFalse(save.exists)
        XCTAssertTrue(addTime.exists && addTime.isHittable)
        XCTAssertTrue(more.exists && more.isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["task.context.edit"].exists)
        submitTaskTitleIfKeyboardIsVisible(titleField, in: app)

        openSection(
            "Today",
            tabIdentifier: "phone.tab.today",
            sidebarIdentifier: "sidebar.Today",
            in: app
        )
        XCTAssertTrue(detail.waitForNonExistence(timeout: 5))
        XCTAssertTrue(homeIsReady(in: app))
        openTaskDetailFromTasks(named: updatedTitle, in: app)
        XCTAssertTrue(taskDetailIsReady(in: app))
        let persistedTitleField = app.descendants(matching: .any)[
            "task.editor.title.field"
        ].firstMatch
        XCTAssertTrue(persistedTitleField.waitForExistence(timeout: 5))
        XCTAssertEqual(
            persistedTitleField.value as? String ?? persistedTitleField.label,
            updatedTitle
        )
        try capture(
            "\(screenshotPrefix)-task-detail-inline-autosaved",
            app: app
        )
    }

    @MainActor
    func testTaskDetailMarkdownPreviewExpandsToAutosavingEditor() throws {
        let app = launchApp(
            route: "tasks",
            replacesDemoDataOnLaunch: true,
            taskTitle: "Read Apple HIG",
            autosaveDelayMilliseconds: 60000
        )
        ensureTaskDetailIsReady(named: "Read Apple HIG", in: app)
        let screenshotPrefix = platformScreenshotPrefix(in: app)
        let emptyPreview = app.descendants(matching: .any)[
            "task.editor.notes.empty"
        ].firstMatch
        let editNotes = app.buttons["task.editor.notes.edit"].firstMatch
        let notesField = app.descendants(matching: .any)[
            "task.editor.notes.field"
        ].firstMatch
        let segmentedMode = app.descendants(matching: .any)[
            "task.editor.notes.mode"
        ].firstMatch
        let markdown = "**Markdown autosave**"

        scrollUntilHittable(editNotes, direction: .up, in: app)
        XCTAssertTrue(
            editNotes.waitForExistence(timeout: 5) && editNotes.isHittable
        )
        XCTAssertTrue(emptyPreview.waitForExistence(timeout: 3))
        XCTAssertFalse(notesField.exists)
        XCTAssertFalse(segmentedMode.exists)
        try capture(
            "\(screenshotPrefix)-task-detail-notes-empty-preview",
            app: app
        )

        activate(editNotes)
        XCTAssertTrue(
            notesField.waitForExistence(timeout: 5) && notesField.isHittable
        )
        #if os(iOS)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        #else
        activate(notesField)
        #endif
        replaceText(markdown, in: notesField)
        XCTAssertEqual(notesField.value as? String ?? notesField.label, markdown)

        let doneNotes = app.buttons["task.editor.notes.done"].firstMatch
        scrollUntilHittable(doneNotes, direction: .down, in: app)
        XCTAssertTrue(
            doneNotes.waitForExistence(timeout: 5) && doneNotes.isHittable
        )
        try capture(
            "\(screenshotPrefix)-task-detail-notes-expanded-editor",
            app: app
        )
        activate(doneNotes)

        XCTAssertTrue(notesField.waitForNonExistence(timeout: 5))
        #if os(iOS)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        #endif
        let markdownPreview = app.descendants(matching: .any)[
            "task.detail.notes.markdown"
        ].firstMatch
        XCTAssertTrue(markdownPreview.waitForExistence(timeout: 5))
        XCTAssertTrue(editNotes.waitForExistence(timeout: 3))
        XCTAssertFalse(doneNotes.exists)
        try capture(
            "\(screenshotPrefix)-task-detail-notes-markdown-preview",
            app: app
        )

        let tasksBack = taskDetailBackButton(
            to: "Tasks",
            in: app
        )
        XCTAssertTrue(
            tasksBack.waitForExistence(timeout: 5) && tasksBack.isHittable
        )
        activate(tasksBack)
        XCTAssertTrue(
            app.descendants(matching: .any)["tasks.view"]
                .waitForExistence(timeout: 5)
        )
        openTaskDetailFromTasks(named: "Read Apple HIG", in: app)
        XCTAssertTrue(taskDetailIsReady(in: app))

        let persistedEditNotes = app.buttons[
            "task.editor.notes.edit"
        ].firstMatch
        scrollUntilHittable(persistedEditNotes, direction: .up, in: app)
        XCTAssertTrue(
            persistedEditNotes.waitForExistence(timeout: 5) &&
                persistedEditNotes.isHittable
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["task.detail.notes.markdown"]
                .firstMatch.waitForExistence(timeout: 5)
        )
        activate(persistedEditNotes)

        let persistedNotesField = app.descendants(matching: .any)[
            "task.editor.notes.field"
        ].firstMatch
        XCTAssertTrue(persistedNotesField.waitForExistence(timeout: 5))
        XCTAssertEqual(
            persistedNotesField.value as? String ??
                persistedNotesField.label,
            markdown
        )
    }

    @MainActor
    func testTaskDetailSidebarNavigationFlushesAutosave() throws {
        let app = launchApp(
            route: "task-detail",
            replacesDemoDataOnLaunch: true,
            taskTitle: "Read Apple HIG",
            autosaveDelayMilliseconds: 30000
        )
        ensureTaskDetailIsReady(named: "Read Apple HIG", in: app)
        let screenshotPrefix = platformScreenshotPrefix(in: app)

        #if os(iOS)
        guard app.descendants(matching: .any)["ipad.splitNavigation"]
            .waitForExistence(timeout: 5)
        else {
            throw XCTSkip("Sidebar navigation is available on iPad and macOS.")
        }
        #endif

        let titleField = app.descendants(matching: .any)[
            "task.editor.title.field"
        ].firstMatch
        let updatedTitle = "Read Apple HIG Sidebar Autosaved"
        XCTAssertTrue(titleField.waitForExistence(timeout: 5) && titleField.isHittable)
        enterTaskTitle(
            updatedTitle,
            appending: " Sidebar Autosaved",
            in: titleField
        )
        XCTAssertFalse(app.buttons["task.editor.save"].firstMatch.exists)
        let timer = app.buttons["task.detail.timer"].firstMatch
        XCTAssertTrue(timer.waitForExistence(timeout: 3))
        XCTAssertFalse(
            timer.label.localizedCaseInsensitiveContains(updatedTitle),
            "The long UI-test debounce must leave navigation to flush this edit."
        )

        openSection(
            "Today",
            tabIdentifier: "phone.tab.today",
            sidebarIdentifier: "sidebar.Today",
            in: app
        )

        XCTAssertTrue(
            app.descendants(matching: .any)["task.detail"]
                .firstMatch.waitForNonExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["editor.discard.confirm"].exists)
        XCTAssertTrue(homeIsReady(in: app))

        openTaskDetailFromTasks(named: updatedTitle, in: app)
        XCTAssertTrue(taskDetailIsReady(in: app))
        let persistedTitleField = app.descendants(matching: .any)[
            "task.editor.title.field"
        ].firstMatch
        XCTAssertTrue(persistedTitleField.waitForExistence(timeout: 5))
        let persistedTitle = persistedTitleField.value as? String ??
            persistedTitleField.label
        XCTAssertEqual(persistedTitle, updatedTitle)
        try capture(
            "\(screenshotPrefix)-task-detail-sidebar-autosave-restored",
            app: app
        )
    }

    @MainActor
    func testTaskDetailPhoneTabNavigationKeepsAutosavedChanges() throws {
        #if os(macOS)
        throw XCTSkip("Phone tab navigation is available on iPhone.")
        #else
        let app = launchApp(
            route: "task-detail",
            replacesDemoDataOnLaunch: true,
            taskTitle: "Read Apple HIG",
            autosaveDelayMilliseconds: 30000
        )

        ensureTaskDetailIsReady(named: "Read Apple HIG", in: app)
        if app.descendants(matching: .any)["ipad.splitNavigation"]
            .waitForExistence(timeout: 2)
        {
            throw XCTSkip("Phone tab navigation is available on iPhone.")
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["phone.tabView"]
                .waitForExistence(timeout: 5),
            "The compact iPhone shell must expose its tab view after launch."
        )
        let screenshotPrefix = platformScreenshotPrefix(in: app)

        let dueDateToggle = app.descendants(matching: .any)[
            "task.editor.due.toggle"
        ].firstMatch
        scrollUntilHittable(dueDateToggle, direction: .up, in: app)
        XCTAssertTrue(
            dueDateToggle.waitForExistence(timeout: 5) &&
                dueDateToggle.isHittable
        )
        XCTAssertEqual(dueDateToggle.value as? String, "0")
        dueDateToggle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)
        ).tap()
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                dueDateToggle.value as? String == "1"
            }
        )
        XCTAssertFalse(app.buttons["task.editor.save"].firstMatch.exists)

        openSection(
            "Today",
            tabIdentifier: "phone.tab.today",
            sidebarIdentifier: "sidebar.Today",
            in: app
        )

        XCTAssertTrue(
            app.descendants(matching: .any)["task.detail"]
                .firstMatch.waitForNonExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["editor.discard.confirm"].exists)
        XCTAssertTrue(homeIsReady(in: app))
        XCTAssertTrue(
            app.descendants(matching: .any)["phone.tab.today"].firstMatch.isSelected
        )

        openTaskDetailFromTasks(named: "Read Apple HIG", in: app)
        XCTAssertTrue(taskDetailIsReady(in: app))
        let persistedDueDateToggle = app.descendants(matching: .any)[
            "task.editor.due.toggle"
        ].firstMatch
        scrollUntilHittable(persistedDueDateToggle, direction: .up, in: app)
        XCTAssertTrue(persistedDueDateToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(
            persistedDueDateToggle.value as? String,
            "1",
            "Phone tab navigation must flush the pending due-date change."
        )
        try capture(
            "\(screenshotPrefix)-task-detail-phone-tab-autosave-restored",
            app: app
        )
        #endif
    }

    @MainActor
    func testCompletingChecklistItemMovesItBelowIncompleteWork() throws {
        #if os(macOS)
        throw XCTSkip("Checklist movement is visually verified in the compact iPhone layout.")
        #else
        let app = launchApp(
            route: "task-detail",
            replacesDemoDataOnLaunch: true,
            taskTitle: "Design macOS UI"
        )
        ensureTaskDetailIsReady(named: "Design macOS UI", in: app)
        let screenshotPrefix = platformScreenshotPrefix(in: app)

        let incomplete = app.buttons["Polish timeline"].firstMatch
        let completedFirst = app.buttons["Align task detail"].firstMatch
        let completedSecond = app.buttons["Tighten sidebar"].firstMatch
        scrollUntilHittable(incomplete, direction: .up, in: app)

        XCTAssertTrue(incomplete.waitForExistence(timeout: 5) && incomplete.isHittable)
        XCTAssertEqual(incomplete.value as? String, "Not completed")
        XCTAssertTrue(completedFirst.waitForExistence(timeout: 3))
        XCTAssertLessThan(incomplete.frame.minY, completedFirst.frame.minY)
        try capture(
            "\(screenshotPrefix)-checklist-incomplete-before-completed",
            app: app
        )

        activate(incomplete)
        scrollUntilHittable(incomplete, direction: .up, in: app)

        XCTAssertTrue(
            waitUntil(timeout: 5) {
                incomplete.value as? String == "Completed" &&
                    completedSecond.exists &&
                    completedSecond.frame.minY < incomplete.frame.minY
            },
            "The newly completed checklist item must update its state and move after every completed item."
        )
        try capture(
            "\(screenshotPrefix)-checklist-completed-moved-to-bottom",
            app: app
        )

        activate(incomplete)
        scrollUntilHittable(incomplete, direction: .up, in: app)
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                incomplete.value as? String == "Not completed" &&
                    completedFirst.exists &&
                    incomplete.frame.minY < completedFirst.frame.minY
            },
            "Uncompleting must restore the checklist item above completed work."
        )
        try capture(
            "\(screenshotPrefix)-checklist-uncompleted-restored-position",
            app: app
        )
        #endif
    }

    @MainActor
    func testTaskDetailSystemBackPreservesExpandedTaskTree() throws {
        #if os(macOS)
        throw XCTSkip("This route-preservation screenshot runs on iPhone and iPad simulators.")
        #else
        let app = launchApp(route: "tasks")
        if app.descendants(matching: .any)["tasks.view"]
            .waitForExistence(timeout: 8) == false
        {
            openSection(
                "Tasks",
                tabIdentifier: "phone.tab.tasks",
                sidebarIdentifier: "sidebar.Tasks",
                in: app
            )
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["tasks.view"].waitForExistence(timeout: 5)
        )

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
        if app.descendants(matching: .any)["tasks.view"]
            .waitForExistence(timeout: 8) == false
        {
            openSection(
                "Tasks",
                tabIdentifier: "phone.tab.tasks",
                sidebarIdentifier: "sidebar.Tasks",
                in: app
            )
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["tasks.view"].waitForExistence(timeout: 5)
        )

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

        let rangePicker = app.segmentedControls
            .containing(.button, identifier: "Day")
            .firstMatch
        scrollUntilHittable(
            rangePicker,
            direction: .up,
            maximumScrolls: 14,
            in: app
        )
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
    func testInboxItemCreatesChildTaskThroughSharedHierarchyPicker() throws {
        #if os(macOS)
        throw XCTSkip("The Inbox task-routing interaction requires an iOS simulator.")
        #else
        let app = launchApp(replacesDemoDataOnLaunch: true)
        let screenshotPrefix = platformScreenshotPrefix(in: app)
        let createdItem = createInboxItem(
            "Prepare release screenshots",
            in: app
        )
        let menu = createdItem.menu
        activate(menu)

        let route = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "inbox.route.childTask."
            ))
            .firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 3) && route.isHittable)
        try capture("\(screenshotPrefix)-inbox-route-menu", app: app)
        activate(route)

        let picker = app.descendants(matching: .any)[
            "inbox.childTask.parentPicker"
        ].firstMatch
        XCTAssertTrue(
            waitForElement(
                picker,
                timeout: 5,
                diagnosticName: "inbox-child-task-parent-picker",
                in: app
            )
        )

        let search = app.searchFields["Search tasks, paths, or notes"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3) && search.isHittable)
        activate(search)
        search.typeText("SwiftData Docs")

        let target = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "inbox.childTask.parentPicker.select."
            ))
            .matching(NSPredicate(format: "label == %@", "SwiftData Docs"))
            .firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 3) && target.isHittable)
        waitForScreenshotTransition()
        try capture(
            "\(screenshotPrefix)-inbox-child-task-parent-picker",
            app: app
        )
        activate(target)

        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertTrue(menu.waitForNonExistence(timeout: 5))
        XCTAssertTrue(createdItem.titleField.waitForNonExistence(timeout: 5))
        try capture(
            "\(screenshotPrefix)-inbox-created-child-task",
            app: app
        )
        #endif
    }

    @MainActor
    func testInboxItemCreatesTaskThroughSharedCategoryPicker() throws {
        #if os(macOS)
        throw XCTSkip("The Inbox category-routing interaction requires an iOS simulator.")
        #else
        let app = launchApp(replacesDemoDataOnLaunch: true)
        let screenshotPrefix = platformScreenshotPrefix(in: app)
        let createdItem = createInboxItem("Plan reading weekend", in: app)
        let menu = createdItem.menu
        activate(menu)

        let route = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "inbox.route.categoryTask."
            ))
            .firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 3) && route.isHittable)
        activate(route)

        let picker = app.descendants(matching: .any)[
            "inbox.categoryTask.categoryPicker"
        ].firstMatch
        XCTAssertTrue(
            waitForElement(
                picker,
                timeout: 5,
                diagnosticName: "inbox-category-task-picker",
                in: app
            )
        )

        let search = app.searchFields["Search categories"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3) && search.isHittable)
        activate(search)
        search.typeText("Study")

        let target = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "inbox.categoryTask.categoryPicker.select."
            ))
            .matching(NSPredicate(format: "label == %@", "Study"))
            .firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 3) && target.isHittable)
        waitForScreenshotTransition()
        try capture(
            "\(screenshotPrefix)-inbox-category-task-picker",
            app: app
        )
        activate(target)

        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertTrue(menu.waitForNonExistence(timeout: 5))
        XCTAssertTrue(createdItem.titleField.waitForNonExistence(timeout: 5))
        try capture(
            "\(screenshotPrefix)-inbox-created-category-task",
            app: app
        )
        #endif
    }

    @MainActor
    func testInboxItemCreatesChecklistThroughSharedHierarchyPicker() throws {
        #if os(macOS)
        throw XCTSkip("The Inbox checklist-routing interaction requires an iOS simulator.")
        #else
        let app = launchApp(replacesDemoDataOnLaunch: true)
        let screenshotPrefix = platformScreenshotPrefix(in: app)
        let createdItem = createInboxItem("Route release checklist", in: app)
        let menu = createdItem.menu
        activate(menu)

        let route = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "inbox.route.checklistItem."
            ))
            .firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 3) && route.isHittable)
        activate(route)

        let picker = app.descendants(matching: .any)[
            "inbox.checklistItem.taskPicker"
        ].firstMatch
        XCTAssertTrue(
            waitForElement(
                picker,
                timeout: 5,
                diagnosticName: "inbox-checklist-task-picker",
                in: app
            )
        )

        let search = app.searchFields["Search tasks, paths, or notes"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3) && search.isHittable)
        activate(search)
        search.typeText("SwiftData Docs")

        let target = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "inbox.checklistItem.taskPicker.select."
            ))
            .matching(NSPredicate(format: "label == %@", "SwiftData Docs"))
            .firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 3) && target.isHittable)
        waitForScreenshotTransition()
        try capture(
            "\(screenshotPrefix)-inbox-checklist-task-picker",
            app: app
        )
        activate(target)

        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertTrue(menu.waitForNonExistence(timeout: 5))
        XCTAssertTrue(createdItem.titleField.waitForNonExistence(timeout: 5))
        try capture(
            "\(screenshotPrefix)-inbox-created-checklist-item",
            app: app
        )
        #endif
    }

    @MainActor
    func testMacInboxItemsSupportAllManualRoutes() throws {
        #if os(macOS)
        let app = launchApp(
            route: "inbox",
            replacesDemoDataOnLaunch: true
        )

        let childItem = createInboxItem(
            "Prepare release screenshots",
            in: app
        )
        let childMenu = childItem.menu
        activate(childMenu)

        let childRoute = inboxRouteAction(
            identifierPrefix: "inbox.route.childTask.",
            macLabel: "Create as Subtask…",
            in: app
        )
        let categoryRoute = inboxRouteAction(
            identifierPrefix: "inbox.route.categoryTask.",
            macLabel: "Create in Category…",
            in: app
        )
        let checklistRoute = inboxRouteAction(
            identifierPrefix: "inbox.route.checklistItem.",
            macLabel: "Add as Checklist Item…",
            in: app
        )
        XCTAssertTrue(
            childRoute.waitForExistence(timeout: 3) &&
                childRoute.isHittable
        )
        XCTAssertTrue(
            categoryRoute.waitForExistence(timeout: 3) &&
                categoryRoute.isHittable
        )
        XCTAssertTrue(
            checklistRoute.waitForExistence(timeout: 3) &&
                checklistRoute.isHittable
        )
        try capture("mac-inbox-manual-route-menu", app: app)
        activate(childRoute)
        try completeInboxPickerRoute(
            pickerIdentifier: "inbox.childTask.parentPicker",
            searchPrompt: "Search tasks, paths, or notes",
            searchTerm: "SwiftData Docs",
            choiceIdentifierPrefix: "inbox.childTask.parentPicker.select.",
            choiceLabel: "SwiftData Docs",
            screenshotName: "mac-inbox-child-task-picker",
            in: app
        )
        XCTAssertTrue(childMenu.waitForNonExistence(timeout: 5))
        XCTAssertTrue(childItem.titleField.waitForNonExistence(timeout: 5))

        let categoryItem = createInboxItem(
            "Plan reading weekend",
            in: app
        )
        let categoryMenu = categoryItem.menu
        activate(categoryMenu)
        let secondCategoryRoute = inboxRouteAction(
            identifierPrefix: "inbox.route.categoryTask.",
            macLabel: "Create in Category…",
            in: app
        )
        XCTAssertTrue(
            secondCategoryRoute.waitForExistence(timeout: 3) &&
                secondCategoryRoute.isHittable
        )
        activate(secondCategoryRoute)
        try completeInboxPickerRoute(
            pickerIdentifier: "inbox.categoryTask.categoryPicker",
            searchPrompt: "Search categories",
            searchTerm: "Study",
            choiceIdentifierPrefix: "inbox.categoryTask.categoryPicker.select.",
            choiceLabel: "Study",
            screenshotName: "mac-inbox-category-picker",
            in: app
        )
        XCTAssertTrue(categoryMenu.waitForNonExistence(timeout: 5))
        XCTAssertTrue(categoryItem.titleField.waitForNonExistence(timeout: 5))

        let checklistItem = createInboxItem(
            "Route release checklist",
            in: app
        )
        let checklistMenu = checklistItem.menu
        activate(checklistMenu)
        let secondChecklistRoute = inboxRouteAction(
            identifierPrefix: "inbox.route.checklistItem.",
            macLabel: "Add as Checklist Item…",
            in: app
        )
        XCTAssertTrue(
            secondChecklistRoute.waitForExistence(timeout: 3) &&
                secondChecklistRoute.isHittable
        )
        activate(secondChecklistRoute)
        try completeInboxPickerRoute(
            pickerIdentifier: "inbox.checklistItem.taskPicker",
            searchPrompt: "Search tasks, paths, or notes",
            searchTerm: "SwiftData Docs",
            choiceIdentifierPrefix: "inbox.checklistItem.taskPicker.select.",
            choiceLabel: "SwiftData Docs",
            screenshotName: "mac-inbox-checklist-picker",
            in: app
        )
        XCTAssertTrue(checklistMenu.waitForNonExistence(timeout: 5))
        XCTAssertTrue(checklistItem.titleField.waitForNonExistence(timeout: 5))
        try capture("mac-inbox-manual-routes-completed", app: app)
        #else
        throw XCTSkip("The macOS Inbox routing smoke test requires macOS.")
        #endif
    }

    @MainActor
    func testInboxCompletedItemStaysReachableAndCanBeReopened() throws {
        let app = launchApp(
            route: "inbox",
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: ["--uitesting-inbox-suggestion"]
        )
        let screenshotPrefix = platformScreenshotPrefix(in: app)
        openSection(
            "Inbox",
            tabIdentifier: "phone.tab.inbox",
            sidebarIdentifier: "sidebar.Inbox",
            in: app
        )
        let seededTitle = "Prepare the design review brief"
        let initialTitleField = app.textFields
            .matching(NSPredicate(format: "value == %@", seededTitle))
            .firstMatch
        XCTAssertTrue(initialTitleField.waitForExistence(timeout: 8))
        let titleIdentifierPrefix = "inbox.item."
        XCTAssertTrue(initialTitleField.identifier.hasPrefix(titleIdentifierPrefix))
        let itemID = String(
            initialTitleField.identifier.dropFirst(titleIdentifierPrefix.count)
        )
        let completionIdentifier = "inbox.item.completion.\(itemID)"
        let titleIdentifier = "\(titleIdentifierPrefix)\(itemID)"
        let completion = app.buttons[completionIdentifier].firstMatch

        XCTAssertTrue(
            initialTitleField.waitForExistence(timeout: 5) &&
                initialTitleField.isHittable &&
                completion.waitForExistence(timeout: 5) &&
                completion.isHittable
        )
        XCTAssertEqual(completion.value as? String, "Not completed")
        activate(completion)

        XCTAssertTrue(waitUntil(timeout: 5) {
            initialTitleField.exists && initialTitleField.isHittable &&
                completion.exists && completion.isHittable &&
                completion.value as? String == "Completed"
        })
        try capture("\(screenshotPrefix)-inbox-completed-reachable", app: app)

        let completedTitleFields = app.textFields.matching(identifier: titleIdentifier)
        let completedCompletions = app.buttons.matching(identifier: completionIdentifier)
        XCTAssertTrue(waitUntil(timeout: 5) {
            completedTitleFields.count == 1 &&
                completedCompletions.count == 1 &&
                completedTitleFields.firstMatch.isHittable &&
                completedCompletions.firstMatch.isHittable &&
                completedCompletions.firstMatch.value as? String == "Completed"
        })
        let completedTarget = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ AND value == %@",
                completionIdentifier,
                "Completed"
            )
        ).firstMatch
        XCTAssertTrue(completedTarget.waitForExistence(timeout: 3) && completedTarget.isHittable)
        activate(completedTarget)

        let reopenedTitleFields = app.textFields.matching(identifier: titleIdentifier)
        let reopenedCompletions = app.buttons.matching(identifier: completionIdentifier)
        XCTAssertTrue(waitUntil(timeout: 5) {
            reopenedTitleFields.count == 1 &&
                reopenedCompletions.count == 1 &&
                reopenedTitleFields.firstMatch.isHittable &&
                reopenedCompletions.firstMatch.isHittable &&
                reopenedCompletions.firstMatch.value as? String == "Not completed"
        })
        try capture("\(screenshotPrefix)-inbox-reopened", app: app)
    }

    @MainActor
    func testInboxNativeCardsExplainAndApplyAllGeneratedDestinations() throws {
        #if os(macOS)
        throw XCTSkip("Inset-grouped card geometry is verified on iPhone and iPad.")
        #else
        let app = launchApp(
            contentSizeCategory: "UICTContentSizeCategoryL",
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

        XCTAssertTrue(captureField.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["inbox.completed.disclosure"].firstMatch
                .waitForExistence(timeout: 3)
        )

        let captureCard = app.cells
            .containing(.textField, identifier: captureField.identifier)
            .firstMatch
        XCTAssertTrue(captureCard.exists)
        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(captureCard.frame.minX, windowFrame.minX + 12)
        XCTAssertLessThan(captureCard.frame.maxX, windowFrame.maxX - 12)

        let destinations = [
            (
                kind: "childTask",
                itemTitle: "Prepare the design review brief",
                summary: "Create as a subtask of Design System",
                applyTitle: "Create Subtask",
                screenshotName: "inbox-ai-child-task"
            ),
            (
                kind: "category",
                itemTitle: "Schedule the client kickoff",
                summary: "Create in Work",
                applyTitle: "Create Task",
                screenshotName: "inbox-ai-category-task"
            ),
            (
                kind: "checklist",
                itemTitle: "Confirm the review attendees",
                summary: "Add to Design System checklist",
                applyTitle: "Add Checklist Item",
                screenshotName: "inbox-ai-checklist-item"
            ),
        ]

        for (index, destination) in destinations.enumerated() {
            let suggestion = app.descendants(matching: .any)
                .matching(NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    "inbox.suggestion.ready.\(destination.kind)."
                ))
                .firstMatch
            let apply = app.buttons
                .matching(NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    "inbox.suggestion.apply.\(destination.kind)."
                ))
                .firstMatch
            let itemField = app.textFields
                .matching(NSPredicate(
                    format: "value == %@",
                    destination.itemTitle
                ))
                .firstMatch

            XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
            XCTAssertEqual(suggestion.label, destination.summary)
            XCTAssertTrue(itemField.waitForExistence(timeout: 5))
            let itemID = try XCTUnwrap(
                suggestion.identifier.split(separator: ".").last.map(String.init)
            )
            let completion = app.buttons[
                "inbox.item.completion.\(itemID)"
            ].firstMatch
            let discard = app.buttons[
                "inbox.suggestion.discard.\(itemID)"
            ].firstMatch
            scrollUntilHittable(apply, direction: .up, in: app)
            XCTAssertTrue(completion.waitForExistence(timeout: 3))
            XCTAssertTrue(apply.isHittable)
            XCTAssertTrue(discard.waitForExistence(timeout: 3) && discard.isHittable)
            XCTAssertEqual(apply.label, destination.applyTitle)
            XCTAssertGreaterThanOrEqual(apply.frame.width, 44)
            XCTAssertGreaterThanOrEqual(apply.frame.height, 44)
            XCTAssertGreaterThanOrEqual(discard.frame.width, 44)
            XCTAssertGreaterThanOrEqual(discard.frame.height, 44)
            XCTAssertEqual(discard.frame.midY, apply.frame.midY, accuracy: 1)
            if app.frame.width < 600 {
                XCTAssertLessThanOrEqual(apply.frame.width, 50)
                XCTAssertLessThanOrEqual(apply.frame.height, 50)
                XCTAssertLessThanOrEqual(discard.frame.width, 50)
                XCTAssertLessThanOrEqual(discard.frame.height, 50)
            }

            let itemCard = app.cells
                .containing(.textField, identifier: itemField.identifier)
                .firstMatch
            XCTAssertTrue(itemCard.exists)
            XCTAssertGreaterThan(itemCard.frame.minX, windowFrame.minX + 12)
            XCTAssertLessThan(itemCard.frame.maxX, windowFrame.maxX - 12)

            if index == 0 {
                XCTAssertEqual(
                    itemField.frame.midY,
                    completion.frame.midY,
                    accuracy: 2,
                    "The Inbox title must align with its completion control."
                )
                let completionMarkLeadingInset = max(
                    0,
                    (completion.frame.width - 24) / 2
                )
                XCTAssertEqual(
                    suggestion.frame.minX,
                    completion.frame.minX + completionMarkLeadingInset,
                    accuracy: 2,
                    "The suggestion must align with the visible completion mark."
                )
            }
            XCTAssertGreaterThan(
                suggestion.frame.minY,
                itemField.frame.maxY,
                "The suggestion must remain below the Inbox title."
            )
            XCTAssertGreaterThan(
                apply.frame.minY,
                suggestion.frame.maxY,
                "Actions must remain below the destination summary."
            )
            XCTAssertLessThan(
                discard.frame.maxX,
                apply.frame.minX,
                "Dismiss and apply must stay on opposite sides."
            )

            try capture("\(destination.screenshotName)-ready", app: app)
        }
        #endif
    }

    @MainActor
    func testInboxChildTaskSuggestionCreatesUnderItsParent() throws {
        #if os(macOS)
        throw XCTSkip("The Inbox route is verified on iPhone and iPad.")
        #else
        let app = launchSeededInboxSuggestions()
        applySeededInboxSuggestion(
            kind: "childTask",
            itemTitle: "Prepare the design review brief",
            summary: "Create as a subtask of Design System",
            in: app
        )

        openSection(
            "Tasks",
            tabIdentifier: "phone.tab.tasks",
            sidebarIdentifier: "sidebar.Tasks",
            in: app
        )
        expandTask(named: "Time Tracker App", in: app)
        expandTask(named: "Design System", in: app)
        let createdTask = taskRow(
            named: "Prepare the design review brief",
            in: app
        )
        XCTAssertTrue(createdTask.waitForExistence(timeout: 5))
        XCTAssertTrue(
            (createdTask.value as? String ?? "")
                .localizedCaseInsensitiveContains("Design System")
        )
        activate(createdTask)

        let parent = app.descendants(matching: .any)[
            "task.editor.parent"
        ].firstMatch
        scrollUntilHittable(parent, direction: .up, in: app)
        XCTAssertTrue(parent.waitForExistence(timeout: 5))
        XCTAssertTrue(
            (parent.value as? String ?? parent.label)
                .localizedCaseInsensitiveContains("Design System")
        )
        try capture("inbox-ai-child-task-created-under-parent", app: app)
        #endif
    }

    @MainActor
    func testInboxCategorySuggestionCreatesARootTaskInThatCategory() throws {
        #if os(macOS)
        throw XCTSkip("The Inbox route is verified on iPhone and iPad.")
        #else
        let app = launchSeededInboxSuggestions()
        applySeededInboxSuggestion(
            kind: "category",
            itemTitle: "Schedule the client kickoff",
            summary: "Create in Work",
            in: app
        )

        openSection(
            "Tasks",
            tabIdentifier: "phone.tab.tasks",
            sidebarIdentifier: "sidebar.Tasks",
            in: app
        )
        let createdTask = taskRow(
            named: "Schedule the client kickoff",
            in: app
        )
        scrollUntilHittable(createdTask, direction: .up, in: app)
        XCTAssertTrue(createdTask.waitForExistence(timeout: 5) && createdTask.isHittable)
        activate(createdTask)

        let category = app.descendants(matching: .any)[
            "task.editor.category"
        ].firstMatch
        scrollUntilHittable(category, direction: .up, in: app)
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertEqual(category.value as? String ?? category.label, "Work")
        try capture("inbox-ai-category-root-task-created", app: app)
        #endif
    }

    @MainActor
    func testInboxChecklistSuggestionCreatesAnItemInTheTargetTask() throws {
        #if os(macOS)
        throw XCTSkip("The Inbox route is verified on iPhone and iPad.")
        #else
        let app = launchSeededInboxSuggestions()
        applySeededInboxSuggestion(
            kind: "checklist",
            itemTitle: "Confirm the review attendees",
            summary: "Add to Design System checklist",
            in: app
        )

        openSection(
            "Tasks",
            tabIdentifier: "phone.tab.tasks",
            sidebarIdentifier: "sidebar.Tasks",
            in: app
        )
        expandTask(named: "Time Tracker App", in: app)
        let targetTask = taskRow(named: "Design System", in: app)
        XCTAssertTrue(targetTask.waitForExistence(timeout: 5) && targetTask.isHittable)
        activate(targetTask)

        let checklistItem = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "task.editor.checklist.completion.",
                "Confirm the review attendees"
            ))
            .firstMatch
        scrollUntilHittable(checklistItem, direction: .up, in: app)
        XCTAssertTrue(
            checklistItem.waitForExistence(timeout: 5) &&
                checklistItem.isHittable
        )
        try capture("inbox-ai-checklist-item-created", app: app)
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
    func testRecurringQuantityTaskCreationAndProgress() throws {
        #if os(macOS)
        throw XCTSkip(
            "Recurring quantity interaction is verified on owned iPhone and iPad simulators."
        )
        #else
        let enteredTaskTitle = "Pushups"
        let app = launchApp(route: "tasks", seedsDemoData: false)
        let screenshotPrefix = platformScreenshotPrefix(in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["tasks.view"]
                .waitForExistence(timeout: 15)
        )

        let addTaskMenu = app.descendants(matching: .any)[
            "tasks.add"
        ].firstMatch
        XCTAssertTrue(
            addTaskMenu.waitForExistence(timeout: 5) &&
                addTaskMenu.isHittable
        )
        activate(addTaskMenu)
        let addRootTask = app.descendants(matching: .any)[
            "tasks.addRoot"
        ].firstMatch
        XCTAssertTrue(
            addRootTask.waitForExistence(timeout: 3) &&
                addRootTask.isHittable
        )
        activate(addRootTask)

        let editor = app.descendants(matching: .any)[
            "task.editor"
        ].firstMatch
        let titleField = app.descendants(matching: .any)[
            "task.editor.title.field"
        ].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(
            titleField.waitForExistence(timeout: 3) &&
                titleField.isHittable
        )
        activate(titleField)
        replaceTextCharacterByCharacter(enteredTaskTitle, in: titleField)
        submitTaskTitleIfKeyboardIsVisible(titleField, in: app)
        let taskTitle = try XCTUnwrap(titleField.value as? String)
        XCTAssertEqual(taskTitle, enteredTaskTitle)

        let quantityToggle = app.descendants(matching: .any)[
            "task.editor.quantity.toggle"
        ].firstMatch
        scrollUntilHittable(quantityToggle, direction: .up, in: app)
        XCTAssertTrue(
            quantityToggle.waitForExistence(timeout: 3) &&
                quantityToggle.isHittable,
            "Quantity toggle must be visible after dismissing the title keyboard."
        )
        quantityToggle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)
        ).tap()

        let targetField = app.descendants(matching: .any)[
            "task.editor.quantity.target"
        ].firstMatch
        let unitField = app.descendants(matching: .any)[
            "task.editor.quantity.unit"
        ].firstMatch
        scrollUntilHittable(unitField, direction: .up, in: app)
        XCTAssertTrue(unitField.waitForExistence(timeout: 3))
        XCTAssertTrue(
            scrollUntilFullyVisibleBelowNavigationBar(
                unitField,
                navigationBarTitle: "New Task",
                in: app
            )
        )
        unitField.coordinate(
            withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)
        ).tap()
        unitField.typeText("reps")
        unitField.typeText(XCUIKeyboardKey.return.rawValue)
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        )

        scrollUntilHittable(targetField, direction: .up, in: app)
        XCTAssertTrue(targetField.waitForExistence(timeout: 3))
        XCTAssertTrue(
            scrollUntilFullyVisibleBelowNavigationBar(
                targetField,
                navigationBarTitle: "New Task",
                in: app
            )
        )
        replaceNumericText("50", in: targetField)
        XCTAssertEqual(targetField.value as? String, "50")
        let keyboardDone = hittableButton(
            identifier: "task.editor.keyboard.done",
            localizedLabels: ["Done"],
            in: app
        )
        guard activateVisibleButton(
            keyboardDone,
            diagnosticName: "task editor keyboard Done"
        ) else { return }

        let recurrenceToggle = app.descendants(matching: .any)[
            "task.editor.recurrence.daily"
        ].firstMatch
        scrollUntilHittable(recurrenceToggle, direction: .up, in: app)
        XCTAssertTrue(
            recurrenceToggle.waitForExistence(timeout: 3) &&
                recurrenceToggle.isHittable,
            "Daily recurrence toggle must be visible below the quantity editor."
        )
        recurrenceToggle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)
        ).tap()
        let quantityFooter = app.staticTexts[
            "Today’s generated child task copies the 50 reps goal. Record progress on that task."
        ].firstMatch
        scrollUntilHittable(quantityFooter, direction: .up, in: app)
        XCTAssertTrue(quantityFooter.waitForExistence(timeout: 3))
        if screenshotPrefix == "iphone" {
            try capture(
                "\(screenshotPrefix)-recurring-quantity-editor",
                app: app
            )
        }

        let save = app.buttons["task.editor.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 3) && save.isHittable)
        activate(save)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 8))

        expandTask(named: taskTitle, in: app)
        let templateRow = recurringTaskRow(
            named: taskTitle,
            role: "Daily Template",
            in: app
        )
        let generatedRow = recurringTaskRow(
            named: taskTitle,
            role: "Today’s Task",
            in: app
        )
        scrollUntilHittable(generatedRow, direction: .up, in: app)
        XCTAssertTrue(
            templateRow.waitForExistence(timeout: 5) &&
                generatedRow.waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            (templateRow.value as? String ?? "").contains("0 / 50 reps")
        )
        XCTAssertTrue(
            (generatedRow.value as? String ?? "").contains("0 / 50 reps")
        )
        try capture(
            "\(screenshotPrefix)-recurring-quantity-task-tree",
            app: app
        )

        scrollUntilHittable(templateRow, direction: .down, in: app)
        XCTAssertTrue(templateRow.isHittable)
        activate(templateRow)
        XCTAssertTrue(taskDetailIsReady(in: app))
        let templateContext = app.staticTexts[
            "This is the recurring template. Record progress on today’s generated task."
        ].firstMatch
        XCTAssertTrue(
            templateContext.waitForExistence(timeout: 5) &&
                templateContext.isHittable
        )
        XCTAssertFalse(
            app.buttons["task.detail.quantity.record"].firstMatch.exists
        )
        try capture(
            "\(screenshotPrefix)-recurring-quantity-template",
            app: app
        )

        let back = taskDetailBackButton(to: "Tasks", in: app)
        XCTAssertTrue(back.waitForExistence(timeout: 5) && back.isHittable)
        activate(back)
        XCTAssertTrue(
            app.descendants(matching: .any)["task.detail"]
                .waitForNonExistence(timeout: 5)
        )

        let currentGeneratedRow = recurringTaskRow(
            named: taskTitle,
            role: "Today’s Task",
            in: app
        )
        scrollUntilHittable(currentGeneratedRow, direction: .up, in: app)
        XCTAssertTrue(
            currentGeneratedRow.waitForExistence(timeout: 5) &&
                currentGeneratedRow.isHittable
        )
        activate(currentGeneratedRow)
        XCTAssertTrue(taskDetailIsReady(in: app))
        let occurrence = app.descendants(matching: .any)[
            "task.detail.quantity.occurrence"
        ].firstMatch
        let progress = app.descendants(matching: .any)[
            "task.detail.quantity.progress"
        ].firstMatch
        let record = app.buttons[
            "task.detail.quantity.record"
        ].firstMatch
        gentlyScrollUntilHittable(record, direction: .up, in: app)
        XCTAssertTrue(occurrence.waitForExistence(timeout: 5))
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertTrue(record.waitForExistence(timeout: 5) && record.isHittable)
        activate(record)

        let amountField = app.descendants(matching: .any)[
            "task.detail.quantity.amount"
        ].firstMatch
        XCTAssertTrue(
            amountField.waitForExistence(timeout: 5) &&
                amountField.isHittable
        )
        replaceNumericText("20", in: amountField)
        XCTAssertEqual(amountField.value as? String, "20")
        let progressKeyboardDone = hittableButton(
            identifier: "task.detail.quantity.keyboard.done",
            localizedLabels: ["Done"],
            in: app
        )
        guard activateVisibleButton(
            progressKeyboardDone,
            diagnosticName: "quantity progress keyboard Done"
        ) else { return }
        let saveProgress = app.buttons[
            "task.detail.quantity.save"
        ].firstMatch
        XCTAssertTrue(waitUntil(timeout: 3) {
            saveProgress.exists && saveProgress.isHittable
        })
        activate(saveProgress)
        XCTAssertTrue(amountField.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) {
            let value = progress.value as? String ?? ""
            return value.contains("20") && value.contains("50")
        })
        let history = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "task.detail.quantity.entry."
            ))
            .firstMatch
        gentlyScrollUntilHittable(history, direction: .up, in: app)
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        try capture(
            "\(screenshotPrefix)-recurring-quantity-progress-20-of-50",
            app: app
        )
        #endif
    }

    @MainActor
    func testEveryAIPromptExposesMarkdownPreviewAndFixedContract() throws {
        // Prompt editor presentation on macOS lives in a separate Settings
        // scene whose window placement makes scripted navigation unreliable;
        // macOS coverage comes from the shared editor source contract tests.
        #if targetEnvironment(simulator)
        let app = launchApp(route: "settings")
        let screenshotPrefix = platformScreenshotPrefix(in: app)
        let settingsView = app.descendants(matching: .any)[
            "settings.view"
        ].firstMatch
        if !settingsView.waitForExistence(timeout: 3) {
            openSettings(in: app)
        }
        XCTAssertTrue(
            settingsView.waitForExistence(timeout: 8),
            "The settings surface must be visible."
        )
        let intelligence = app.descendants(matching: .any)[
            "settings.category.intelligence"
        ].firstMatch
        scrollUntilHittable(intelligence, direction: .up, in: app)
        // The macOS Settings window can open on another display or stay
        // behind the main window, making isHittable/activate unreliable;
        // a coordinate click still reaches the row.
        #if os(macOS)
        XCTAssertTrue(
            intelligence.waitForExistence(timeout: 5),
            "The intelligence settings category must be available."
        )
        intelligence.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        #else
        XCTAssertTrue(
            intelligence.waitForExistence(timeout: 5) && intelligence.isHittable,
            "The intelligence settings category must be available."
        )
        activate(intelligence)
        #endif

        for kind in ["inboxRouting", "checklistVisual", "taskPlan"] {
            let edit = app.descendants(matching: .any)[
                "settings.llm.prompt.\(kind).edit"
            ].firstMatch
            scrollUntilHittable(edit, direction: .up, in: app)
            #if os(macOS)
            XCTAssertTrue(edit.waitForExistence(timeout: 5))
            #else
            XCTAssertTrue(edit.waitForExistence(timeout: 5) && edit.isHittable)
            #endif
            activate(edit)

            let mode = app.descendants(matching: .any)[
                "settings.llm.prompt.\(kind).mode"
            ].firstMatch
            XCTAssertTrue(
                mode.waitForExistence(timeout: 5),
                "Every prompt editor must offer an edit/preview mode switch."
            )
            let previewSegment = mode.buttons.element(boundBy: 1)
            XCTAssertTrue(previewSegment.exists && previewSegment.isHittable)
            activate(previewSegment)
            let preview = app.descendants(matching: .any)[
                "settings.llm.prompt.\(kind).preview"
            ].firstMatch
            XCTAssertTrue(
                preview.waitForExistence(timeout: 5),
                "Every prompt editor must render a Markdown preview."
            )
            #if !os(macOS)
            if kind == "taskPlan" {
                try capture(
                    "\(screenshotPrefix)-ai-prompt-task-plan-default-preview",
                    app: app
                )
            }
            #endif

            let effectiveRequest = app.descendants(matching: .any)[
                "settings.llm.prompt.\(kind).effectiveRequest"
            ].firstMatch
            scrollUntilHittable(effectiveRequest, direction: .up, in: app)
            XCTAssertTrue(
                effectiveRequest.waitForExistence(timeout: 5),
                "Every prompt editor must disclose the effective provider request."
            )
            let fixedRules = app.descendants(matching: .any)[
                "settings.llm.prompt.\(kind).fixedRules"
            ].firstMatch
            scrollUntilHittable(fixedRules, direction: .up, in: app)
            XCTAssertTrue(
                fixedRules.waitForExistence(timeout: 5),
                "Every prompt editor must expose the fixed response contract."
            )
            let allowedVisuals = app.descendants(matching: .any)[
                "settings.llm.prompt.\(kind).allowedVisuals"
            ].firstMatch
            scrollUntilHittable(allowedVisuals, direction: .up, in: app)
            XCTAssertTrue(
                allowedVisuals.waitForExistence(timeout: 5),
                "Every prompt editor must expose the allowed symbols and colors."
            )
            #if !os(macOS)
            if kind == "inboxRouting" || kind == "taskPlan" {
                activate(fixedRules)
                try capture(
                    "\(screenshotPrefix)-ai-prompt-\(kind)-fixed-contract",
                    app: app
                )
            }
            #endif

            let cancel = app.buttons[
                "settings.llm.prompt.\(kind).cancel"
            ].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 3))
            activate(cancel)
            let editor = app.descendants(matching: .any)[
                "settings.llm.prompt.\(kind).editor"
            ].firstMatch
            XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        }
        #endif
    }

    @MainActor
    func testEveryAIPromptCanBeEditedSavedRestoredAndSafelyDiscarded() throws {
        #if targetEnvironment(simulator)
        let app = launchApp(route: "settings")
        let settingsView = app.descendants(matching: .any)[
            "settings.view"
        ].firstMatch
        if !settingsView.waitForExistence(timeout: 3) {
            openSettings(in: app)
        }
        XCTAssertTrue(settingsView.waitForExistence(timeout: 8))

        let intelligence = app.descendants(matching: .any)[
            "settings.category.intelligence"
        ].firstMatch
        XCTAssertTrue(
            intelligence.waitForExistence(timeout: 3) && intelligence.isHittable
        )
        activate(intelligence)

        let kinds = ["inboxRouting", "checklistVisual", "taskPlan"]
        for kind in kinds {
            let edit = app.descendants(matching: .any)[
                "settings.llm.prompt.\(kind).edit"
            ].firstMatch
            scrollUntilHittable(edit, direction: .up, in: app)
            XCTAssertTrue(edit.waitForExistence(timeout: 5) && edit.isHittable)
        }
        let screenshotPrefix = platformScreenshotPrefix(in: app)
        try capture("\(screenshotPrefix)-settings-ai-prompt-list", app: app)

        let inboxEdit = app.descendants(matching: .any)[
            "settings.llm.prompt.inboxRouting.edit"
        ].firstMatch
        scrollUntilHittable(inboxEdit, direction: .down, in: app)
        activate(inboxEdit)
        let inboxEditor = app.descendants(matching: .any)[
            "settings.llm.prompt.inboxRouting.editor"
        ].firstMatch
        let inboxByteCount = app.descendants(matching: .any)[
            "settings.llm.prompt.inboxRouting.byteCount"
        ].firstMatch
        XCTAssertTrue(inboxEditor.waitForExistence(timeout: 5) && inboxEditor.isHittable)
        XCTAssertTrue(inboxByteCount.waitForExistence(timeout: 3))
        activate(inboxEditor)
        let inboxDirtySuffix = "Prefer the narrowest matching destination."
        inboxEditor.typeText("\n\(inboxDirtySuffix)")

        let inboxCancel = app.buttons[
            "settings.llm.prompt.inboxRouting.cancel"
        ].firstMatch
        XCTAssertTrue(inboxCancel.waitForExistence(timeout: 3) && inboxCancel.isHittable)
        activate(inboxCancel)
        let discardDialog = app.sheets["Discard Changes?"].firstMatch
        XCTAssertTrue(discardDialog.waitForExistence(timeout: 3))
        try capture("\(screenshotPrefix)-ai-prompt-discard-confirmation", app: app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5)).tap()
        XCTAssertTrue(discardDialog.waitForNonExistence(timeout: 3))
        XCTAssertTrue(inboxEditor.waitForExistence(timeout: 3))

        activate(inboxCancel)
        let discard = app.buttons["editor.discard.confirm"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 3) && discard.isHittable)
        activate(discard)
        XCTAssertTrue(inboxEditor.waitForNonExistence(timeout: 5))

        scrollUntilHittable(inboxEdit, direction: .down, in: app)
        activate(inboxEdit)
        XCTAssertTrue(inboxEditor.waitForExistence(timeout: 5) && inboxEditor.isHittable)
        XCTAssertFalse((inboxEditor.value as? String ?? "").contains(inboxDirtySuffix))
        activate(inboxEditor)
        inboxEditor.typeText("\n\(inboxDirtySuffix)")
        let inboxSave = app.buttons[
            "settings.llm.prompt.inboxRouting.save"
        ].firstMatch
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                inboxSave.exists && inboxSave.isEnabled && inboxSave.isHittable
            }
        )
        activate(inboxSave)
        XCTAssertTrue(inboxEditor.waitForNonExistence(timeout: 5))

        scrollUntilHittable(inboxEdit, direction: .down, in: app)
        activate(inboxEdit)
        XCTAssertTrue(inboxEditor.waitForExistence(timeout: 5))
        XCTAssertTrue((inboxEditor.value as? String ?? "").contains(inboxDirtySuffix))
        let restoreDefault = app.buttons[
            "settings.llm.prompt.inboxRouting.restoreDefault"
        ].firstMatch
        XCTAssertTrue(
            restoreDefault.waitForExistence(timeout: 3) &&
                restoreDefault.isEnabled &&
                restoreDefault.isHittable
        )
        activate(restoreDefault)
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                inboxSave.exists && inboxSave.isEnabled && inboxSave.isHittable
            }
        )
        activate(inboxSave)
        XCTAssertTrue(inboxEditor.waitForNonExistence(timeout: 5))

        scrollUntilHittable(inboxEdit, direction: .down, in: app)
        activate(inboxEdit)
        XCTAssertTrue(inboxEditor.waitForExistence(timeout: 5))
        XCTAssertFalse((inboxEditor.value as? String ?? "").contains(inboxDirtySuffix))
        XCTAssertFalse(restoreDefault.isEnabled)
        activate(inboxCancel)
        XCTAssertTrue(inboxEditor.waitForNonExistence(timeout: 5))

        for (kind, uniqueInstructions) in [
            ("checklistVisual", "Prefer literal symbols with calm colors."),
            ("taskPlan", "Prefer small tasks with concrete checklist steps."),
        ] {
            let edit = app.descendants(matching: .any)[
                "settings.llm.prompt.\(kind).edit"
            ].firstMatch
            scrollUntilHittable(edit, direction: .up, in: app)
            activate(edit)
            let editor = app.descendants(matching: .any)[
                "settings.llm.prompt.\(kind).editor"
            ].firstMatch
            let byteCount = app.descendants(matching: .any)[
                "settings.llm.prompt.\(kind).byteCount"
            ].firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 5) && editor.isHittable)
            XCTAssertTrue(byteCount.waitForExistence(timeout: 3))
            if kind == "checklistVisual" {
                try capture("\(screenshotPrefix)-ai-prompt-checklist-editor", app: app)
            }
            activate(editor)
            if kind == "taskPlan" {
                editor.typeKey("a", modifierFlags: .command)
                editor.typeText(
                    "# Task plan instructions\n\n\(uniqueInstructions)\n\n" +
                        "## Structure\n\n- Keep every step concrete."
                )
                let editedInstructions = editor.value as? String ?? ""
                XCTAssertTrue(
                    editedInstructions.hasPrefix("# Task plan instructions")
                )
                XCTAssertTrue(
                    editedInstructions.contains(
                        "## Structure\n\n- Keep every step concrete."
                    )
                )
            } else {
                editor.typeText("\n\(uniqueInstructions)")
            }
            if kind == "taskPlan" {
                let mode = app.descendants(matching: .any)[
                    "settings.llm.prompt.taskPlan.mode"
                ].firstMatch
                XCTAssertTrue(mode.waitForExistence(timeout: 3))
                let previewSegment = mode.buttons.element(boundBy: 1)
                XCTAssertTrue(previewSegment.exists && previewSegment.isHittable)
                activate(previewSegment)
                let markdownPreview = app.descendants(matching: .any)[
                    "settings.llm.prompt.taskPlan.preview"
                ].firstMatch
                XCTAssertTrue(markdownPreview.waitForExistence(timeout: 5))
                try capture(
                    "\(screenshotPrefix)-ai-prompt-task-plan-markdown-preview",
                    app: app
                )
            }
            let save = app.buttons[
                "settings.llm.prompt.\(kind).save"
            ].firstMatch
            XCTAssertTrue(
                waitUntil(timeout: 3) {
                    save.exists && save.isEnabled && save.isHittable
                }
            )
            activate(save)
            XCTAssertTrue(editor.waitForNonExistence(timeout: 5))

            scrollUntilHittable(edit, direction: .up, in: app)
            XCTAssertTrue(edit.isHittable)
            activate(edit)
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            XCTAssertTrue((editor.value as? String ?? "").contains(uniqueInstructions))
            let restore = app.buttons[
                "settings.llm.prompt.\(kind).restoreDefault"
            ].firstMatch
            XCTAssertTrue(
                restore.waitForExistence(timeout: 3) &&
                    restore.isEnabled &&
                    restore.isHittable
            )
            activate(restore)
            XCTAssertTrue(
                waitUntil(timeout: 3) {
                    save.exists && save.isEnabled && save.isHittable
                }
            )
            activate(save)
            XCTAssertTrue(editor.waitForNonExistence(timeout: 5))

            scrollUntilHittable(edit, direction: .up, in: app)
            XCTAssertTrue(edit.isHittable)
            activate(edit)
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            XCTAssertFalse((editor.value as? String ?? "").contains(uniqueInstructions))
            XCTAssertFalse(restore.isEnabled)
            let cancel = app.buttons[
                "settings.llm.prompt.\(kind).cancel"
            ].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 3) && cancel.isHittable)
            activate(cancel)
            XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        }
        #else
        throw XCTSkip("AI prompt editing and screenshots run only on an explicitly owned simulator.")
        #endif
    }

    @MainActor
    func testLiveDeepSeekTaskPlanGeneratePreviewAndApply() throws {
        #if os(iOS) && targetEnvironment(simulator)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let configuration = try liveLLMUITestConfiguration()
        let prompt =
            "帮我生成 category阅读，下放一个任务：人工智能：现代方法，生成checklist 1-28"
        let liveEnvironment = [
            "TIMETRACKER_UI_TEST_LIVE_LLM_ENDPOINT":
                configuration.endpoint,
            "TIMETRACKER_UI_TEST_LIVE_LLM_API_KEY":
                configuration.apiKey,
            "TIMETRACKER_UI_TEST_LIVE_LLM_MODEL":
                configuration.modelID,
        ]

        let settingsApp = launchApp(
            route: "settings",
            seedsDemoData: false,
            additionalLaunchArguments: ["--uitesting-live-llm"],
            additionalLaunchEnvironment: liveEnvironment
        )
        let settingsView = settingsApp.descendants(matching: .any)[
            "settings.view"
        ].firstMatch
        XCTAssertTrue(settingsView.waitForExistence(timeout: 15))
        let intelligence = settingsApp.descendants(matching: .any)[
            "settings.category.intelligence"
        ].firstMatch
        scrollUntilHittable(
            intelligence,
            direction: .up,
            in: settingsApp
        )
        XCTAssertTrue(
            intelligence.waitForExistence(timeout: 5) &&
                intelligence.isHittable
        )
        activate(intelligence)

        let configureAI = settingsApp.descendants(matching: .any)[
            "settings.llm.configure"
        ].firstMatch
        scrollUntilHittable(
            configureAI,
            direction: .up,
            in: settingsApp
        )
        XCTAssertTrue(
            configureAI.waitForExistence(timeout: 5) &&
                configureAI.isHittable
        )
        activate(configureAI)

        let reasoningEffort = settingsApp.descendants(matching: .any)[
            "settings.llm.reasoningEffort"
        ].firstMatch
        XCTAssertTrue(reasoningEffort.waitForExistence(timeout: 5))
        let high = settingsApp.buttons["High"].firstMatch
        let maximum = settingsApp.buttons["Maximum"].firstMatch
        XCTAssertTrue(high.waitForExistence(timeout: 3) && high.isHittable)
        XCTAssertTrue(
            maximum.waitForExistence(timeout: 3) &&
                maximum.isHittable
        )
        XCTAssertTrue(maximum.isSelected)
        activate(high)
        XCTAssertTrue(high.isSelected)
        activate(maximum)
        XCTAssertTrue(maximum.isSelected)
        try capture(
            "iphone-live-deepseek-reasoning-effort-maximum",
            app: settingsApp
        )
        settingsApp.terminate()

        let app = launchApp(
            route: "tasks",
            seedsDemoData: false,
            additionalLaunchArguments: ["--uitesting-live-llm"],
            additionalLaunchEnvironment: liveEnvironment
        )

        let tasksView = app.descendants(matching: .any)[
            "tasks.view"
        ].firstMatch
        XCTAssertTrue(tasksView.waitForExistence(timeout: 15))

        let addMenu = app.descendants(matching: .any)[
            "tasks.add"
        ].firstMatch
        XCTAssertTrue(
            addMenu.waitForExistence(timeout: 5) && addMenu.isHittable
        )
        activate(addMenu)

        let generatePlan = app.descendants(matching: .any)[
            "tasks.generatePlan"
        ].firstMatch
        XCTAssertTrue(
            generatePlan.waitForExistence(timeout: 5) &&
                generatePlan.isHittable
        )
        activate(generatePlan)

        let sheet = app.descendants(matching: .any)[
            "aiTaskPlan.sheet"
        ].firstMatch
        let request = app.descendants(matching: .any)[
            "aiTaskPlan.request"
        ].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        XCTAssertTrue(
            request.waitForExistence(timeout: 5) && request.isHittable
        )
        activate(request)
        replaceText(prompt, in: request)
        XCTAssertTrue(
            (request.value as? String ?? request.label).contains(
                "人工智能：现代方法"
            )
        )

        let generate = app.buttons[
            "aiTaskPlan.generate"
        ].firstMatch
        XCTAssertTrue(
            generate.waitForExistence(timeout: 5) && generate.isHittable
        )
        activate(generate)

        let generating = app.descendants(matching: .any)[
            "aiTaskPlan.generating"
        ].firstMatch
        XCTAssertTrue(generating.waitForExistence(timeout: 10))

        let tokenProgress = app.descendants(matching: .any)[
            "aiTaskPlan.generating.tokens"
        ].firstMatch
        let generationError = app.descendants(matching: .any)[
            "aiTaskPlan.error"
        ].firstMatch
        let changeSummary = app.descendants(matching: .any)[
            "aiTaskPlan.changeSummary"
        ].firstMatch
        let progressDeadline = Date().addingTimeInterval(300)
        while tokenProgress.exists == false,
              generationError.exists == false,
              changeSummary.exists == false,
              Date() < progressDeadline
        {
            RunLoop.current.run(
                until: Date().addingTimeInterval(0.1)
            )
        }
        if generationError.exists {
            try capture(
                "iphone-live-deepseek-generation-error",
                app: app
            )
            XCTFail(
                "The real provider failed before progress: \(generationError.label)"
            )
            return
        }
        XCTAssertTrue(
            tokenProgress.exists,
            "The real provider must report output token progress before preview."
        )
        try capture(
            "iphone-live-deepseek-generating-tokens",
            app: app
        )

        XCTAssertTrue(
            changeSummary.waitForExistence(timeout: 180),
            "The production DeepSeek request must reach Preview."
        )
        try capture("iphone-live-deepseek-preview", app: app)

        let finalChecklistOperation = app.descendants(matching: .any)[
            "aiTaskPlan.operation.29"
        ].firstMatch
        gentlyScrollUntilHittable(
            finalChecklistOperation,
            direction: .up,
            maximumScrolls: 60,
            in: app
        )
        XCTAssertTrue(
            finalChecklistOperation.waitForExistence(timeout: 5) &&
                finalChecklistOperation.isHittable
        )
        XCTAssertTrue(
            finalChecklistOperation.label.contains("28"),
            "The real Preview must faithfully include Checklist 28."
        )
        try capture(
            "iphone-live-deepseek-preview-checklist-28",
            app: app
        )

        let reasoning = app.descendants(matching: .any)[
            "aiTaskPlan.reasoning"
        ].firstMatch
        gentlyScrollUntilHittable(
            reasoning,
            direction: .up,
            maximumScrolls: 30,
            in: app
        )
        XCTAssertTrue(
            reasoning.waitForExistence(timeout: 5) && reasoning.isHittable
        )
        activate(reasoning)
        let reasoningContent = app.descendants(matching: .any)[
            "aiTaskPlan.reasoning.content"
        ].firstMatch
        XCTAssertTrue(reasoningContent.waitForExistence(timeout: 5))
        try capture("iphone-live-deepseek-reasoning", app: app)
        activate(reasoning)
        XCTAssertTrue(reasoningContent.waitForNonExistence(timeout: 5))

        let rawOutput = app.descendants(matching: .any)[
            "aiTaskPlan.rawOutput"
        ].firstMatch
        gentlyScrollUntilHittable(
            rawOutput,
            direction: .up,
            maximumScrolls: 30,
            in: app
        )
        XCTAssertTrue(
            rawOutput.waitForExistence(timeout: 5) &&
                rawOutput.isHittable
        )
        activate(rawOutput)
        let rawOutputContent = app.descendants(matching: .any)[
            "aiTaskPlan.rawOutput.content"
        ].firstMatch
        XCTAssertTrue(rawOutputContent.waitForExistence(timeout: 5))
        try capture("iphone-live-deepseek-raw-output", app: app)

        let apply = app.buttons[
            "aiTaskPlan.apply"
        ].firstMatch
        XCTAssertTrue(
            apply.waitForExistence(timeout: 5) && apply.isHittable
        )
        activate(apply)
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 15))
        XCTAssertTrue(taskDetailIsReady(in: app))

        let titleField = app.descendants(matching: .any)[
            "task.editor.title.field"
        ].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertEqual(
            titleField.value as? String,
            "人工智能：现代方法"
        )
        try capture("iphone-live-deepseek-applied-task", app: app)
        #else
        throw XCTSkip(
            "The paid live DeepSeek UI gate runs only on an owned iPhone simulator."
        )
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
            CGVector(dx: 0.5, dy: 0.40),
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
    func testFocusCardsMatchTheNativePlatformCardStyle() throws {
        let app = launchApp(route: "focus")
        XCTAssertTrue(
            app.descendants(matching: .any)["pomodoro.view"]
                .waitForExistence(timeout: 8)
        )
        let setup = app.descendants(matching: .any)["pomodoro.setup"].firstMatch
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        let ledger = app.descendants(matching: .any)["pomodoro.recent"].firstMatch
        scrollUntilHittable(ledger, direction: .up, in: app)

        let prefix = platformScreenshotPrefix(in: app)
        try capture("\(prefix)-focus-native-card-style", app: app)
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
    func testAnalyticsHomeShowsTrackedTaskHeatmaps() throws {
        let app = launchApp(
            route: "analytics",
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: [
                "--uitesting-today-heatmap",
                "--uitesting-reset-demo-preferences",
            ]
        )
        XCTAssertTrue(analyticsIsReady(in: app))

        let heatmapsHeader = app.descendants(matching: .any)[
            "home.heatmaps.header"
        ].firstMatch
        scrollUntilHittable(heatmapsHeader, direction: .up, in: app)
        XCTAssertTrue(
            heatmapsHeader.waitForExistence(timeout: 8),
            "The analytics home must show the tracked-task heatmap section."
        )
        let grid = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@",
                "Time Tracker App activity Heatmap"
            )
        ).firstMatch
        scrollUntilHittable(grid, direction: .up, in: app)
        XCTAssertTrue(grid.waitForExistence(timeout: 8))

        let prefix = platformScreenshotPrefix(in: app)
        #if !os(macOS)
        try capture("\(prefix)-analytics-task-heatmaps", app: app)
        #endif
    }

    @MainActor
    func testDesktopTodayShowsUnifiedNowOverviewRow() throws {
        #if targetEnvironment(simulator) || os(macOS)
        let app = launchApp(replacesDemoDataOnLaunch: true)
        XCTAssertTrue(homeIsReady(in: app))
        let nowHeading = app.descendants(matching: .any)[
            "home.activeTimers.title"
        ].firstMatch
        let overview = app.descendants(matching: .any)["home.overview"].firstMatch
        let overviewHeader = app.descendants(matching: .any)[
            "home.overview.header"
        ].firstMatch
        let overviewHeading = app.descendants(matching: .any)[
            "home.overview.header.title"
        ].firstMatch
        let nowCard = app.descendants(matching: .any)[
            "home.now.card"
        ].firstMatch
        let overviewCard = app.descendants(matching: .any)[
            "home.overview.card"
        ].firstMatch
        XCTAssertTrue(nowHeading.waitForExistence(timeout: 8))
        XCTAssertTrue(overview.waitForExistence(timeout: 8))
        XCTAssertTrue(overviewHeading.waitForExistence(timeout: 3))
        if app.windows.firstMatch.frame.width >= 800 {
            XCTAssertTrue(overviewHeader.waitForExistence(timeout: 3))
            let nowHeadingFrame = try validVisibleFrame(
                for: nowHeading,
                in: app
            )
            let overviewHeadingFrame = try validVisibleFrame(
                for: overviewHeading,
                in: app
            )
            let nowCardFrame = try validVisibleFrame(for: nowCard, in: app)
            let overviewCardFrame = try validVisibleFrame(
                for: overviewCard,
                in: app
            )
            XCTAssertLessThan(
                nowHeadingFrame.maxX,
                overviewHeadingFrame.minX,
                "Wide-screen current state sections must actually use separate columns."
            )
            XCTAssertEqual(
                nowHeadingFrame.minY,
                overviewHeadingFrame.minY,
                accuracy: 2,
                "Wide-screen Now and Overview title glyphs must share one visual top edge."
            )
            XCTAssertEqual(
                nowCardFrame.minY,
                overviewCardFrame.minY,
                accuracy: 2,
                "Wide-screen Now and Overview cards must start at the same height."
            )
            XCTAssertEqual(
                nowCardFrame.maxY,
                overviewCardFrame.maxY,
                accuracy: 2,
                "Wide-screen Now and Overview cards must end on the same row boundary."
            )
        }
        let prefix = platformScreenshotPrefix(in: app)
        try capture("\(prefix)-today-unified-now-overview", app: app)
        #endif
    }

    @MainActor
    func testWideTodayPacksQuickStartBesideVisualizations() throws {
        #if os(macOS)
        let app = launchApp(
            replacesDemoDataOnLaunch: true,
            additionalLaunchEnvironment: [
                "TIMETRACKER_UI_TEST_WINDOW_WIDTH": "1500",
                "TIMETRACKER_UI_TEST_WINDOW_HEIGHT": "1000",
            ]
        )
        try placeMainWindowOnPrimaryScreen(in: app)
        XCTAssertGreaterThanOrEqual(
            app.windows.firstMatch.frame.width,
            1450,
            "The deterministic fixture must exercise the widest Today layout."
        )
        #else
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchApp(replacesDemoDataOnLaunch: true)
        guard min(app.frame.width, app.frame.height) >= 700 else {
            throw XCTSkip("The regular-width iOS layout requires an iPad simulator.")
        }
        let hideSidebar = app.buttons["Hide Sidebar"].firstMatch
        if hideSidebar.waitForExistence(timeout: 2), hideSidebar.isHittable {
            activate(hideSidebar)
        }
        #endif
        XCTAssertTrue(homeIsReady(in: app))
        let home = app.descendants(matching: .any)["home.view"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 5) {
            home.exists && home.frame.width >= 1056
        }, "The fixture must expose at least 1056 pt to the Today detail.")

        let weeklyHeading = app.descendants(matching: .any)[
            "home.weeklyGross.header.title"
        ].firstMatch
        let quickStartHeading = app.descendants(matching: .any)[
            "home.quickStart"
        ].firstMatch
        let weeklyFrame = try validVisibleFrame(
            for: weeklyHeading,
            in: app
        )
        let quickStartFrame = try validVisibleFrame(
            for: quickStartHeading,
            in: app
        )
        XCTAssertLessThan(
            weeklyFrame.maxX,
            quickStartFrame.minX,
            "The widest Today layout must place Quick Start in a separate trailing lane."
        )
        XCTAssertTrue(
            weeklyFrame.minY < quickStartFrame.maxY &&
                quickStartFrame.minY < weeklyFrame.maxY,
            "Quick Start and the first visualization heading must overlap vertically instead of stacking."
        )
        let prefix = platformScreenshotPrefix(in: app)
        try capture("\(prefix)-home-adaptive-packed-columns", app: app)
    }

    @MainActor
    func testAnalyticsRangeSwitchKeepsPeriodControlsMounted() throws {
        let app = launchApp(
            route: "analytics",
            additionalLaunchArguments: [
                "--uitesting-slow-analytics-range-reload",
            ]
        )
        XCTAssertTrue(analyticsIsReady(in: app))

        let periodFilter = app.descendants(matching: .any)[
            "analytics.periodFilter"
        ].firstMatch
        XCTAssertTrue(
            periodFilter.waitForExistence(timeout: 5),
            "The Analytics period controls must be visible before switching."
        )
        let reviewSection = app.descendants(matching: .any)[
            "analytics.section.review"
        ].firstMatch
        XCTAssertTrue(reviewSection.waitForExistence(timeout: 5))
        let refreshing = app.descendants(matching: .any)[
            "analytics.refreshing"
        ].firstMatch

        for segment in ["Week", "Month"] {
            let periodFilterFrameBeforeSwitch = periodFilter.frame
            let reviewFrameBeforeSwitch = reviewSection.frame
            #if os(macOS)
            let button = app.radioButtons[segment].firstMatch
            #else
            let button = app.segmentedControls.buttons[segment].firstMatch
            #endif
            XCTAssertTrue(
                button.waitForExistence(timeout: 5) && button.isHittable,
                "The \(segment) range segment must be available."
            )
            activate(button)
            XCTAssertTrue(
                refreshing.waitForExistence(timeout: 2),
                "The \(segment) switch must expose its in-place refresh state."
            )
            XCTAssertTrue(
                periodFilter.exists && reviewSection.exists,
                "Period controls and Review must stay mounted while \(segment) loads."
            )
            XCTAssertLessThanOrEqual(
                abs(periodFilter.frame.minY - periodFilterFrameBeforeSwitch.minY),
                2,
                "The period controls must not jump while \(segment) loads."
            )
            XCTAssertLessThanOrEqual(
                abs(reviewSection.frame.minY - reviewFrameBeforeSwitch.minY),
                2,
                "The Review section must not collapse while \(segment) loads."
            )
            let prefix = platformScreenshotPrefix(in: app)
            try capture(
                "\(prefix)-analytics-\(segment.lowercased())-mid-refresh",
                app: app
            )
            XCTAssertTrue(
                refreshing.waitForNonExistence(timeout: 10),
                "The \(segment) data sections must return after loading."
            )
            XCTAssertTrue(reviewSection.waitForExistence(timeout: 5))
        }

        #if os(macOS)
        let dayButton = app.radioButtons["Day"].firstMatch
        #else
        let dayButton = app.segmentedControls.buttons["Day"].firstMatch
        #endif
        XCTAssertTrue(dayButton.waitForExistence(timeout: 5) && dayButton.isHittable)
        activate(dayButton)
        XCTAssertTrue(
            refreshing.waitForNonExistence(timeout: 2),
            "Returning to the exact cached Day request must not force a loading frame."
        )
        XCTAssertTrue(periodFilter.exists && reviewSection.waitForExistence(timeout: 5))

        let prefix = platformScreenshotPrefix(in: app)
        try capture("\(prefix)-analytics-range-switch-stable", app: app)
    }

    @MainActor
    func testAnalyticsReviewAndExploreExposeAnswers() throws {
        #if os(macOS)
        throw XCTSkip("The question-led Analytics path requires an iOS simulator.")
        #else
        let app = launchApp(route: "analytics")
        XCTAssertTrue(analyticsIsReady(in: app))

        let periodFilter = app.descendants(matching: .any)[
            "analytics.periodFilter"
        ].firstMatch
        XCTAssertTrue(periodFilter.waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["Day"].firstMatch.isSelected)

        let reviewHeader = app.descendants(matching: .any)[
            "analytics.section.review"
        ].firstMatch
        let reviewFirstRow = app.descendants(matching: .any)[
            "analytics.category.decisions"
        ].firstMatch
        scrollUntilHittable(reviewFirstRow, direction: .up, in: app)
        XCTAssertTrue(reviewHeader.waitForExistence(timeout: 5))
        XCTAssertTrue(reviewFirstRow.waitForExistence(timeout: 5))
        XCTAssertTrue(
            reviewHeader.label.localizedCaseInsensitiveContains("Review")
        )
        XCTAssertTrue(
            reviewHeader.label.contains(
                "Check changes and data issues before deciding what to do next."
            )
        )

        let expectations: [
            (id: String, question: String, answer: String, destination: String)
        ] = [
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
            ),
        ]

        for expectation in expectations {
            verifyAnalyticsCategory(expectation, in: app)
        }
        try capture("analytics-review", app: app)

        let exploreHeader = app.descendants(matching: .any)[
            "analytics.section.explore"
        ].firstMatch
        let exploreFirstRow = app.descendants(matching: .any)[
            "analytics.category.time"
        ].firstMatch
        scrollUntilHittable(exploreFirstRow, direction: .up, in: app)
        XCTAssertTrue(exploreHeader.waitForExistence(timeout: 5))
        XCTAssertTrue(exploreFirstRow.waitForExistence(timeout: 5))
        XCTAssertTrue(
            exploreHeader.label.localizedCaseInsensitiveContains("Explore")
        )
        XCTAssertTrue(
            exploreHeader.label.contains(
                "See the charts, breakdowns, and records behind each total."
            )
        )

        let exploreExpectations: [
            (id: String, question: String, answer: String, destination: String)
        ] = [
            (
                "time",
                "When was my time most concentrated?",
                "Busiest at",
                "Time Patterns"
            ),
            (
                "tasks",
                "Where did my time go across tasks and categories?",
                "category distribution",
                "Tasks & Categories"
            ),
            (
                "pomodoro",
                "How many focus rounds did I finish?",
                "completed",
                "Focus Rounds"
            ),
            (
                "overview",
                "How much time did I spend?",
                "across all task timers",
                "Totals & Definitions"
            ),
        ]

        for expectation in exploreExpectations {
            verifyAnalyticsCategory(expectation, in: app)
        }

        let overview = app.descendants(matching: .any)["analytics.category.overview"].firstMatch
        scrollUntilFullyVisibleAboveSystemChrome(overview, in: app)
        XCTAssertTrue(isFullyVisibleAboveSystemChrome(overview, in: app))
        try capture("analytics-explore", app: app)
        #endif
    }

    @MainActor
    func testAnalyticsTasksAndCategoriesLeadWithCategoryDistribution() throws {
        let app = launchApp(route: "analytics")
        XCTAssertTrue(analyticsIsReady(in: app))

        let tasksAndCategories = app.descendants(matching: .any)[
            "analytics.category.tasks"
        ].firstMatch
        scrollUntilHittable(tasksAndCategories, direction: .up, in: app)
        XCTAssertTrue(
            waitForElement(
                tasksAndCategories,
                timeout: 5,
                diagnosticName: "analytics-tasks-categories",
                in: app
            ) && tasksAndCategories.isHittable
        )
        XCTAssertTrue(tasksAndCategories.label.contains("tasks and categories"))
        XCTAssertTrue(
            tasksAndCategories.label.localizedCaseInsensitiveContains(
                "category distribution"
            )
        )
        XCTAssertTrue(tasksAndCategories.label.contains("View details: Tasks & Categories"))
        activate(tasksAndCategories)

        let detail = app.descendants(matching: .any)[
            "analytics.categoryDetail.tasks"
        ].firstMatch
        let categorySection = app.descendants(matching: .any)[
            "analytics.categoryUsage.header"
        ].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        XCTAssertTrue(categorySection.waitForExistence(timeout: 8))
        XCTAssertEqual(categorySection.label, "Category Distribution")
        #if os(iOS)
        XCTAssertTrue(isFrameFullyVisibleAboveSystemChrome(categorySection, in: app))
        #endif
        try capture("analytics-tasks-categories-category-first", app: app)
    }

    @MainActor
    func testAnalyticsFocusRoundsAndForecastsRespectSelectedPeriod() throws {
        #if os(macOS)
        throw XCTSkip("Analytics period evidence requires an iOS simulator.")
        #else
        let app = launchApp(route: "analytics")
        if app.descendants(matching: .any)["analytics.view"]
            .waitForExistence(timeout: 5) == false
        {
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
    func testAnalyticsDefinitionsExplainGrossWallAndOverlap() throws {
        let app = launchApp(route: "analytics")

        XCTAssertTrue(analyticsIsReady(in: app))
        let overview = app.descendants(matching: .any)[
            "analytics.category.overview"
        ].firstMatch
        scrollUntilHittable(overview, direction: .up, in: app)
        XCTAssertTrue(overview.waitForExistence(timeout: 5) && overview.isHittable)
        activate(overview)

        let detail = app.descendants(matching: .any)[
            "analytics.categoryDetail.overview"
        ].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 8))

        let definitions: [(element: XCUIElement, expectedFragments: [String])] = [
            (
                app.descendants(matching: .any)["analytics.definition.gross"].firstMatch,
                ["every task timer"]
            ),
            (
                app.descendants(matching: .any)["analytics.definition.wall"].firstMatch,
                ["Overlapping intervals count once"]
            ),
            (
                app.descendants(matching: .any)["analytics.definition.overlap"].firstMatch,
                ["Gross Time − Wall Time"]
            ),
            (
                app.descendants(matching: .any)["analytics.definition.example"].firstMatch,
                ["Gross Time is 1h", "Wall Time is 30m", "Overlap Excess is 30m"]
            ),
        ]
        for definition in definitions {
            scrollUntilHittable(definition.element, direction: .up, in: app)
            XCTAssertTrue(
                waitForElement(
                    definition.element,
                    timeout: 5,
                    diagnosticName: "analytics-definition",
                    in: app
                )
            )
            #if os(iOS)
            for fragment in definition.expectedFragments {
                let text = app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS %@", fragment)
                ).firstMatch
                XCTAssertTrue(
                    text.waitForExistence(timeout: 3),
                    "Analytics definition must visibly contain: \(fragment)"
                )
            }
            #endif
        }

        try capture("analytics-detailed-definitions", app: app)
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
        XCTAssertTrue(
            app.staticTexts["Wall Time"].firstMatch.waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts["Gross Time"].firstMatch.waitForExistence(timeout: 3)
        )
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
    func testStoppingTodayTimerImmediatelyClosesMatchingTimelineRow() throws {
        let app = launchApp(replacesDemoDataOnLaunch: true)

        openSection(
            "Today",
            tabIdentifier: "phone.tab.today",
            sidebarIdentifier: "sidebar.Today",
            in: app
        )
        XCTAssertTrue(homeIsReady(in: app))
        let stop = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
            "home.activeTimer.",
            "Stop "
        )).firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5) && stop.isHittable)
        XCTAssertTrue(
            ["Stop Design macOS UI", "Stop Read Apple HIG"].contains(stop.label),
            "The destructive assertion must only run against the isolated demo fixture."
        )

        let segmentID = String(
            stop.identifier.dropFirst("home.activeTimer.".count)
        )
        XCTAssertFalse(segmentID.isEmpty)
        activate(stop)
        XCTAssertTrue(
            stop.waitForNonExistence(timeout: 5),
            "The selected timer must leave the Now section immediately."
        )

        let timeline = app.descendants(matching: .any)[
            "home.timeline"
        ].firstMatch
        scrollTodayUntilHittable(timeline, in: app)
        XCTAssertTrue(timeline.waitForExistence(timeout: 5) && timeline.isHittable)

        let record = app.buttons.matching(NSPredicate(
            format: "identifier ENDSWITH %@",
            segmentID
        )).firstMatch
        #if os(macOS)
        // macOS lazily virtualizes the legend rows below the 320-point chart;
        // XCTest can still read the matching row's value while it is offscreen.
        XCTAssertTrue(
            record.waitForExistence(timeout: 5),
            "The stopped segment must remain in Today's timeline projection."
        )
        #else
        scrollUntilFullyVisibleAboveSystemChrome(record, in: app)
        XCTAssertTrue(
            record.waitForExistence(timeout: 5) &&
                isFrameFullyVisibleAboveSystemChrome(record, in: app),
            """
            The stopped segment must remain visible in Today's timeline. \
            Record frame: \(record.frame); window: \(app.windows.firstMatch.frame)
            """
        )
        #endif
        let fixedTimeRange = String(describing: record.value ?? "")
        XCTAssertFalse(
            ["Now", "现在", "現在"].contains { fixedTimeRange.contains($0) },
            """
            The matching timeline row still exposes an open-ended range after \
            Stop: \(fixedTimeRange)
            """
        )

        try capture(
            "\(platformScreenshotPrefix(in: app))-today-stopped-timeline-row",
            app: app
        )
    }

    @MainActor
    func testPhoneShortTimelineBarsUseProjectedLanes() throws {
        #if os(macOS)
        throw XCTSkip("Projected short-task lanes are verified on an iPhone simulator.")
        #else
        let app = launchApp(
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: ["--uitesting-short-timeline"]
        )

        XCTAssertTrue(homeIsReady(in: app))
        if app.descendants(matching: .any)["ipad.splitNavigation"]
            .waitForExistence(timeout: 1)
        {
            throw XCTSkip("The Task 23 fixture is phone-only.")
        }

        let timeline = app.descendants(matching: .any)["home.timeline"].firstMatch
        scrollTodayUntilHittable(timeline, in: app)
        XCTAssertTrue(timeline.waitForExistence(timeout: 5) && timeline.isHittable)

        scroll(direction: .up, toward: timeline, in: app)
        let chartMarks = app.otherElements.matching(
            NSPredicate(
                format: "label IN %@",
                [
                    "Timeline Short Blue",
                    "Timeline Short Orange",
                    "Timeline Terminal Green",
                ]
            )
        )
        let blue = chartMarks.matching(
            NSPredicate(format: "label == %@", "Timeline Short Blue")
        ).firstMatch
        let orange = chartMarks.matching(
            NSPredicate(format: "label == %@", "Timeline Short Orange")
        ).firstMatch
        let terminal = chartMarks.matching(
            NSPredicate(format: "label == %@", "Timeline Terminal Green")
        ).firstMatch
        XCTAssertTrue(blue.waitForExistence(timeout: 5))
        XCTAssertTrue(orange.waitForExistence(timeout: 5))
        XCTAssertTrue(terminal.waitForExistence(timeout: 5))

        let projectedOverlap = min(blue.frame.maxY, orange.frame.maxY) -
            max(blue.frame.minY, orange.frame.minY)
        XCTAssertGreaterThan(
            projectedOverlap,
            0,
            "The fixture's short marks must overlap on the projected time axis."
        )
        XCTAssertGreaterThanOrEqual(
            abs(blue.frame.midX - orange.frame.midX),
            6,
            "Projected marks that collide must render on separate visual lanes."
        )
        XCTAssertGreaterThan(
            terminal.frame.minY,
            max(blue.frame.maxY, orange.frame.maxY),
            "The terminal short mark must remain anchored later on the downward axis."
        )
        try capture("iphone-home-short-timeline-lanes", app: app)
        #endif
    }

    @MainActor
    func testOverlappingShortTimelineProtectsGapAnnotationAcrossPlatforms() throws {
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif

        let app = launchApp(
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: ["--uitesting-overlap-timeline"]
        )
        #if os(macOS)
        try placeMainWindowOnPrimaryScreen(in: app)
        #endif
        XCTAssertTrue(homeIsReady(in: app))

        let timeline = app.descendants(matching: .any)["home.timeline"].firstMatch
        scrollTodayUntilHittable(timeline, in: app)
        XCTAssertTrue(timeline.waitForExistence(timeout: 5) && timeline.isHittable)

        #if os(macOS)
        try assertOverlappingTimelineMarks(
            in: app,
            usesHorizontalTimeAxis: true
        )
        scroll(direction: .up, toward: timeline, in: app)
        waitForScreenshotTransition()
        try capture("mac-home-overlap-timeline", app: app)
        #else
        let usesIPadShell = platformScreenshotPrefix(in: app) == "ipad"
        try assertOverlappingTimelineMarks(
            in: app,
            usesHorizontalTimeAxis: usesIPadShell
        )

        if usesIPadShell {
            waitForScreenshotTransition()
            try capture("ipad-home-overlap-timeline-portrait", app: app)

            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(waitUntil(timeout: 5) {
                let frame = app.windows.firstMatch.frame
                return frame.width > frame.height
            })
            let landscapeTimeline = app.descendants(matching: .any)[
                "home.timeline"
            ].firstMatch
            scrollTodayUntilHittable(landscapeTimeline, in: app)
            XCTAssertTrue(
                landscapeTimeline.waitForExistence(timeout: 5) &&
                    landscapeTimeline.isHittable
            )
            try assertOverlappingTimelineMarks(
                in: app,
                usesHorizontalTimeAxis: true
            )
            scroll(direction: .up, toward: landscapeTimeline, in: app)
            waitForScreenshotTransition()
            try capture("ipad-home-overlap-timeline-landscape", app: app)
        } else {
            scroll(direction: .up, toward: timeline, in: app)
            waitForScreenshotTransition()
            try capture("iphone-home-overlap-timeline", app: app)
        }
        #endif

        assertOverlappingTimelineRecordIcons(in: app)
        waitForScreenshotTransition()
        let recordScreenshotPrefix = platformScreenshotPrefix(in: app)
        let recordScreenshotName = switch recordScreenshotPrefix {
        case "ipad":
            "ipad-home-overlap-timeline-record-icons-landscape"
        case "iphone":
            "iphone-home-overlap-timeline-record-icons"
        default:
            "mac-home-overlap-timeline-record-icons"
        }
        try capture(recordScreenshotName, app: app)
    }

    @MainActor
    func testMultipleTimelineGapLabelsAvoidCollisionAcrossPlatforms() throws {
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif

        let app = launchApp(
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: ["--uitesting-gap-label-collision"]
        )
        #if os(macOS)
        try placeMainWindowOnPrimaryScreen(in: app)
        #endif
        XCTAssertTrue(homeIsReady(in: app))

        let timeline = app.descendants(matching: .any)["home.timeline"].firstMatch
        scrollTodayUntilHittable(timeline, in: app)
        XCTAssertTrue(timeline.waitForExistence(timeout: 5) && timeline.isHittable)

        #if os(macOS)
        scroll(direction: .up, toward: timeline, in: app)
        waitForScreenshotTransition()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3))
        XCTAssertTrue(
            app.windows.firstMatch.frame.contains(timeline.frame),
            "The macOS Timeline must be fully visible inside the app window"
        )
        try assertTimelineGapCapsulesHugText(in: app)
        try capture(
            "mac-home-task27-intrinsic-gap-capsules",
            element: app.windows.firstMatch
        )
        #else
        let usesIPadShell = platformScreenshotPrefix(in: app) == "ipad"
        if usesIPadShell {
            scrollUntilFullyVisibleAboveSystemChrome(timeline, in: app)
            XCTAssertTrue(isFullyVisibleAboveSystemChrome(timeline, in: app))
            try assertTimelineGapCapsulesHugText(in: app)
            waitForScreenshotTransition()
            try capture(
                "ipad-home-task27-intrinsic-gap-capsules-portrait",
                app: app
            )

            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(waitUntil(timeout: 5) {
                let frame = app.windows.firstMatch.frame
                return frame.width > frame.height
            })
            let landscapeTimeline = app.descendants(matching: .any)[
                "home.timeline"
            ].firstMatch
            scrollTodayUntilHittable(landscapeTimeline, in: app)
            XCTAssertTrue(
                landscapeTimeline.waitForExistence(timeout: 5) &&
                    landscapeTimeline.isHittable
            )
            scrollUntilFullyVisibleAboveSystemChrome(landscapeTimeline, in: app)
            XCTAssertTrue(
                isFullyVisibleAboveSystemChrome(landscapeTimeline, in: app)
            )
            try assertTimelineGapCapsulesHugText(in: app)
            waitForScreenshotTransition()
            try capture(
                "ipad-home-task27-intrinsic-gap-capsules-landscape",
                app: app
            )
        } else {
            scrollUntilFullyVisibleAboveSystemChrome(timeline, in: app)
            XCTAssertTrue(isFullyVisibleAboveSystemChrome(timeline, in: app))
            try assertTimelineGapCapsulesHugText(in: app)
            waitForScreenshotTransition()
            try capture(
                "iphone-home-task27-intrinsic-gap-capsules",
                app: app
            )
        }
        #endif
    }

    @MainActor
    func testPhoneTimelineAxisLabelsStayLeadingAlignedAroundSkippedGaps() throws {
        #if os(macOS)
        throw XCTSkip("The compact vertical Timeline is verified on iPhone.")
        #else
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchApp(
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: ["--uitesting-gap-label-collision"]
        )
        XCTAssertTrue(homeIsReady(in: app))

        if app.descendants(matching: .any)["ipad.splitNavigation"]
            .waitForExistence(timeout: 1)
        {
            throw XCTSkip("The compact vertical Timeline is verified on iPhone.")
        }

        let chart = app.descendants(matching: .any)[
            "home.timeline.chart"
        ].firstMatch
        scrollTodayUntilHittable(chart, in: app)
        XCTAssertTrue(chart.waitForExistence(timeout: 5) && chart.isHittable)
        scrollUntilFullyVisibleAboveSystemChrome(chart, in: app)
        XCTAssertTrue(isFullyVisibleAboveSystemChrome(chart, in: app))

        try assertPhoneTimelineAxisLabelsStayLeadingAligned(in: app)
        waitForScreenshotTransition()
        try capture(
            "iphone-home-timeline-leading-axis-around-skipped-gaps",
            app: app
        )
        #endif
    }

    @MainActor
    func testAppleHealthTimelineControlsStayVisibleAndContextual() throws {
        #if os(macOS)
        throw XCTSkip("Apple Health timeline controls require an iOS simulator.")
        #else
        let app = launchApp(
            additionalLaunchArguments: [
                "-AppleHealthTimelineEnabled",
                "NO",
            ]
        )
        XCTAssertTrue(homeIsReady(in: app))

        let timelineAccess = app.descendants(matching: .any)[
            "home.timeline.appleHealth"
        ].firstMatch
        scrollTodayUntilHittable(timelineAccess, in: app)
        XCTAssertTrue(
            timelineAccess.waitForExistence(timeout: 5) &&
                timelineAccess.isHittable
        )
        XCTAssertGreaterThanOrEqual(timelineAccess.frame.height, 44)
        XCTAssertTrue(
            timelineAccess.label.localizedCaseInsensitiveContains(
                "Show Apple Health in Timeline"
            )
        )
        try capture("iphone-home-apple-health-timeline-access", app: app)

        openSettings(in: app)
        let general = app.buttons["settings.category.general"].firstMatch
        XCTAssertTrue(general.waitForExistence(timeout: 5) && general.isHittable)
        activate(general)

        let timelineToggle = app.switches[
            "settings.appleHealth.timelineToggle"
        ].firstMatch
        scrollUntilHittable(timelineToggle, direction: .up, in: app)
        XCTAssertTrue(
            timelineToggle.waitForExistence(timeout: 5) &&
                timelineToggle.isHittable
        )
        XCTAssertTrue(timelineToggle.isEnabled)
        XCTAssertEqual(timelineToggle.value as? String, "0")
        try capture("iphone-settings-apple-health-timeline", app: app)
        #endif
    }

    @MainActor
    func testAppleHealthWorkoutAndSleepAppearInTodayTimeline() throws {
        #if os(macOS)
        throw XCTSkip("Apple Health timeline content requires iOS.")
        #else
        let app = launchApp(
            seedsDemoData: false,
            additionalLaunchArguments: [
                "--uitesting-apple-health",
                "-AppleHealthTimelineEnabled",
                "NO",
            ]
        )
        XCTAssertTrue(homeIsReady(in: app))

        let timelineAccess = app.buttons[
            "Show Apple Health in Timeline"
        ].firstMatch
        for _ in 0 ..< 8 {
            if timelineAccess.exists, timelineAccess.isHittable {
                break
            }
            dragContentUp(by: app.frame.height * 0.25, in: app)
        }
        XCTAssertTrue(
            timelineAccess.waitForExistence(timeout: 5) &&
                timelineAccess.isHittable
        )
        activate(timelineAccess)

        let healthEntries = { (title: String) in
            app.descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "label CONTAINS[c] %@ AND label CONTAINS[c] %@",
                        title,
                        "Apple Health"
                    )
                )
        }
        let sleepEntries = healthEntries("Sleep")
        let sleep = sleepEntries.firstMatch
        let running = healthEntries("Running").firstMatch
        for _ in 0 ..< 8 {
            if sleep.exists, sleep.isHittable {
                break
            }
            dragContentUp(by: app.frame.height * 0.25, in: app)
        }
        scrollUntilFullyVisibleAboveSystemChrome(sleep, in: app)
        XCTAssertTrue(
            sleep.waitForExistence(timeout: 8) &&
                isFrameFullyVisibleAboveSystemChrome(sleep, in: app)
        )
        XCTAssertEqual(
            sleepEntries.count,
            1,
            "Core, awake, deep, and REM samples must form one sleep episode."
        )
        XCTAssertTrue(
            running.waitForExistence(timeout: 5) &&
                isFrameFullyVisibleAboveSystemChrome(running, in: app)
        )

        let prefix = app.frame.width >= 700 ? "ipad" : "iphone"
        try capture(
            "\(prefix)-home-apple-health-workout-sleep",
            app: app
        )
        #endif
    }

    @MainActor
    func testFirstAppleHealthTimelineRowUsesSharedRecordLayout() throws {
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif

        let app = launchApp(
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: [
                "--uitesting-first-health-timeline",
            ]
        )
        #if os(macOS)
        try placeMainWindowOnPrimaryScreen(in: app)
        #endif
        XCTAssertTrue(homeIsReady(in: app))
        let screenshotPrefix = platformScreenshotPrefix(in: app)
        #if os(iOS)
        let usesStableLeafGeometry = screenshotPrefix != "ipad"
        #endif

        let healthKey =
            "appleHealthWorkout.D0700000-0000-4000-8000-000000000001"
        let chart = app.descendants(matching: .any)[
            "home.timeline.chart"
        ].firstMatch
        let healthRow = app.descendants(matching: .any)[
            "home.timeline.entry.\(healthKey)"
        ].firstMatch
        let healthRange = app.descendants(matching: .any)[
            "home.timeline.entry.\(healthKey).timeRange"
        ].firstMatch
        let healthTitle = app.staticTexts[
            "home.timeline.entry.\(healthKey).title"
        ].firstMatch
        #if os(macOS)
        let trackedRows = app.groups.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "home.timeline.entry.trackedSegment."
            )
        )
        #else
        let trackedRows = app.otherElements.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "home.timeline.entry.trackedSegment."
            )
        )
        #endif
        let trackedRanges = app.staticTexts.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
                "home.timeline.entry.trackedSegment.",
                ".timeRange"
            )
        )
        let trackedTitles = app.staticTexts.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
                "home.timeline.entry.trackedSegment.",
                ".title"
            )
        )
        let trackedMenus = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "timeline.more.manual."
            )
        )
        let trackedRow = trackedRows.firstMatch

        for _ in 0 ..< 12 where !healthRow.exists {
            scroll(direction: .up, toward: healthRow, in: app)
        }
        XCTAssertTrue(
            healthRow.waitForExistence(timeout: 8),
            "The deterministic Health-first fixture must load into the Timeline."
        )
        scrollUntilFrameFullyVisibleAboveSystemChrome(healthRow, in: app)
        #if os(macOS)
        scroll(direction: .up, toward: healthRow, in: app)
        #else
        scrollUntilFrameFullyVisibleAboveSystemChrome(trackedRow, in: app)
        #endif
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertTrue(healthRow.waitForExistence(timeout: 5))
        #if os(iOS)
        XCTAssertTrue(healthRange.waitForExistence(timeout: 5))
        #endif
        XCTAssertEqual(trackedRows.count, 1)
        #if os(iOS)
        XCTAssertEqual(trackedRanges.count, 1)
        XCTAssertEqual(trackedTitles.count, 1)
        #endif
        XCTAssertEqual(trackedMenus.count, 1)

        #if os(iOS)
        let trackedRange = trackedRanges.firstMatch
        let trackedTitle = trackedTitles.firstMatch
        #endif
        scrollUntilFrameFullyVisibleAboveSystemChrome(trackedRow, in: app)

        let chartFrame = try validVisibleFrame(
            for: chart,
            in: app,
            requiresFullVisibility: false
        )
        let healthRowFrame = try validVisibleFrame(
            for: healthRow,
            in: app
        )
        let trackedRowFrame = try validVisibleFrame(
            for: trackedRow,
            in: app
        )
        #if os(iOS)
        let leafFrames: (
            healthRange: CGRect,
            trackedRange: CGRect,
            healthTitle: CGRect,
            trackedTitle: CGRect
        )? = if usesStableLeafGeometry {
            try (
                validVisibleFrame(for: healthRange, in: app),
                validVisibleFrame(for: trackedRange, in: app),
                validVisibleFrame(for: healthTitle, in: app),
                validVisibleFrame(for: trackedTitle, in: app)
            )
        } else {
            nil
        }
        #endif

        XCTAssertLessThan(healthRowFrame.minY, trackedRowFrame.minY)
        #if os(iOS)
        if let leafFrames {
            XCTAssertFalse(
                leafFrames.healthRange.intersects(chartFrame),
                "The first Health time range must remain below the chart."
            )
            XCTAssertLessThanOrEqual(
                abs(leafFrames.healthRange.minX - leafFrames.trackedRange.minX),
                2,
                "Health and tracked records must reuse the same time column."
            )
            XCTAssertLessThanOrEqual(
                abs(leafFrames.healthTitle.minX - leafFrames.trackedTitle.minX),
                2,
                "Health and tracked records must share the title leading edge."
            )
        } else {
            XCTAssertFalse(
                healthRowFrame.intersects(chartFrame),
                "The first Health record must remain below the chart."
            )
        }
        #else
        XCTAssertFalse(
            healthRowFrame.intersects(chartFrame),
            "The first Health record must remain below the chart."
        )
        XCTAssertTrue(
            healthRow.descendants(matching: .any).matching(
                NSPredicate(
                    format: "label CONTAINS[c] %@",
                    "Apple Health"
                )
            ).firstMatch.waitForExistence(timeout: 3),
            "The macOS shared renderer must preserve the Health source."
        )
        #endif
        XCTAssertLessThanOrEqual(
            healthRowFrame.maxY,
            trackedRowFrame.minY + 1,
            "Adjacent Timeline records must not overlap."
        )
        XCTAssertEqual(
            healthRow.buttons.matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    "timeline.more."
                )
            ).count,
            0,
            "Apple Health records must stay read-only."
        )

        #if os(iOS)
        if screenshotPrefix != "ipad" {
            waitForScreenshotTransition()
            try capture(
                "\(screenshotPrefix)-home-first-health-shared-row",
                app: app
            )
        }
        #else
        waitForScreenshotTransition()
        try capture(
            "\(screenshotPrefix)-home-first-health-shared-row",
            app: app
        )
        #endif
    }

    @MainActor
    func testAppleHealthTasksStayOutOfQuickStartAndUseAnalyticsOnlyDetail()
        throws
    {
        #if os(macOS)
        throw XCTSkip("Apple Health sync-only UI requires an iOS simulator.")
        #else
        let app = launchApp(
            seedsDemoData: true,
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: [
                "--uitesting-apple-health",
                "-AppleHealthTimelineEnabled",
                "NO",
            ]
        )
        XCTAssertTrue(homeIsReady(in: app))
        let screenshotPrefix = platformScreenshotPrefix(in: app)
        let syncOnlyTaskIDs = [
            "A1200000-0000-4000-8000-000000000002",
            "A1200000-0000-4000-8000-000000000012",
        ]

        let tasksTab = app.descendants(matching: .any)[
            "phone.tab.tasks"
        ].firstMatch
        for _ in 0 ..< 5 where !tasksTab.isHittable {
            app.swipeDown()
        }

        openSection(
            "Tasks",
            tabIdentifier: "phone.tab.tasks",
            sidebarIdentifier: "sidebar.Tasks",
            in: app
        )
        let running = app.buttons[
            "tasks.row.A1200000-0000-4000-8000-000000000002"
        ].firstMatch
        let sleep = app.buttons[
            "tasks.row.A1200000-0000-4000-8000-000000000012"
        ].firstMatch
        scrollUntilHittable(
            running,
            direction: .up,
            maximumScrolls: 8,
            in: app
        )
        XCTAssertTrue(
            running.waitForExistence(timeout: 8) && running.isHittable
        )
        try capture(
            "\(screenshotPrefix)-apple-health-auto-visible-tasks",
            app: app
        )
        activate(running)

        XCTAssertTrue(taskDetailIsReady(in: app))
        assertAppleHealthDetailOmitsOrdinaryTaskContent(in: app)
        try capture(
            "\(screenshotPrefix)-apple-health-analytics-only-detail",
            app: app
        )

        let tasksBack = taskDetailBackButton(to: "Tasks", in: app)
        XCTAssertTrue(
            tasksBack.waitForExistence(timeout: 5) && tasksBack.isHittable
        )
        activate(tasksBack)
        XCTAssertTrue(
            app.descendants(matching: .any)["tasks.view"]
                .waitForExistence(timeout: 5)
        )
        scrollUntilHittable(
            sleep,
            direction: .up,
            maximumScrolls: 16,
            in: app
        )
        XCTAssertTrue(
            sleep.waitForExistence(timeout: 8) && sleep.isHittable,
            "Sleep must appear in Tasks while Apple Health Timeline remains disabled."
        )

        let todayTab = app.descendants(matching: .any)[
            "phone.tab.today"
        ].firstMatch
        for _ in 0 ..< 5 where !todayTab.isHittable {
            app.swipeDown()
        }

        openSection(
            "Today",
            tabIdentifier: "phone.tab.today",
            sidebarIdentifier: "sidebar.Today",
            in: app
        )
        XCTAssertTrue(homeIsReady(in: app))
        let editQuickStart = app.buttons["home.quickStart.edit"].firstMatch
        scrollTodayUntilHittable(editQuickStart, in: app)
        XCTAssertTrue(
            editQuickStart.waitForExistence(timeout: 5) &&
                editQuickStart.isHittable
        )
        XCTAssertGreaterThan(
            app.buttons.matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    "home.quickStart.task."
                )
            ).count,
            0,
            "Ordinary demo tasks keep the Quick Start filter observable."
        )
        for taskID in syncOnlyTaskIDs {
            XCTAssertFalse(
                app.buttons["home.quickStart.task.\(taskID)"].exists,
                "Apple Health workout and sleep tasks must not become Quick Start rows."
            )
            XCTAssertFalse(
                app.buttons["home.quickStart.timer.\(taskID)"].exists,
                "Apple Health tasks must not expose Quick Start timer actions."
            )
        }
        activate(editQuickStart)

        XCTAssertTrue(
            app.descendants(matching: .any)["quickStart.editor"]
                .waitForExistence(timeout: 5)
        )
        let editorTaskRows = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@",
                "quickStart.editor.pinned.",
                "quickStart.editor.available."
            )
        )
        XCTAssertGreaterThan(
            editorTaskRows.count,
            0,
            "Ordinary tasks must remain available while sync-only tasks are filtered."
        )
        for taskID in syncOnlyTaskIDs {
            XCTAssertFalse(
                app.buttons["quickStart.editor.pinned.\(taskID)"].exists
            )
            XCTAssertFalse(
                app.buttons["quickStart.editor.available.\(taskID)"].exists,
                "Sync-only Apple Health tasks must not be pinnable."
            )
        }
        try capture(
            "\(screenshotPrefix)-apple-health-sync-only-quick-start",
            app: app
        )
        #endif
    }

    @MainActor
    func testAppleHealthTaskDetailShowsOnlyAnalyticsSections() throws {
        #if os(macOS)
        throw XCTSkip("Apple Health sync-only UI requires an iOS simulator.")
        #else
        let app = launchApp(
            route: "task-detail",
            contentSizeCategory: "UICTContentSizeCategoryL",
            seedsDemoData: true,
            replacesDemoDataOnLaunch: true,
            taskTitle: "Running",
            additionalLaunchArguments: [
                "--uitesting-apple-health-history",
                "-AppleHealthTimelineEnabled",
                "NO",
            ]
        )
        ensureTaskDetailIsReady(named: "Running", in: app)

        assertAppleHealthDetailOmitsOrdinaryTaskContent(in: app)
        let chart = assertAppleHealthHistoryContent(in: app)
        assertAppleHealthDetailSectionHeaders(in: app)
        let periodFilter = app.descendants(matching: .any)[
            "task.detail.appleHealth.periodFilter"
        ].firstMatch
        scrollUntilHittable(
            periodFilter,
            direction: .down,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(
            periodFilter.waitForExistence(timeout: 5) &&
                periodFilter.isHittable,
            "Period controls must remain inside the Task Analysis section."
        )
        assertNoAppleHealthAuthorizationSheet(in: app)

        scrollUntilFullyVisibleAboveSystemChrome(chart, in: app)
        try capture(
            "\(platformScreenshotPrefix(in: app))-task-detail-apple-health-analytics-only",
            app: app
        )
        #endif
    }

    @MainActor
    func testAppleHealthHistoryLoadsAcrossRangesAndIPadOrientations()
        throws
    {
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif

        let app = launchApp(
            route: "task-detail",
            contentSizeCategory: "UICTContentSizeCategoryL",
            seedsDemoData: true,
            replacesDemoDataOnLaunch: true,
            taskTitle: "Running",
            additionalLaunchArguments: [
                "--uitesting-apple-health-history",
                "-AppleHealthTimelineEnabled",
                "NO",
            ]
        )

        #if os(macOS)
        try placeMainWindowOnPrimaryScreen(in: app)
        ensureTaskDetailIsReady(named: "Running", in: app)
        assertAppleHealthDetailOmitsOrdinaryTaskContent(in: app)
        let unavailable = app.descendants(matching: .any)[
            "task.detail.appleHealth.unavailable"
        ].firstMatch
        scrollUntilHittable(
            unavailable,
            direction: .up,
            maximumScrolls: 16,
            in: app
        )
        XCTAssertTrue(
            unavailable.waitForExistence(timeout: 8) &&
                unavailable.isHittable
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "task.detail.appleHealth.periodFilter"
            ].exists,
            "Historical controls must stay hidden when Apple Health is unavailable."
        )
        try capture(
            "mac-task-detail-apple-health-unavailable",
            app: app
        )
        #else
        ensureTaskDetailIsReady(named: "Running", in: app)
        assertNoAppleHealthAuthorizationSheet(in: app)
        assertAppleHealthDetailOmitsOrdinaryTaskContent(in: app)

        let loading = app.descendants(matching: .any)[
            "task.detail.appleHealth.loading"
        ].firstMatch
        let failed = app.descendants(matching: .any)[
            "task.detail.appleHealth.failed"
        ].firstMatch
        let weekChart = assertAppleHealthHistoryContent(in: app)
        assertAppleHealthDetailSectionHeaders(in: app)
        XCTAssertTrue(waitUntil(timeout: 3) {
            loading.exists == false && failed.exists == false
        })

        let rangePicker = taskDetailRangePicker(in: app)
        scrollUntilHittable(
            rangePicker,
            direction: .down,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(
            rangePicker.waitForExistence(timeout: 5) &&
                rangePicker.isHittable
        )
        let week = rangePicker.buttons["Week"].firstMatch
        XCTAssertTrue(
            week.waitForExistence(timeout: 3) &&
                week.isHittable && week.isSelected
        )
        scrollUntilHittable(
            weekChart,
            direction: .up,
            maximumScrolls: 20,
            in: app
        )
        scrollUntilFullyVisibleAboveSystemChrome(weekChart, in: app)
        XCTAssertTrue(
            isFullyVisibleAboveSystemChrome(weekChart, in: app)
        )

        let screenshotPrefix = platformScreenshotPrefix(in: app)
        waitForScreenshotTransition()
        try capture(
            "\(screenshotPrefix)-task-detail-apple-health-history-week",
            app: app
        )

        let periodTitle = app.staticTexts[
            "task.detail.appleHealth.periodTitle"
        ].firstMatch
        scrollUntilHittable(
            periodTitle,
            direction: .down,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(
            periodTitle.waitForExistence(timeout: 5) && periodTitle.isHittable
        )
        let currentWeekTitle = periodTitle.label
        XCTAssertFalse(currentWeekTitle.isEmpty)

        let periodFilter = app.descendants(matching: .any)[
            "task.detail.appleHealth.periodFilter"
        ].firstMatch
        XCTAssertTrue(periodFilter.waitForExistence(timeout: 5))
        let previousWeek = app.buttons[
            "analytics.period.previous"
        ].firstMatch
        scrollUntilHittable(
            previousWeek,
            direction: .down,
            maximumScrolls: 8,
            in: app
        )
        XCTAssertTrue(
            previousWeek.waitForExistence(timeout: 5) &&
                previousWeek.isHittable && previousWeek.isEnabled
        )
        activate(previousWeek)

        XCTAssertTrue(
            waitUntil(timeout: 8) {
                periodTitle.exists && periodTitle.label.isEmpty == false &&
                    periodTitle.label != currentWeekTitle
            },
            "Moving to the previous week must update the visible period title."
        )

        let nextWeek = app.buttons[
            "analytics.period.next"
        ].firstMatch
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                nextWeek.exists && nextWeek.isEnabled
            },
            "The next-period action must be enabled from a historical week."
        )
        waitForScreenshotTransition()
        try capture(
            "\(screenshotPrefix)-task-detail-apple-health-historical-period",
            app: app
        )

        let currentHealthRecordIdentifier =
            "task.detail.history.appleHealthWorkout." +
            "D0410000-0000-4000-8000-000000000001"
        let historicalWeekChart = assertAppleHealthHistoricalWeekContent(
            in: app,
            excludingIdentifier: currentHealthRecordIdentifier
        )
        scrollUntilHittable(
            historicalWeekChart,
            direction: .down,
            maximumScrolls: 20,
            in: app
        )
        scrollUntilFullyVisibleAboveSystemChrome(historicalWeekChart, in: app)
        XCTAssertTrue(
            isFullyVisibleAboveSystemChrome(historicalWeekChart, in: app)
        )
        waitForScreenshotTransition()
        try capture(
            "\(screenshotPrefix)-task-detail-apple-health-historical-week",
            app: app
        )

        scrollUntilHittable(
            periodTitle,
            direction: .down,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(
            periodTitle.waitForExistence(timeout: 5) && periodTitle.isHittable
        )
        let returnToToday = app.buttons[
            "analytics.period.today"
        ].firstMatch
        scrollUntilHittable(
            returnToToday,
            direction: .down,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(
            returnToToday.waitForExistence(timeout: 5) &&
                returnToToday.isHittable && returnToToday.isEnabled
        )
        activate(returnToToday)
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                periodTitle.exists && periodTitle.label == currentWeekTitle
            },
            "Returning to today must restore the current-week period title."
        )

        let pickerForMonth = taskDetailRangePicker(in: app)
        scrollUntilHittable(
            pickerForMonth,
            direction: .down,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(
            pickerForMonth.waitForExistence(timeout: 5) &&
                pickerForMonth.isHittable
        )
        let month = pickerForMonth.buttons["Month"].firstMatch
        XCTAssertTrue(
            month.waitForExistence(timeout: 3) && month.isHittable
        )
        activate(month)
        let monthChart = assertAppleHealthHistoryContent(
            in: app,
            expectedLoadedRange: "Month"
        )
        XCTAssertTrue(waitUntil(timeout: 3) {
            loading.exists == false && failed.exists == false
        })
        let refreshedPicker = taskDetailRangePicker(in: app)
        scrollUntilHittable(
            refreshedPicker,
            direction: .down,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(
            refreshedPicker.waitForExistence(timeout: 5) &&
                refreshedPicker.isHittable
        )
        let refreshedMonth = refreshedPicker.buttons["Month"].firstMatch
        XCTAssertTrue(
            refreshedMonth.waitForExistence(timeout: 3) &&
                refreshedMonth.isSelected
        )
        scrollUntilHittable(
            monthChart,
            direction: .up,
            maximumScrolls: 20,
            in: app
        )
        scrollUntilFullyVisibleAboveSystemChrome(monthChart, in: app)
        XCTAssertTrue(
            isFullyVisibleAboveSystemChrome(monthChart, in: app)
        )
        waitForScreenshotTransition()

        if screenshotPrefix == "ipad" {
            try capture(
                "ipad-task-detail-apple-health-history-month-portrait",
                app: app
            )

            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(waitUntil(timeout: 5) {
                let frame = app.windows.firstMatch.frame
                return frame.width > frame.height
            })
            let landscapeChart = app.descendants(matching: .any)[
                "task.detail.history.chart"
            ].firstMatch
            scrollUntilHittable(
                landscapeChart,
                direction: .up,
                maximumScrolls: 20,
                in: app
            )
            scrollUntilFullyVisibleAboveSystemChrome(
                landscapeChart,
                in: app
            )
            XCTAssertTrue(
                landscapeChart.waitForExistence(timeout: 5) &&
                    isFullyVisibleAboveSystemChrome(
                        landscapeChart,
                        in: app
                    )
            )
            waitForScreenshotTransition()
            try capture(
                "ipad-task-detail-apple-health-history-month-landscape",
                app: app
            )
        } else {
            try capture(
                "iphone-task-detail-apple-health-history-month",
                app: app
            )
        }
        #endif
    }

    @MainActor
    func testAppleHealthHistoryFailureUsesNativeRetryThenShowsContent()
        throws
    {
        #if os(macOS)
        throw XCTSkip("The injected Apple Health reader is iOS-only.")
        #else
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchApp(
            route: "task-detail",
            seedsDemoData: true,
            replacesDemoDataOnLaunch: true,
            taskTitle: "Running",
            additionalLaunchArguments: [
                "--uitesting-apple-health-history",
                "--uitesting-apple-health-fail-once",
                "-AppleHealthTimelineEnabled",
                "NO",
            ]
        )
        ensureTaskDetailIsReady(named: "Running", in: app)
        assertNoAppleHealthAuthorizationSheet(in: app)

        let failed = app.descendants(matching: .any)[
            "task.detail.appleHealth.failed"
        ].firstMatch
        scrollUntilHittable(
            failed,
            direction: .up,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(
            failed.waitForExistence(timeout: 8) && failed.isHittable
        )

        let retry = app.buttons[
            "task.detail.appleHealth.retry"
        ].firstMatch
        scrollUntilHittable(
            retry,
            direction: .up,
            maximumScrolls: 8,
            in: app
        )
        XCTAssertTrue(
            retry.waitForExistence(timeout: 5) &&
                retry.isHittable && retry.isEnabled
        )
        activate(retry)

        let loading = app.descendants(matching: .any)[
            "task.detail.appleHealth.loading"
        ].firstMatch
        let chart = assertAppleHealthHistoryContent(in: app)
        XCTAssertTrue(waitUntil(timeout: 5) {
            failed.exists == false && loading.exists == false
        })
        scrollUntilHittable(
            chart,
            direction: .up,
            maximumScrolls: 20,
            in: app
        )
        scrollUntilFullyVisibleAboveSystemChrome(chart, in: app)
        XCTAssertTrue(isFullyVisibleAboveSystemChrome(chart, in: app))
        waitForScreenshotTransition()
        try capture(
            "\(platformScreenshotPrefix(in: app))-task-detail-apple-health-retry",
            app: app
        )
        #endif
    }

    @MainActor
    func testAppleHealthHistoryRefreshesAfterSceneReactivation() throws {
        #if os(macOS)
        throw XCTSkip("The injected Apple Health reader is iOS-only.")
        #else
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchApp(
            route: "task-detail",
            seedsDemoData: true,
            replacesDemoDataOnLaunch: true,
            taskTitle: "Running",
            additionalLaunchArguments: [
                "--uitesting-apple-health-history",
                "--uitesting-apple-health-empty-once",
                "-AppleHealthTimelineEnabled",
                "NO",
            ]
        )
        ensureTaskDetailIsReady(named: "Running", in: app)
        assertNoAppleHealthAuthorizationSheet(in: app)

        let empty = app.descendants(matching: .any)[
            "task.detail.appleHealth.empty"
        ].firstMatch
        scrollUntilHittable(
            empty,
            direction: .up,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(
            empty.waitForExistence(timeout: 8) && empty.isHittable
        )

        let emptyMessage = app.descendants(matching: .any)[
            "task.detail.appleHealth.empty.message"
        ].firstMatch
        XCTAssertTrue(emptyMessage.waitForExistence(timeout: 5))
        XCTAssertFalse(emptyMessage.label.lowercased().contains("denied"))
        XCTAssertFalse(
            emptyMessage.label.lowercased().contains("permission denied")
        )
        try capture(
            "\(platformScreenshotPrefix(in: app))-task-detail-apple-health-empty",
            app: app
        )

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(waitUntil(timeout: 5) {
            switch app.state {
            case .runningBackground, .runningBackgroundSuspended:
                true
            default:
                false
            }
        })
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        let chart = assertAppleHealthHistoryContent(in: app)
        XCTAssertTrue(empty.waitForNonExistence(timeout: 5))
        scrollUntilFullyVisibleAboveSystemChrome(chart, in: app)
        XCTAssertTrue(isFullyVisibleAboveSystemChrome(chart, in: app))
        waitForScreenshotTransition()
        try capture(
            "\(platformScreenshotPrefix(in: app))-task-detail-apple-health-reactivated",
            app: app
        )
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
        let app = launchApp(replacesDemoDataOnLaunch: true)
        let screenshotPrefix = platformScreenshotPrefix(in: app)
        #if os(macOS)
        try placeMainWindowOnPrimaryScreen(in: app)
        #endif

        XCTAssertTrue(homeIsReady(in: app))
        try capture("\(screenshotPrefix)-typography-today", app: app)

        openSection("Inbox", tabIdentifier: "phone.tab.inbox", sidebarIdentifier: "sidebar.Inbox", in: app)
        let inboxView = app.descendants(matching: .any)["inbox.view"].firstMatch
        XCTAssertTrue(inboxView.waitForExistence(timeout: 8))
        try capture("\(screenshotPrefix)-typography-inbox", app: app)

        openSection("Tasks", tabIdentifier: "phone.tab.tasks", sidebarIdentifier: "sidebar.Tasks", in: app)
        let tasksView = app.descendants(matching: .any)["tasks.view"].firstMatch
        XCTAssertTrue(tasksView.waitForExistence(timeout: 8))
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
        try capture("\(screenshotPrefix)-typography-tasks", app: app)

        activate(firstTaskRow)
        XCTAssertTrue(taskDetailIsReady(in: app))
        try capture("\(screenshotPrefix)-typography-task-detail", app: app)

        openSection("Focus", tabIdentifier: "phone.tab.focus", sidebarIdentifier: "sidebar.Pomodoro", in: app)
        let focusView = app.descendants(matching: .any)["pomodoro.view"].firstMatch
        XCTAssertTrue(focusView.waitForExistence(timeout: 8))
        try capture("\(screenshotPrefix)-typography-focus", app: app)

        openSection("Analytics", tabIdentifier: "phone.tab.analytics", sidebarIdentifier: "sidebar.Analytics", in: app)
        XCTAssertTrue(analyticsIsReady(in: app))
        try capture("\(screenshotPrefix)-typography-analytics", app: app)

        openSettings(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["settings.view"].waitForExistence(timeout: 8))
        #if os(macOS)
        let settingsWindow = try XCTUnwrap(
            app.windows.allElementsBoundByIndex.first { window in
                window.descendants(matching: .any)["settings.view"].exists
            },
            "The macOS Settings window must exist for typography acceptance."
        )
        try placeWindowOnPrimaryScreen(settingsWindow, in: app)
        try capture(
            "\(screenshotPrefix)-typography-settings",
            element: settingsWindow
        )
        #else
        try capture("\(screenshotPrefix)-typography-settings", app: app)
        #endif
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
    func testQuickStartEditorMovesAddedTaskOutOfAvailableTasks() throws {
        #if os(macOS)
        throw XCTSkip("The Quick Start editor transition is verified on iOS.")
        #else
        let app = launchApp(replacesDemoDataOnLaunch: true)
        XCTAssertTrue(homeIsReady(in: app))

        let edit = app.buttons["home.quickStart.edit"].firstMatch
        scrollTodayUntilHittable(edit, in: app)
        XCTAssertTrue(edit.waitForExistence(timeout: 3) && edit.isHittable)
        let editor = app.descendants(matching: .any)["quickStart.editor"]
        activate(edit)
        if !editor.waitForExistence(timeout: 3) {
            scrollTodayUntilHittable(edit, in: app)
            XCTAssertTrue(edit.isHittable)
            activate(edit)
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        let available = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "quickStart.editor.available."
            )
        ).matching(
            NSPredicate(format: "label == %@", "Design macOS UI")
        ).firstMatch
        scrollUntilHittable(available, direction: .up, in: app)
        XCTAssertTrue(available.waitForExistence(timeout: 5))
        XCTAssertTrue(available.isHittable)
        let taskID = available.identifier.replacingOccurrences(
            of: "quickStart.editor.available.",
            with: ""
        )
        let pinned = app.buttons[
            "quickStart.editor.pinned.\(taskID)"
        ].firstMatch

        try capture("quick-start-editor-before-pin", app: app)
        activate(available)

        XCTAssertTrue(available.waitForNonExistence(timeout: 3))
        scrollUntilHittable(pinned, direction: .down, in: app)
        XCTAssertTrue(pinned.waitForExistence(timeout: 3))
        XCTAssertTrue(pinned.isHittable)
        XCTAssertTrue(app.staticTexts["Pinned Tasks 3"].waitForExistence(timeout: 3))
        XCTAssertEqual(pinned.value as? String, "Pinned, order 3")
        let availableHeader = app.staticTexts["Available Tasks"].firstMatch
        XCTAssertTrue(availableHeader.waitForExistence(timeout: 3))
        XCTAssertLessThan(
            pinned.frame.midY,
            availableHeader.frame.minY,
            "The added task must move into the pinned section instead of remaining below."
        )
        try capture("quick-start-editor-after-pin", app: app)

        XCTAssertTrue(pinned.isHittable)
        activate(pinned)
        XCTAssertTrue(pinned.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Pinned Tasks 2"].waitForExistence(timeout: 3))
        scrollUntilHittable(available, direction: .up, in: app)
        XCTAssertTrue(available.waitForExistence(timeout: 3))
        #endif
    }

    @MainActor
    func testQuickStartEditorReordersPinnedTasks() throws {
        let app = launchApp(replacesDemoDataOnLaunch: true)
        XCTAssertTrue(homeIsReady(in: app))
        let screenshotPrefix = platformScreenshotPrefix(in: app)

        let edit = app.buttons["home.quickStart.edit"].firstMatch
        scrollTodayUntilHittable(edit, in: app)
        XCTAssertTrue(edit.waitForExistence(timeout: 3) && edit.isHittable)
        activate(edit)
        let editor = app.descendants(matching: .any)["quickStart.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        let available = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "quickStart.editor.available."
            ))
            .matching(
                NSPredicate(format: "label == %@", "Requirements Review")
            )
            .firstMatch
        scrollUntilHittable(available, direction: .up, in: app)
        XCTAssertTrue(available.waitForExistence(timeout: 5) && available.isHittable)
        let taskID = available.identifier.replacingOccurrences(
            of: "quickStart.editor.available.",
            with: ""
        )
        activate(available)

        let pinnedRows = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "quickStart.editor.pinned."
            )
        )
        let thirdPinned = pinnedRows
            .matching(
                NSPredicate(format: "label == %@", "Requirements Review")
            )
            .firstMatch
        let secondPinned = pinnedRows
            .matching(NSPredicate(format: "label == %@", "Design System"))
            .firstMatch
        scrollUntilHittable(thirdPinned, direction: .down, in: app)
        XCTAssertTrue(thirdPinned.waitForExistence(timeout: 5))
        XCTAssertTrue(secondPinned.waitForExistence(timeout: 5))
        XCTAssertEqual(thirdPinned.value as? String, "Pinned, order 3")
        XCTAssertEqual(secondPinned.value as? String, "Pinned, order 2")
        let passedTaskID = secondPinned.identifier.replacingOccurrences(
            of: "quickStart.editor.pinned.",
            with: ""
        )

        let moveUp = app.buttons[
            "quickStart.editor.moveUp.\(taskID)"
        ].firstMatch
        XCTAssertTrue(moveUp.waitForExistence(timeout: 3))
        activate(moveUp)
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                thirdPinned.value as? String == "Pinned, order 2"
            },
            "Moving a pinned task up must update its order badge."
        )
        #if !os(macOS)
        try capture("\(screenshotPrefix)-quick-start-editor-reordered", app: app)
        #endif

        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 3) && save.isHittable)
        activate(save)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        XCTAssertTrue(homeIsReady(in: app))

        let reorderedRow = app.descendants(matching: .any)[
            "home.quickStart.task.\(taskID)"
        ].firstMatch
        let previousRow = app.descendants(matching: .any)[
            "home.quickStart.task.\(passedTaskID)"
        ].firstMatch
        scrollTodayUntilHittable(reorderedRow, in: app)
        XCTAssertTrue(reorderedRow.waitForExistence(timeout: 5))
        XCTAssertTrue(previousRow.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            reorderedRow.frame.minY,
            previousRow.frame.minY,
            "The reordered pinned task must appear above the task it passed."
        )
        #if !os(macOS)
        try capture("\(screenshotPrefix)-quick-start-home-reordered", app: app)
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
            .waitForExistence(timeout: 1)
        {
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
        let todayTab = app.descendants(matching: .any)["phone.tab.today"].firstMatch
        if phoneTabView.exists, todayTab.exists {
            XCTAssertTrue(todayTab.isSelected)
        }
        XCTAssertFalse(app.descendants(matching: .any)["tasks.view"].exists)
        try capture("quick-start-detail-returned-to-today", app: app)
        #endif
    }

    @MainActor
    func testTodayQuickStartSystemBackFlushesAutosave() throws {
        let app = launchApp(
            replacesDemoDataOnLaunch: true,
            autosaveDelayMilliseconds: 30000
        )
        XCTAssertTrue(homeIsReady(in: app))
        let screenshotPrefix = platformScreenshotPrefix(in: app)

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
        let childIdentifier = child.identifier
        XCTAssertFalse(childIdentifier.isEmpty)

        #if os(iOS)
        let usesIPadShell = app.descendants(matching: .any)["ipad.splitNavigation"]
            .waitForExistence(timeout: 1)
        #endif

        activate(child)
        XCTAssertTrue(taskDetailIsReady(in: app))
        XCTAssertTrue(app.staticTexts["Design System"].waitForExistence(timeout: 3))
        try capture(
            "\(screenshotPrefix)-today-quick-start-task-detail",
            app: app
        )

        let titleField = app.descendants(matching: .any)[
            "task.editor.title.field"
        ].firstMatch
        let updatedTitle = "Design System Updated"
        XCTAssertTrue(titleField.waitForExistence(timeout: 5) && titleField.isHittable)
        enterTaskTitle(
            updatedTitle,
            appending: " Updated",
            in: titleField
        )
        XCTAssertFalse(app.buttons["task.editor.save"].firstMatch.exists)
        XCTAssertFalse(app.buttons["task.editor.cancel"].firstMatch.exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["task.detail.addTime"]
                .firstMatch.waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["task.detail.more"]
                .firstMatch.waitForExistence(timeout: 3)
        )
        let timer = app.buttons["task.detail.timer"].firstMatch
        XCTAssertTrue(timer.waitForExistence(timeout: 3))
        XCTAssertFalse(
            timer.label.localizedCaseInsensitiveContains(updatedTitle),
            "The long UI-test debounce must leave system Back to flush this edit."
        )
        XCTAssertFalse(app.descendants(matching: .any)["task.context.edit"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tasks.view"].exists)
        try capture(
            "\(screenshotPrefix)-today-quick-start-inline-edit",
            app: app
        )

        let todayBack = taskDetailBackButton(
            to: "Today",
            in: app
        )
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

        XCTAssertTrue(
            app.descendants(matching: .any)["task.detail"]
                .firstMatch.waitForNonExistence(timeout: 5)
        )
        XCTAssertTrue(homeIsReady(in: app))
        #if os(iOS)
        if usesIPadShell == false {
            let todayTab = app.descendants(matching: .any)["phone.tab.today"].firstMatch
            if todayTab.exists {
                XCTAssertTrue(todayTab.isSelected)
            }
        }
        #endif
        XCTAssertFalse(app.descendants(matching: .any)["tasks.view"].exists)
        let updatedChild = app.buttons[childIdentifier].firstMatch
        XCTAssertTrue(updatedChild.waitForExistence(timeout: 5))
        scrollTodayUntilHittable(updatedChild, in: app)
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                updatedChild.exists &&
                    updatedChild.isHittable &&
                    updatedChild.label == updatedTitle
            },
            """
            Returning from a task detail must refresh the Today row.
            Actual label: \(updatedChild.label)
            """
        )
        XCTAssertFalse(app.buttons["editor.discard.confirm"].exists)
        try capture(
            "\(screenshotPrefix)-today-quick-start-autosave-returned",
            app: app
        )

        activate(updatedChild)
        XCTAssertTrue(taskDetailIsReady(in: app))
        let persistedTitleField = app.descendants(matching: .any)[
            "task.editor.title.field"
        ].firstMatch
        XCTAssertTrue(persistedTitleField.waitForExistence(timeout: 5))
        XCTAssertEqual(
            persistedTitleField.value as? String ?? persistedTitleField.label,
            updatedTitle
        )
        try capture(
            "\(screenshotPrefix)-today-quick-start-autosave-reopened",
            app: app
        )
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
    func testTodayPersistentExplanationsOpenFromInformationButtons() throws {
        let app = launchApp(replacesDemoDataOnLaunch: true)
        #if os(macOS)
        try placeMainWindowOnPrimaryScreen(in: app)
        #endif
        XCTAssertTrue(homeIsReady(in: app))
        let prefix = platformScreenshotPrefix(in: app)

        XCTAssertTrue(
            app.staticTexts[
                "Check what is running, review today, then continue with the next task."
            ].waitForNonExistence(timeout: 2),
            "The overview explanation must not consume persistent Home space."
        )
        let overviewInfo = app.buttons["home.overview.info"].firstMatch
        scrollUntilHittable(
            overviewInfo,
            direction: .up,
            maximumScrolls: 8,
            in: app
        )
        XCTAssertTrue(
            overviewInfo.waitForExistence(timeout: 5) && overviewInfo.isHittable
        )
        activate(overviewInfo)
        let overviewView = app.descendants(matching: .any)[
            "home.info.overview"
        ].firstMatch
        XCTAssertTrue(overviewView.waitForExistence(timeout: 5))
        for identifier in [
            "home.info.overview.summary",
            "home.info.overview.gross",
            "home.info.overview.wall",
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier]
                    .firstMatch.waitForExistence(timeout: 3),
                "Overview Info must expose \(identifier)."
            )
        }
        try capture("\(prefix)-home-overview-info", app: app)
        let overviewDone = app.descendants(matching: .any)[
            "home.info.done"
        ].firstMatch
        XCTAssertTrue(overviewDone.waitForExistence(timeout: 3))
        activate(overviewDone)
        XCTAssertTrue(overviewView.waitForNonExistence(timeout: 3))

        XCTAssertTrue(
            app.staticTexts[
                "Pinned tasks first, then frequently used recent tasks."
            ].waitForNonExistence(timeout: 2),
            "The Quick Start explanation must not remain as a persistent footer."
        )
        let quickStartInfo = app.buttons["home.quickStart.info"].firstMatch
        scrollUntilHittable(
            quickStartInfo,
            direction: .up,
            maximumScrolls: 12,
            in: app
        )
        XCTAssertTrue(
            quickStartInfo.waitForExistence(timeout: 5) && quickStartInfo.isHittable
        )
        activate(quickStartInfo)
        let quickStartView = app.descendants(matching: .any)[
            "home.info.quickStart"
        ].firstMatch
        let quickStartSummary = app.descendants(matching: .any)[
            "home.info.quickStart.summary"
        ].firstMatch
        XCTAssertTrue(quickStartView.waitForExistence(timeout: 5))
        XCTAssertTrue(quickStartSummary.waitForExistence(timeout: 3))
        let quickStartCopy = [
            quickStartSummary.label,
            quickStartSummary.value as? String ?? "",
        ].joined(separator: " ")
        XCTAssertTrue(
            quickStartCopy.localizedCaseInsensitiveContains("pinned tasks"),
            "Quick Start Info must explain pinned-task ordering. Copy: \(quickStartCopy)"
        )
        try capture("\(prefix)-home-quick-start-info", app: app)
        let quickStartDone = app.descendants(matching: .any)[
            "home.info.done"
        ].firstMatch
        XCTAssertTrue(quickStartDone.waitForExistence(timeout: 3))
        activate(quickStartDone)
        XCTAssertTrue(quickStartView.waitForNonExistence(timeout: 3))

        let forecastInfo = app.buttons["forecast.info.open"].firstMatch
        scrollUntilHittable(
            forecastInfo,
            direction: .up,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(
            forecastInfo.waitForExistence(timeout: 5) && forecastInfo.isHittable,
            "Forecast explanations must remain reachable through Info."
        )
        activate(forecastInfo)
        let forecastView = app.descendants(matching: .any)[
            "home.info.forecast"
        ].firstMatch
        let forecastRequirements = app.descendants(matching: .any)[
            "home.info.forecast.requirements"
        ].firstMatch
        XCTAssertTrue(forecastView.waitForExistence(timeout: 5))
        XCTAssertTrue(forecastRequirements.waitForExistence(timeout: 3))
        try capture("\(prefix)-home-forecast-info", app: app)
        let forecastDone = app.descendants(matching: .any)[
            "home.info.done"
        ].firstMatch
        XCTAssertTrue(forecastDone.waitForExistence(timeout: 3))
        activate(forecastDone)
        XCTAssertTrue(forecastView.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testTodayWeeklyGrossTimeChartIsVisible() throws {
        let app = launchApp(replacesDemoDataOnLaunch: true)
        #if os(macOS)
        try placeMainWindowOnPrimaryScreen(in: app)
        #endif
        XCTAssertTrue(homeIsReady(in: app))
        let header = app.descendants(matching: .any)[
            "home.weeklyGross.header"
        ].firstMatch
        let card = app.descendants(matching: .any)[
            "home.weeklyGross.card"
        ].firstMatch
        let info = app.descendants(matching: .any)[
            "home.weeklyGross.info"
        ].firstMatch
        let chart = app.descendants(matching: .any)[
            "home.weeklyGross.chart"
        ].firstMatch
        let oldInlineFooter = app.staticTexts[
            "Daily Gross Time across all tasks; overlapping timers count separately."
        ].firstMatch

        scrollTodayUntilHittable(info, in: app)
        XCTAssertTrue(
            header.waitForExistence(timeout: 5),
            "The weekly chart title must remain visible outside its card."
        )
        XCTAssertTrue(
            card.waitForExistence(timeout: 5),
            "The weekly chart must expose its card boundary for layout verification."
        )
        #if os(iOS)
        dragContentUp(by: 64, in: app)
        #endif
        XCTAssertTrue(
            info.waitForExistence(timeout: 5) && info.isHittable,
            "The weekly chart explanation must be available from its Info button."
        )
        XCTAssertTrue(header.isHittable, "The weekly title must be on-screen.")
        XCTAssertTrue(card.isHittable, "The weekly chart card must be on-screen.")
        XCTAssertTrue(
            chart.waitForExistence(timeout: 3),
            "The weekly comparison chart must expose its Gross and Wall Time summary."
        )
        let chartCopy = [
            chart.label,
            chart.value as? String ?? "",
        ].joined(separator: " ")
        XCTAssertTrue(
            chartCopy.contains("Gross Time") && chartCopy.contains("Wall Time"),
            "The weekly chart must identify both compared series. Copy: \(chartCopy)"
        )
        #if os(macOS)
        let headerText = header.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "label BEGINSWITH %@",
                    "This Week’s Time"
                )
            )
            .firstMatch
        XCTAssertTrue(headerText.waitForExistence(timeout: 3))
        let aggregateCopy = [
            headerText.label,
            headerText.value as? String ?? "",
        ].joined(separator: " ")
        XCTAssertNotEqual(
            aggregateCopy,
            "This Week’s Time ",
            "The weekly chart header must expose the aggregate comparison."
        )
        #else
        let chartSummary = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "label == %@ AND value != nil AND value != ''",
                    "This Week’s Time"
                )
            )
            .firstMatch
        let headerAggregate = app.staticTexts
            .matching(
                NSPredicate(
                    format: "label BEGINSWITH %@",
                    "This Week’s Time,"
                )
            )
            .firstMatch
        let chartValue = chartSummary.exists
            ? chartSummary.value as? String ?? ""
            : ""
        XCTAssertTrue(
            !chartValue.isEmpty || headerAggregate.exists,
            "The weekly chart section must expose its aggregate duration."
        )
        #endif
        XCTAssertLessThanOrEqual(
            header.frame.maxY,
            card.frame.minY + 2,
            "The weekly title must be positioned above, rather than inside, the chart card."
        )
        XCTAssertFalse(
            header.frame.intersects(card.frame),
            "The weekly title and chart card must have separate visual regions."
        )
        XCTAssertTrue(
            oldInlineFooter.waitForNonExistence(timeout: 2),
            "The overlap explanation must no longer consume space inside the chart card."
        )
        XCTAssertGreaterThanOrEqual(card.frame.height, 150)
        XCTAssertGreaterThan(card.frame.width, 240)
        XCTAssertTrue(
            isFrameFullyVisibleAboveSystemChrome(card, in: app),
            "The entire weekly chart card must be visible before acceptance capture."
        )
        let screenshotPrefix = platformScreenshotPrefix(in: app)
        try capture(
            "\(screenshotPrefix)-home-weekly-gross-card-hierarchy",
            app: app
        )

        activate(info)
        let informationView = app.descendants(matching: .any)[
            "home.info.weeklyGross"
        ].firstMatch
        let summary = app.descendants(matching: .any)[
            "home.info.weeklyGross.summary"
        ].firstMatch
        XCTAssertTrue(
            informationView.waitForExistence(timeout: 5),
            "Activating Info must open the weekly Gross Time explanation."
        )
        XCTAssertTrue(
            summary.waitForExistence(timeout: 5),
            "The weekly explanation must expose a concise semantic summary."
        )
        let explanation = [
            summary.label,
            summary.value as? String ?? "",
        ].joined(separator: " ").lowercased()
        XCTAssertTrue(
            explanation.contains("overlap") &&
                explanation.contains("gross time") &&
                explanation.contains("wall time") &&
                explanation.contains("two timers") &&
                explanation.contains("30 minutes") &&
                explanation.contains("60 minutes"),
            "The weekly explanation must define both time series and demonstrate overlap. Copy: \(explanation)"
        )
        try capture(
            "\(screenshotPrefix)-home-weekly-gross-info",
            app: app
        )

        let done = app.descendants(matching: .any)["home.info.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 3) && done.isHittable)
        activate(done)
        XCTAssertTrue(
            informationView.waitForNonExistence(timeout: 3),
            "Done must dismiss the weekly information surface."
        )

        #if os(iOS)
        if screenshotPrefix == "ipad" {
            XCUIDevice.shared.orientation = .landscapeLeft
            defer { XCUIDevice.shared.orientation = .portrait }
            scrollUntilHittable(
                info,
                direction: .down,
                maximumScrolls: 8,
                in: app
            )
            XCTAssertTrue(info.waitForExistence(timeout: 5) && info.isHittable)
            XCTAssertTrue(header.exists && card.exists)
            XCTAssertLessThanOrEqual(header.frame.maxY, card.frame.minY + 2)
            XCTAssertTrue(isFrameFullyVisibleAboveSystemChrome(card, in: app))
            try capture(
                "ipad-home-weekly-gross-card-landscape",
                app: app
            )
        }
        #endif
    }

    @MainActor
    func testTodayWideVisualizationsUseReadableWidth() throws {
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif

        let app = launchApp(
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: [
                "--uitesting-today-heatmap",
                "--uitesting-reset-demo-preferences",
            ]
        )
        #if os(macOS)
        try placeMainWindowOnPrimaryScreen(in: app)
        #endif
        XCTAssertTrue(homeIsReady(in: app))

        let prefix = platformScreenshotPrefix(in: app)
        if prefix == "iphone" {
            throw XCTSkip("Readable-width chart caps apply to the regular Today canvas.")
        }

        let weeklyCard = app.descendants(matching: .any)[
            "home.weeklyGross.card"
        ].firstMatch
        scrollUntilFullyVisibleAboveSystemChrome(weeklyCard, in: app)
        assertReadableHomeVisualization(
            card: weeklyCard,
            in: app
        )
        try capture("\(prefix)-home-wide-weekly-gross", app: app)

        let heatmapChart = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    "home.heatmap.chart."
                )
            )
            .firstMatch
        XCTAssertTrue(heatmapChart.waitForExistence(timeout: 8))
        let heatmapTaskID = heatmapChart.identifier.dropFirst(
            "home.heatmap.chart.".count
        )
        let heatmapScroller = app.descendants(matching: .any)[
            "home.heatmap.scroller.\(heatmapTaskID)"
        ].firstMatch
        let heatmapCard = app.descendants(matching: .any)[
            "home.heatmap.card.\(heatmapTaskID)"
        ].firstMatch
        scrollUntilFullyVisibleAboveSystemChrome(heatmapCard, in: app)
        assertReadableHomeVisualization(
            card: heatmapCard,
            contains: heatmapScroller,
            in: app
        )
        XCTAssertGreaterThan(
            heatmapChart.frame.width,
            heatmapScroller.frame.width,
            "A one-year Heatmap must keep readable cells and expose horizontal scrolling."
        )
        XCTAssertEqual(
            heatmapCard.frame.minX,
            weeklyCard.frame.minX,
            accuracy: 2,
            "The two Today visualization types must share a leading edge."
        )
        XCTAssertEqual(
            heatmapCard.frame.width,
            weeklyCard.frame.width,
            accuracy: 2,
            "The two Today visualization types must share one readable card width."
        )
        try capture("\(prefix)-home-wide-heatmap", app: app)

        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitUntil(timeout: 5) {
            let frame = app.windows.firstMatch.frame
            return frame.width > frame.height
        })

        let landscapeWeeklyCard = app.descendants(matching: .any)[
            "home.weeklyGross.card"
        ].firstMatch
        scrollUntilFullyVisibleAboveSystemChrome(landscapeWeeklyCard, in: app)
        assertReadableHomeVisualization(
            card: landscapeWeeklyCard,
            in: app
        )

        let landscapeHeatmapChart = app.descendants(matching: .any)[
            heatmapChart.identifier
        ].firstMatch
        let landscapeHeatmapScroller = app.descendants(matching: .any)[
            heatmapScroller.identifier
        ].firstMatch
        let landscapeHeatmapCard = app.descendants(matching: .any)[
            heatmapCard.identifier
        ].firstMatch
        scrollUntilFullyVisibleAboveSystemChrome(
            landscapeHeatmapCard,
            in: app
        )
        assertReadableHomeVisualization(
            card: landscapeHeatmapCard,
            contains: landscapeHeatmapScroller,
            in: app
        )
        XCTAssertGreaterThan(
            landscapeHeatmapChart.frame.width,
            landscapeHeatmapScroller.frame.width
        )
        XCTAssertEqual(
            landscapeHeatmapCard.frame.minX,
            landscapeWeeklyCard.frame.minX,
            accuracy: 2
        )
        XCTAssertEqual(
            landscapeHeatmapCard.frame.width,
            landscapeWeeklyCard.frame.width,
            accuracy: 2
        )
        try capture("ipad-home-wide-visualizations-landscape", app: app)
        #endif
    }

    @MainActor
    func testTodayVisualizationCardsAreVisuallyIndependent() throws {
        #if os(macOS)
        throw XCTSkip("Native List card separation is verified on iPhone and iPad.")
        #else
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchApp(
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: [
                "--uitesting-today-heatmap",
                "--uitesting-reset-demo-preferences",
            ]
        )
        XCTAssertTrue(initialConfigurationIsReady(in: app))
        XCTAssertTrue(homeIsReady(in: app))

        let overview = app.cells
            .containing(.any, identifier: "home.overview")
            .firstMatch
        let weeklyCard = app.descendants(matching: .any)[
            "home.weeklyGross.card"
        ].firstMatch
        let weeklyRow = app.cells
            .containing(.any, identifier: "home.weeklyGross.card")
            .firstMatch
        let heatmapsHeader = app.descendants(matching: .any)[
            "home.heatmaps.header"
        ].firstMatch
        let checklistGrid = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@",
                "Time Tracker App activity Heatmap"
            )
        ).firstMatch
        let durationGrid = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@",
                "Client Work activity Heatmap"
            )
        ).firstMatch
        let usesNativeTodayList = app.windows.firstMatch.frame.width < 700

        scrollUntilFullyVisibleAboveSystemChrome(weeklyCard, in: app)
        XCTAssertTrue(weeklyCard.waitForExistence(timeout: 5))
        var expectedNativeCardBounds: (minX: CGFloat, maxX: CGFloat)?
        if usesNativeTodayList {
            XCTAssertTrue(overview.waitForExistence(timeout: 5))
            XCTAssertTrue(weeklyRow.waitForExistence(timeout: 5))
            assertHorizontalHomeCardAlignment(
                weeklyRow,
                nativeReference: overview,
                in: app
            )
            expectedNativeCardBounds = (
                minX: weeklyRow.frame.minX,
                maxX: weeklyRow.frame.maxX
            )
        }

        scrollUntilHittable(
            heatmapsHeader,
            direction: .up,
            maximumScrolls: 10,
            in: app
        )
        XCTAssertTrue(heatmapsHeader.waitForExistence(timeout: 8))
        scrollUntilFullyVisibleAboveSystemChrome(checklistGrid, in: app)
        XCTAssertTrue(checklistGrid.waitForExistence(timeout: 8))
        let checklistCard = heatmapCard(for: checklistGrid, in: app)
        assertHeatmapCard(checklistCard, contains: checklistGrid)
        if let expectedNativeCardBounds {
            let checklistRow = app.cells
                .containing(.any, identifier: checklistCard.identifier)
                .firstMatch
            XCTAssertTrue(checklistRow.waitForExistence(timeout: 5))
            XCTAssertEqual(
                checklistRow.frame.minX,
                expectedNativeCardBounds.minX,
                accuracy: 2,
                "Heatmap and Gross Time cards must share their leading boundary."
            )
            XCTAssertEqual(
                checklistRow.frame.maxX,
                expectedNativeCardBounds.maxX,
                accuracy: 2,
                "Heatmap and Gross Time cards must share their trailing boundary."
            )
            assertSymmetricHorizontalInsets(for: checklistRow, in: app)
        }

        scrollUntilHittable(durationGrid, direction: .up, in: app)
        XCTAssertTrue(durationGrid.waitForExistence(timeout: 8))
        let durationCard = heatmapCard(for: durationGrid, in: app)
        assertHeatmapCard(durationCard, contains: durationGrid)
        if let expectedNativeCardBounds {
            let durationRow = app.cells
                .containing(.any, identifier: durationCard.identifier)
                .firstMatch
            XCTAssertTrue(durationRow.waitForExistence(timeout: 5))
            XCTAssertEqual(
                durationRow.frame.minX,
                expectedNativeCardBounds.minX,
                accuracy: 2
            )
            XCTAssertEqual(
                durationRow.frame.maxX,
                expectedNativeCardBounds.maxX,
                accuracy: 2
            )
            assertSymmetricHorizontalInsets(for: durationRow, in: app)
        }
        XCTAssertNotEqual(checklistCard.identifier, durationCard.identifier)
        XCTAssertTrue(
            scrollUntilCardBoundaryIsVisible(checklistCard, durationCard, in: app),
            "Two adjacent Heatmap card boundaries must share one acceptance view."
        )
        assertSeparateCards(checklistCard, durationCard)

        XCTAssertTrue(weeklyCard.waitForExistence(timeout: 3))
        XCTAssertFalse(weeklyCard.frame.intersects(checklistCard.frame))
        XCTAssertLessThan(weeklyCard.frame.maxY, checklistCard.frame.minY)
        XCTAssertFalse(heatmapsHeader.frame.intersects(checklistCard.frame))
        XCTAssertLessThanOrEqual(
            heatmapsHeader.frame.maxY,
            checklistCard.frame.minY + 2
        )

        let prefix = platformScreenshotPrefix(in: app)
        try capture("\(prefix)-home-visualization-card-separation", app: app)

        if prefix == "ipad" {
            XCUIDevice.shared.orientation = .landscapeLeft
            waitForScreenshotTransition()
            XCTAssertTrue(
                scrollUntilCardBoundaryIsVisible(
                    checklistCard,
                    durationCard,
                    in: app
                )
            )
            assertSeparateCards(checklistCard, durationCard)
            try capture(
                "ipad-home-visualization-card-separation-landscape",
                app: app
            )
        }
        #endif
    }

    @MainActor
    func testTodayConfiguredHeatmapsStayIndependentByTaskAndMetric() throws {
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif
        let quantityTemplateTaskID = UUID().uuidString.uppercased()
        let app = launchApp(
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: [
                "--uitesting-today-heatmap",
                "--uitesting-today-heatmap-template-id",
                quantityTemplateTaskID,
                "--uitesting-reset-demo-preferences",
            ]
        )
        #if os(macOS)
        try placeMainWindowOnPrimaryScreen(in: app)
        #else
        XCTAssertTrue(initialConfigurationIsReady(in: app))
        #endif
        XCTAssertTrue(homeIsReady(in: app))
        let heatmaps = app.descendants(matching: .any)[
            "home.heatmaps.header"
        ].firstMatch
        let checklistGrid = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@",
                "Time Tracker App activity Heatmap"
            )
        ).firstMatch
        let durationGrid = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@",
                "Client Work activity Heatmap"
            )
        ).firstMatch
        let quantityGrid = app.descendants(matching: .any)[
            "home.heatmap.grid.\(quantityTemplateTaskID)"
        ].firstMatch
        let quantityCard = app.descendants(matching: .any)[
            "home.heatmap.card.\(quantityTemplateTaskID)"
        ].firstMatch
        let checklistHeader = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "(label CONTAINS[c] %@ OR value CONTAINS[c] %@) AND (label CONTAINS[c] %@ OR value CONTAINS[c] %@)",
                "Time Tracker App",
                "Time Tracker App",
                "Checklist Completions",
                "Checklist Completions"
            )
        ).firstMatch
        let durationHeader = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "(label CONTAINS[c] %@ OR value CONTAINS[c] %@) AND (label CONTAINS[c] %@ OR value CONTAINS[c] %@)",
                "Client Work",
                "Client Work",
                "Tracked Time",
                "Tracked Time"
            )
        ).firstMatch
        let quantityHeader = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "(label CONTAINS[c] %@ OR value CONTAINS[c] %@) AND (label CONTAINS[c] %@ OR value CONTAINS[c] %@)",
                "Daily Push-ups",
                "Daily Push-ups",
                "Quantity",
                "Quantity"
            )
        ).firstMatch
        let oldChecklistFooter = app.staticTexts[
            "Daily completed checklist items for this task and its subtasks. Shades are relative to the busiest day (4 completed)."
        ].firstMatch
        let oldDurationFooter = app.staticTexts.matching(
            NSPredicate(
                format: "label BEGINSWITH %@",
                "Daily gross tracked time for this task and its subtasks."
            )
        ).firstMatch
        let oldQuantityFooter = app.staticTexts[
            "Daily quantity for this task and matching-unit subtasks. Shades show progress toward each task’s declared goal; peak 45 reps."
        ].firstMatch

        scrollUntilHittable(
            heatmaps,
            direction: .up,
            maximumScrolls: 10,
            in: app
        )
        XCTAssertTrue(
            heatmaps.waitForExistence(timeout: 8),
            "Selecting tasks must expose the task-specific Today Heatmaps."
        )
        scrollUntilFullyVisibleAboveSystemChrome(checklistGrid, in: app)
        XCTAssertTrue(
            checklistGrid.waitForExistence(timeout: 8),
            "The checklist task must have its own Heatmap."
        )
        XCTAssertTrue(checklistHeader.waitForExistence(timeout: 3))
        let checklistHeaderCopy = [
            checklistHeader.label,
            checklistHeader.value as? String ?? "",
        ].joined(separator: " ")
        XCTAssertTrue(checklistHeaderCopy.contains("9 completed"))
        #if os(iOS)
        XCTAssertEqual(
            checklistGrid.value as? String,
            "Checklist Completions. Total 9 completed across 4 active days; busiest day 4 completed."
        )
        #endif
        XCTAssertTrue(oldChecklistFooter.waitForNonExistence(timeout: 2))
        XCTAssertGreaterThan(checklistGrid.frame.width, 240)
        XCTAssertGreaterThan(checklistGrid.frame.height, 90)
        XCTAssertTrue(
            isFrameFullyVisibleAboveSystemChrome(checklistGrid, in: app)
        )
        let prefix = platformScreenshotPrefix(in: app)
        try capture("\(prefix)-home-today-heatmap-checklist", app: app)

        scrollUntilHittable(durationGrid, direction: .up, in: app)
        scrollUntilFullyVisibleAboveSystemChrome(durationGrid, in: app)
        XCTAssertTrue(
            durationGrid.waitForExistence(timeout: 8),
            "The duration task must have a separate Heatmap."
        )
        XCTAssertTrue(durationHeader.waitForExistence(timeout: 3))
        let durationHeaderCopy = [
            durationHeader.label,
            durationHeader.value as? String ?? "",
        ].joined(separator: " ")
        XCTAssertTrue(durationHeaderCopy.contains("Tracked Time"))
        XCTAssertTrue(durationHeaderCopy.contains("hr"))
        #if os(iOS)
        let durationSummary = durationGrid.value as? String ?? ""
        XCTAssertTrue(durationSummary.contains("Tracked Time"))
        XCTAssertTrue(durationSummary.contains("active days"))
        #endif
        XCTAssertTrue(oldDurationFooter.waitForNonExistence(timeout: 2))
        XCTAssertGreaterThan(durationGrid.frame.width, 240)
        XCTAssertGreaterThan(durationGrid.frame.height, 90)
        XCTAssertTrue(isFrameFullyVisibleAboveSystemChrome(durationGrid, in: app))
        #if os(iOS)
        XCTAssertNotEqual(checklistGrid.value as? String, durationGrid.value as? String)
        #endif
        try capture("\(prefix)-home-today-heatmap-duration", app: app)

        scrollUntilHittable(quantityGrid, direction: .up, in: app)
        scrollUntilFullyVisibleAboveSystemChrome(quantityGrid, in: app)
        XCTAssertTrue(
            quantityGrid.waitForExistence(timeout: 8),
            "The quantity task must have a third independent Heatmap."
        )
        XCTAssertTrue(quantityCard.waitForExistence(timeout: 3))
        assertHeatmapCard(quantityCard, contains: quantityGrid)
        XCTAssertTrue(
            quantityGrid.label.localizedCaseInsensitiveContains(
                "Daily Push-ups"
            )
        )
        XCTAssertTrue(quantityHeader.waitForExistence(timeout: 3))
        let quantityHeaderCopy = [
            quantityHeader.label,
            quantityHeader.value as? String ?? "",
        ].joined(separator: " ")
        XCTAssertTrue(quantityHeaderCopy.contains("75"))
        #if os(iOS)
        XCTAssertEqual(
            quantityGrid.value as? String,
            "Quantity · reps. Total 75 reps across 2 active days; busiest day 45 reps."
        )
        #endif
        XCTAssertTrue(oldQuantityFooter.waitForNonExistence(timeout: 2))
        XCTAssertGreaterThan(quantityGrid.frame.width, 240)
        XCTAssertGreaterThan(quantityGrid.frame.height, 90)
        XCTAssertTrue(isFrameFullyVisibleAboveSystemChrome(quantityGrid, in: app))
        #if os(iOS)
        XCTAssertNotEqual(checklistGrid.value as? String, quantityGrid.value as? String)
        XCTAssertNotEqual(durationGrid.value as? String, quantityGrid.value as? String)
        #endif
        try capture(
            "\(prefix)-home-today-heatmap-all-metrics-recurring-parent",
            app: app
        )

        let info = app.buttons["home.heatmaps.info"].firstMatch
        scrollUntilHittable(
            info,
            direction: .down,
            maximumScrolls: 14,
            in: app
        )
        #if os(iOS)
        XCTAssertTrue(
            scrollUntilFullyVisibleBelowNavigationBar(
                info,
                navigationBarTitle: "Today",
                in: app
            ),
            "Heatmap Info must be below the navigation bar before activation."
        )
        #endif
        XCTAssertTrue(
            info.waitForExistence(timeout: 5) && info.isHittable,
            "Heatmap explanations must be reachable from the section Info button."
        )
        let informationView = app.descendants(matching: .any)[
            "home.info.heatmaps"
        ].firstMatch
        waitForScreenshotTransition()
        activate(info)
        if !informationView.waitForExistence(timeout: 5) {
            let refreshedInfo = app.buttons["home.heatmaps.info"].firstMatch
            scrollUntilHittable(
                refreshedInfo,
                direction: .up,
                maximumScrolls: 14,
                in: app
            )
            if refreshedInfo.waitForExistence(timeout: 1),
               refreshedInfo.isHittable
            {
                #if os(iOS)
                _ = scrollUntilFullyVisibleBelowNavigationBar(
                    refreshedInfo,
                    navigationBarTitle: "Today",
                    in: app
                )
                #endif
                scrollUntilHittable(
                    refreshedInfo,
                    direction: .up,
                    maximumScrolls: 2,
                    in: app
                )
                waitForScreenshotTransition()
                if refreshedInfo.exists, refreshedInfo.isHittable {
                    #if os(iOS)
                    refreshedInfo.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                    ).tap()
                    #else
                    activate(refreshedInfo)
                    #endif
                }
            }
        }
        XCTAssertTrue(
            informationView.waitForExistence(timeout: 5),
            "Activating Info must open the Heatmap explanation."
        )
        let informationRows: [(identifier: String, requiredTerms: [String])] = [
            ("home.info.heatmaps.summary", ["square", "day"]),
            ("home.info.heatmaps.duration", ["tracked time", "subtasks", "overlapping timers"]),
            ("home.info.heatmaps.checklist", ["checklist", "subtasks", "each day"]),
            ("home.info.heatmaps.quantity", ["quantities", "matching-unit", "goal"]),
        ]
        for informationRow in informationRows {
            let row = app.descendants(matching: .any)[
                informationRow.identifier
            ].firstMatch
            XCTAssertTrue(
                row.waitForExistence(timeout: 3),
                "The Heatmap guide must expose \(informationRow.identifier)."
            )
            let copy = [
                row.label,
                row.value as? String ?? "",
            ].joined(separator: " ").lowercased()
            for term in informationRow.requiredTerms {
                XCTAssertTrue(
                    copy.contains(term),
                    "\(informationRow.identifier) must clearly explain \(term). Label: \(row.label)"
                )
            }
        }
        let quantityTaskExplanation = app.descendants(matching: .any)[
            "home.info.heatmaps.task.\(quantityTemplateTaskID)"
        ].firstMatch
        #if os(iOS)
        for _ in 0 ..< 8 {
            if quantityTaskExplanation.exists, quantityTaskExplanation.isHittable {
                break
            }
            let appFrame = app.frame
            let informationFrame = informationView.frame
            let horizontalPosition = (
                informationFrame.midX - appFrame.minX
            ) / appFrame.width
            let startPosition = (
                informationFrame.maxY - 36 - appFrame.minY
            ) / appFrame.height
            let endPosition = (
                informationFrame.minY + 80 - appFrame.minY
            ) / appFrame.height
            let start = app.coordinate(
                withNormalizedOffset: CGVector(
                    dx: horizontalPosition,
                    dy: startPosition
                )
            )
            let end = app.coordinate(
                withNormalizedOffset: CGVector(
                    dx: horizontalPosition,
                    dy: endPosition
                )
            )
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        #else
        for _ in 0 ..< 8 where !quantityTaskExplanation.exists {
            informationView.scroll(byDeltaX: 0, deltaY: -240)
        }
        #endif
        XCTAssertTrue(
            quantityTaskExplanation.waitForExistence(timeout: 3),
            "Heatmap Info must retain each configured task's dynamic scale explanation."
        )
        let quantityExplanationCopy = [
            quantityTaskExplanation.label,
            quantityTaskExplanation.value as? String ?? "",
        ].joined(separator: " ")
        XCTAssertTrue(
            quantityExplanationCopy.localizedCaseInsensitiveContains("peak 45 reps"),
            "The moved quantity explanation must preserve the actual peak scale."
        )
        try capture("\(prefix)-home-today-heatmap-info", app: app)

        let done = app.descendants(matching: .any)["home.info.done"].firstMatch
        if done.waitForExistence(timeout: 3), done.isHittable {
            activate(done)
            XCTAssertTrue(
                informationView.waitForNonExistence(timeout: 3),
                "Done must dismiss the Heatmap information surface."
            )
        } else {
            XCTAssertTrue(
                informationView.waitForNonExistence(timeout: 1),
                "The guide must remain dismissible or already be closed by the system sheet."
            )
        }
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
    func testTimerPickerAlignsRunningAndAvailableTaskActions() throws {
        let app = launchApp(replacesDemoDataOnLaunch: true)
        XCTAssertTrue(homeIsReady(in: app))

        let startTimer = app.buttons["home.startTimer"].firstMatch
        scrollUntilHittable(startTimer, direction: .up, in: app)
        XCTAssertTrue(startTimer.waitForExistence(timeout: 5) && startTimer.isHittable)
        XCTAssertEqual(
            startTimer.label,
            "Start Another Timer",
            "This regression must exercise the parallel-timer picker."
        )
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
        #if os(macOS)
        let pickerSheet = app.sheets.containing(
            .any,
            identifier: "timer.taskPicker"
        ).firstMatch
        XCTAssertTrue(pickerSheet.waitForExistence(timeout: 3))
        let macSearch = pickerSheet.searchFields.allElementsBoundByIndex
            .first(where: { $0.isHittable })
            ?? pickerSheet.searchFields.firstMatch
        XCTAssertTrue(
            macSearch.waitForExistence(timeout: 3) && macSearch.isHittable
        )
        activate(macSearch)
        replaceText("Study", in: macSearch)
        #endif
        let stopButtons = picker.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@",
            "timer.taskPicker.stop."
        ))
        let guideStop = stopButtons.element(boundBy: 0)
        let availableAction = picker.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@",
            "timer.taskPicker.select."
        )).firstMatch
        let runningHeader = picker.descendants(matching: .any)[
            "timer.taskPicker.runningHeader"
        ].firstMatch
        XCTAssertTrue(runningHeader.waitForExistence(timeout: 5))
        XCTAssertTrue(guideStop.waitForExistence(timeout: 5))
        XCTAssertEqual(guideStop.label, "Stop Read Apple HIG")
        XCTAssertTrue(
            waitForElement(
                availableAction,
                timeout: 5,
                diagnosticName: "timer-picker-available-action",
                in: app
            )
        )
        #if os(macOS)
        XCTAssertTrue(availableAction.isEnabled)
        XCTAssertEqual(
            availableAction.label,
            "Start Study",
            "The macOS search must settle on the deterministic visible Study result."
        )
        XCTAssertTrue(
            pickerSheet.frame.contains(guideStop.frame),
            "The running Stop action must be fully visible inside the timer-picker sheet."
        )
        XCTAssertTrue(
            pickerSheet.frame.contains(availableAction.frame),
            "The available Start action must be fully visible inside the timer-picker sheet."
        )
        #else
        XCTAssertTrue(availableAction.isHittable)
        #endif
        XCTAssertTrue(
            availableAction.label.hasPrefix("Start "),
            "An available row in Start Another Timer must expose a Start action."
        )

        #if os(macOS)
        let minimumTargetDimension: CGFloat = 28
        #else
        let minimumTargetDimension: CGFloat = 44
        let screenshotPrefix = app.windows.firstMatch.frame.width >= 700
            ? "ipad"
            : "iphone"
        #endif
        #if os(macOS)
        XCTAssertEqual(stopButtons.count, 1)
        #else
        XCTAssertGreaterThanOrEqual(stopButtons.count, 1)
        #endif
        for index in 0 ..< stopButtons.count {
            let stop = stopButtons.element(boundBy: index)
            #if os(macOS)
            XCTAssertTrue(stop.isEnabled)
            #else
            XCTAssertTrue(stop.isHittable)
            #endif
            XCTAssertGreaterThanOrEqual(stop.frame.width, minimumTargetDimension)
            XCTAssertGreaterThanOrEqual(stop.frame.height, minimumTargetDimension)
            XCTAssertEqual(
                stop.frame.width,
                availableAction.frame.width,
                accuracy: 2,
                "Start/Switch and Stop must use the same icon control width."
            )
            XCTAssertEqual(
                stop.frame.height,
                availableAction.frame.height,
                accuracy: 2,
                "Start/Switch and Stop must use the same icon control height."
            )
            XCTAssertEqual(
                stop.frame.maxX,
                availableAction.frame.maxX,
                accuracy: 2,
                "Every timer action must occupy the same trailing column."
            )
        }
        XCTAssertGreaterThanOrEqual(
            availableAction.frame.width,
            minimumTargetDimension
        )
        XCTAssertGreaterThanOrEqual(
            availableAction.frame.height,
            minimumTargetDimension
        )
        XCTAssertEqual(
            availableAction.frame.width,
            availableAction.frame.height,
            accuracy: 2,
            "Picker timer actions must remain centered icon controls on every platform."
        )
        let guideStopFrame = guideStop.frame
        let stopIdentifierPrefix = "timer.taskPicker.stop."
        XCTAssertTrue(guideStop.identifier.hasPrefix(stopIdentifierPrefix))
        let guideTaskID = String(
            guideStop.identifier.dropFirst(stopIdentifierPrefix.count)
        )
        XCTAssertFalse(guideTaskID.isEmpty)
        #if os(iOS)
        try capture(
            "\(screenshotPrefix)-timer-picker-aligned-task-actions",
            app: app
        )
        #endif

        #if os(iOS)
        XCTAssertTrue(guideStop.isHittable)
        activate(guideStop)
        XCTAssertTrue(guideStop.waitForNonExistence(timeout: 5))
        XCTAssertTrue(picker.exists)

        let search = app.searchFields[
            "Search tasks, paths, or notes"
        ].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3) && search.isHittable)
        activate(search)
        replaceText("Read Apple HIG", in: search)
        search.typeText(XCUIKeyboardKey.return.rawValue)
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 3),
            "Dismiss the search keyboard before comparing screen-space action frames."
        )
        let stoppedTask = app.buttons[
            "timer.taskPicker.select.\(guideTaskID)"
        ].firstMatch
        XCTAssertTrue(
            waitForElement(
                stoppedTask,
                timeout: 5,
                diagnosticName: "timer-picker-stopped-task-selectable",
                in: app
            ) && stoppedTask.isHittable
        )
        XCTAssertEqual(
            stoppedTask.label,
            "Start Read Apple HIG",
            "The exact task UUID must change from Stop to Start after stopping."
        )
        XCTAssertEqual(
            stoppedTask.frame.width,
            guideStopFrame.width,
            accuracy: 2,
            "The same task must keep one action-control width after Stop becomes Start."
        )
        XCTAssertEqual(
            stoppedTask.frame.height,
            guideStopFrame.height,
            accuracy: 2,
            "The same task must keep one action-control height after Stop becomes Start."
        )
        XCTAssertEqual(
            stoppedTask.frame.maxX,
            guideStopFrame.maxX,
            accuracy: 2,
            "The same task action must stay in the trailing column across state changes."
        )
        try capture(
            "\(screenshotPrefix)-timer-picker-stopped-task-selectable",
            app: app
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
    func testIPadTodayPlacesNowAndOverviewInOneAdaptiveRow() throws {
        #if os(macOS)
        throw XCTSkip("The adaptive Today status row requires an iPad simulator.")
        #else
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchApp(replacesDemoDataOnLaunch: true)
        let applicationFrame = app.frame
        guard min(applicationFrame.width, applicationFrame.height) >= 700 else {
            throw XCTSkip("This layout audit only runs on iPad.")
        }
        XCTAssertTrue(homeIsReady(in: app))

        let nowHeading = app.descendants(matching: .any)[
            "home.activeTimers.title"
        ].firstMatch
        let overviewHeading = app.descendants(matching: .any)[
            "home.overview.header.title"
        ].firstMatch
        let nowCard = app.descendants(matching: .any)[
            "home.now.card"
        ].firstMatch
        let overviewCard = app.descendants(matching: .any)[
            "home.overview.card"
        ].firstMatch
        let nowHeadingFrame = try validVisibleFrame(for: nowHeading, in: app)
        let overviewHeadingFrame = try validVisibleFrame(
            for: overviewHeading,
            in: app
        )
        let nowCardFrame = try validVisibleFrame(for: nowCard, in: app)
        let overviewCardFrame = try validVisibleFrame(
            for: overviewCard,
            in: app
        )
        XCTAssertEqual(
            nowHeadingFrame.minY,
            overviewHeadingFrame.minY,
            accuracy: 2,
            "Now and Overview must share one top-aligned row at the normal iPad width."
        )
        XCTAssertLessThan(
            nowHeadingFrame.maxX,
            overviewHeadingFrame.minX,
            "Now must remain in the leading column without overlapping Overview."
        )
        XCTAssertEqual(
            nowCardFrame.minY,
            overviewCardFrame.minY,
            accuracy: 2,
            "Now and Overview cards must share one top edge at the normal iPad width."
        )
        XCTAssertEqual(
            nowCardFrame.maxY,
            overviewCardFrame.maxY,
            accuracy: 2,
            "Now and Overview cards must share one bottom edge without an empty Overview gutter."
        )
        try capture("ipad-today-now-overview-adaptive-row", app: app)
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
            .waitForExistence(timeout: 5)
        else {
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
        for _ in 0 ..< 3 where navigationBar.frame.height >= expandedHeight - 12 {
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
    func testSidebarRunningTaskMatchesIdleSiblingRowGeometry() throws {
        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif

        let app = launchApp(replacesDemoDataOnLaunch: true)
        XCTAssertTrue(homeIsReady(in: app))

        #if os(iOS)
        guard platformScreenshotPrefix(in: app) == "ipad" else {
            throw XCTSkip("The sidebar geometry audit requires an iPad.")
        }
        #endif

        let studyDisclosure = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
                "sidebar.disclosure.",
                "Study"
            ))
            .firstMatch
        if !studyDisclosure.waitForExistence(timeout: 2) {
            #if os(iOS)
            let identifiedToggle = app.descendants(matching: .any)["sidebar.show"].firstMatch
            let systemToggle = app.buttons["Show Sidebar"].firstMatch
            if identifiedToggle.waitForExistence(timeout: 1), identifiedToggle.isHittable {
                activate(identifiedToggle)
            } else if systemToggle.waitForExistence(timeout: 1), systemToggle.isHittable {
                activate(systemToggle)
            }
            #endif
        }
        scrollUntilHittable(studyDisclosure, direction: .up, in: app)
        XCTAssertTrue(
            studyDisclosure.waitForExistence(timeout: 5) && studyDisclosure.isHittable,
            "The deterministic demo tree must expose the Study disclosure."
        )
        activate(studyDisclosure)

        let runningTask = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "sidebar.task.",
                "Read Apple HIG"
            ))
            .firstMatch
        let idleTask = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "sidebar.task.",
                "SwiftData Docs"
            ))
            .firstMatch
        scrollUntilHittable(runningTask, direction: .up, in: app)
        scrollUntilHittable(idleTask, direction: .up, in: app)
        XCTAssertTrue(runningTask.waitForExistence(timeout: 5) && runningTask.isHittable)
        XCTAssertTrue(idleTask.waitForExistence(timeout: 5) && idleTask.isHittable)

        #if os(iOS)
        let runningValue = (runningTask.value as? String ?? "").lowercased()
        let idleValue = (idleTask.value as? String ?? "").lowercased()
        XCTAssertTrue(
            runningValue.contains("running"),
            "Expected the running task value to include Running; found \(String(describing: runningTask.value))."
        )
        XCTAssertFalse(
            idleValue.contains("running"),
            "Expected the idle sibling to omit Running; found \(String(describing: idleTask.value))."
        )
        #endif
        XCTAssertEqual(runningTask.frame.minX, idleTask.frame.minX, accuracy: 1)
        XCTAssertEqual(
            runningTask.frame.height,
            idleTask.frame.height,
            accuracy: 1,
            "A running indicator must not add a metadata line or alter sidebar row spacing."
        )
        XCTAssertEqual(
            idleTask.frame.minY - runningTask.frame.maxY,
            0,
            accuracy: 2,
            "Adjacent leaf rows must not gain extra vertical spacing when the first task is running."
        )

        #if os(macOS)
        try capture("mac-sidebar-running-task-spacing", app: app)
        #else
        try capture("ipad-sidebar-running-task-spacing", app: app)
        #endif
    }

    @MainActor
    private func createInboxItem(
        _ title: String,
        in app: XCUIApplication
    ) -> InboxUITestItem {
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

        let field = app.descendants(matching: .any)[
            "inbox.capture.field"
        ].firstMatch
        let addButton = app.buttons["inbox.capture.add"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 5) {
            field.exists && field.isHittable
        })
        XCTAssertTrue(waitUntil(timeout: 5) {
            addButton.exists && addButton.isHittable
        })
        activate(field)
        replaceText(title, in: field)
        activate(addButton)

        let menu = app.descendants(matching: .any)
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

        let menuIdentifierPrefix = "inbox.item.menu."
        XCTAssertTrue(menu.identifier.hasPrefix(menuIdentifierPrefix))
        let itemIdentifier = String(
            menu.identifier.dropFirst(menuIdentifierPrefix.count)
        )
        let titleField = app.textFields[
            "inbox.item.\(itemIdentifier)"
        ].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        XCTAssertEqual(titleField.value as? String, title)
        return InboxUITestItem(
            id: itemIdentifier,
            menu: menu,
            titleField: titleField
        )
    }

    @MainActor
    private func completeInboxPickerRoute(
        pickerIdentifier: String,
        searchPrompt: String,
        searchTerm: String,
        choiceIdentifierPrefix: String,
        choiceLabel: String,
        screenshotName: String,
        in app: XCUIApplication
    ) throws {
        let picker = app.descendants(matching: .any)[
            pickerIdentifier
        ].firstMatch
        XCTAssertTrue(
            waitForElement(
                picker,
                timeout: 5,
                diagnosticName: screenshotName,
                in: app
            )
        )

        let pickerSheet = app.sheets
            .containing(.any, identifier: pickerIdentifier)
            .firstMatch
        XCTAssertTrue(pickerSheet.waitForExistence(timeout: 3))
        let search = inboxSearchField(
            prompt: searchPrompt,
            in: pickerSheet
        )
        XCTAssertTrue(search.exists && search.isHittable)
        activate(search)
        replaceText(searchTerm, in: search)

        let identifiedChoice = picker.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                choiceIdentifierPrefix
            ))
            .matching(NSPredicate(format: "label == %@", choiceLabel))
            .firstMatch
        let choice: XCUIElement
        if identifiedChoice.waitForExistence(timeout: 3) {
            choice = identifiedChoice
        } else {
            #if os(macOS)
            choice = picker.buttons[choiceLabel].firstMatch
            #else
            choice = identifiedChoice
            #endif
        }
        XCTAssertTrue(
            choice.waitForExistence(timeout: 3) &&
                choice.isHittable
        )
        waitForScreenshotTransition()
        try capture(screenshotName, app: app)
        activate(choice)
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func inboxRouteAction(
        identifierPrefix: String,
        macLabel: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        #if os(macOS)
        let nativeMenuItem = app.menuItems[macLabel].firstMatch
        if nativeMenuItem.waitForExistence(timeout: 2) {
            return nativeMenuItem
        }
        #endif

        return app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                identifierPrefix
            ))
            .firstMatch
    }

    @MainActor
    private func inboxSearchField(
        prompt: String,
        in picker: XCUIElement
    ) -> XCUIElement {
        let promptedField = picker.searchFields[prompt].firstMatch
        if promptedField.waitForExistence(timeout: 2) {
            return promptedField
        }

        return picker.searchFields.allElementsBoundByIndex.first(where: {
            $0.isHittable
        }) ?? picker.searchFields.firstMatch
    }

    @MainActor
    private func platformScreenshotPrefix(in app: XCUIApplication) -> String {
        #if os(macOS)
        "mac"
        #else
        let environment = ProcessInfo.processInfo.environment
        let modelIdentifier = environment["SIMULATOR_MODEL_IDENTIFIER"]
        let deviceName = environment["SIMULATOR_DEVICE_NAME"]
        if modelIdentifier?.hasPrefix("iPad") == true ||
            deviceName?.localizedCaseInsensitiveContains("iPad") == true
        {
            return "ipad"
        }
        if modelIdentifier?.hasPrefix("iPhone") == true ||
            deviceName?.localizedCaseInsensitiveContains("iPhone") == true
        {
            return "iphone"
        }
        let windowFrame = app.windows.firstMatch.frame
        return min(windowFrame.width, windowFrame.height) >= 700
            ? "ipad"
            : "iphone"
        #endif
    }

    @MainActor
    private func assertAppleHealthDetailOmitsOrdinaryTaskContent(
        in app: XCUIApplication
    ) {
        let ordinaryIdentifiers = [
            "task.detail.identity",
            "task.editor",
            "task.editor.title.field",
            "task.editor.parent",
            "task.detail.icon.edit",
            "task.detail.trackingUnavailable",
            "task.detail.quantity.record",
            "task.detail.quantity.progress",
            "task.detail.quantity.template",
            "task.detail.quantity.occurrence",
            "task.detail.heatmapTracking",
            "task.detail.heatmapPalette",
            "task.editor.category.readOnly",
            "task.editor.category",
            "symbol.picker.open.task",
            "task.editor.due.toggle",
            "task.editor.quantity.toggle",
            "task.editor.recurrence.daily",
            "task.editor.notes.edit",
            "task.detail.notes.markdown",
            "task.detail.autosave.failure",
            "task.detail.recovery",
            "task.editor.recovery",
            "task.detail.forecast",
            "task.detail.timer",
            "task.detail.addTime",
            "task.detail.more",
            "task.editor.cancel",
            "task.editor.save",
        ]
        let ordinaryContentPredicate = NSPredicate(
            format: "identifier IN %@",
            ordinaryIdentifiers
        )
        let bottomProbe = app.descendants(matching: .any)["task.detail.forecast"]
            .firstMatch
        #if os(macOS)
        let maximumViewport = 8
        #else
        let maximumViewport = 20
        #endif
        for viewport in 0 ... maximumViewport {
            let leakedContent = app.descendants(matching: .any)
                .matching(ordinaryContentPredicate)
                .firstMatch
            XCTAssertFalse(
                leakedContent.exists,
                "Apple Health detail exposed \(leakedContent.identifier) in viewport \(viewport)."
            )
            if viewport < maximumViewport {
                scroll(direction: .up, toward: bottomProbe, in: app)
            }
        }

        #if os(macOS)
        let topProbe = app.descendants(matching: .any)[
            "task.detail.appleHealth.unavailable"
        ].firstMatch
        #else
        let topProbe = app.staticTexts["task.detail.summary"].firstMatch
        #endif
        scrollUntilHittable(
            topProbe,
            direction: .down,
            maximumScrolls: maximumViewport + 1,
            in: app
        )
    }

    @MainActor
    private func assertAppleHealthDetailSectionHeaders(
        in app: XCUIApplication
    ) {
        let expectedHeaders: [(identifier: String, title: String)] = [
            ("task.detail.summary", "Summary"),
            ("task.detail.analysis", "Task Analysis"),
            ("task.detail.history.header", "Recent Records"),
        ]

        for (index, expected) in expectedHeaders.enumerated() {
            let header = app.staticTexts[expected.identifier].firstMatch
            scrollUntilHittable(
                header,
                direction: index == 0 ? .down : .up,
                maximumScrolls: 20,
                in: app
            )
            XCTAssertTrue(
                header.waitForExistence(timeout: 5) && header.isHittable,
                "Apple Health detail must retain the \(expected.title) section."
            )
        }

        let summary = app.staticTexts["task.detail.summary"].firstMatch
        scrollUntilHittable(
            summary,
            direction: .down,
            maximumScrolls: 20,
            in: app
        )
        let analysis = app.staticTexts["task.detail.analysis"].firstMatch
        let periodFilter = app.descendants(matching: .any)[
            "task.detail.appleHealth.periodFilter"
        ].firstMatch
        XCTAssertTrue(analysis.waitForExistence(timeout: 5))
        XCTAssertTrue(periodFilter.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            summary.frame.minY,
            analysis.frame.minY,
            "Summary must precede Task Analysis."
        )
        XCTAssertLessThan(
            analysis.frame.minY,
            periodFilter.frame.minY,
            "Period controls must live inside Task Analysis, after its header."
        )
    }

    @MainActor
    private func taskDetailRangePicker(
        in app: XCUIApplication
    ) -> XCUIElement {
        app.segmentedControls
            .containing(.button, identifier: "Week")
            .firstMatch
    }

    @MainActor
    @discardableResult
    private func assertAppleHealthHistoryContent(
        in app: XCUIApplication,
        expectedLoadedRange: String = "Week"
    ) -> XCUIElement {
        let gross = app.descendants(matching: .any)[
            "task.detail.summary.gross"
        ].firstMatch
        scrollUntilHittable(
            gross,
            direction: .up,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(
            gross.waitForExistence(timeout: 8) && gross.isHittable
        )
        assertDurationIsNonZero(gross, name: "gross")

        let wall = app.descendants(matching: .any)[
            "task.detail.summary.wall"
        ].firstMatch
        scrollUntilHittable(
            wall,
            direction: .up,
            maximumScrolls: 8,
            in: app
        )
        XCTAssertTrue(
            wall.waitForExistence(timeout: 5) && wall.isHittable
        )
        assertDurationIsNonZero(wall, name: "wall")

        let chart = app.descendants(matching: .any)[
            "task.detail.history.chart"
        ].firstMatch
        scrollUntilHittable(
            chart,
            direction: .up,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(
            chart.waitForExistence(timeout: 8) && chart.isHittable
        )
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                let loadedChart = app.descendants(matching: .any)[
                    "task.detail.history.chart"
                ].firstMatch
                return loadedChart.exists &&
                    (loadedChart.value as? String) == expectedLoadedRange
            },
            "The chart must represent the requested \(expectedLoadedRange) snapshot."
        )

        let fixedHealthRecord = app.descendants(matching: .any)[
            "task.detail.history.appleHealthWorkout." +
                "D0410000-0000-4000-8000-000000000001"
        ].firstMatch
        scrollUntilHittable(
            fixedHealthRecord,
            direction: .up,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(
            fixedHealthRecord.waitForExistence(timeout: 8) &&
                fixedHealthRecord.isHittable
        )
        XCTAssertFalse(
            app.buttons[fixedHealthRecord.identifier].exists,
            "Apple Health history must remain read-only even when ledger records are editable."
        )

        scrollUntilFullyVisibleAboveSystemChrome(chart, in: app)
        XCTAssertTrue(isFullyVisibleAboveSystemChrome(chart, in: app))
        return chart
    }

    @MainActor
    @discardableResult
    private func assertAppleHealthHistoricalWeekContent(
        in app: XCUIApplication,
        excludingIdentifier currentHealthRecordIdentifier: String
    ) -> XCUIElement {
        let gross = app.descendants(matching: .any)[
            "task.detail.summary.gross"
        ].firstMatch
        scrollUntilHittable(
            gross,
            direction: .up,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(gross.waitForExistence(timeout: 8) && gross.isHittable)
        assertDurationIsNonZero(gross, name: "historical gross")

        let wall = app.descendants(matching: .any)[
            "task.detail.summary.wall"
        ].firstMatch
        scrollUntilHittable(
            wall,
            direction: .up,
            maximumScrolls: 8,
            in: app
        )
        XCTAssertTrue(wall.waitForExistence(timeout: 5) && wall.isHittable)
        assertDurationIsNonZero(wall, name: "historical wall")

        let chart = app.descendants(matching: .any)[
            "task.detail.history.chart"
        ].firstMatch
        scrollUntilHittable(
            chart,
            direction: .up,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(chart.waitForExistence(timeout: 8) && chart.isHittable)
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                let loadedChart = app.descendants(matching: .any)[
                    "task.detail.history.chart"
                ].firstMatch
                return loadedChart.exists &&
                    (loadedChart.value as? String) == "Week"
            },
            "The chart must reload as a Week snapshot after period navigation."
        )

        let currentHealthRecord = app.descendants(matching: .any)[
            currentHealthRecordIdentifier
        ].firstMatch
        XCTAssertTrue(
            currentHealthRecord.waitForNonExistence(timeout: 8),
            "Today's fixed Apple Health record must not remain in the previous week."
        )

        let recordIdentifierPrefix =
            "task.detail.history.appleHealthWorkout."
        let historicalHealthRecord = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    recordIdentifierPrefix
                )
            )
            .firstMatch
        scrollUntilHittable(
            historicalHealthRecord,
            direction: .up,
            maximumScrolls: 20,
            in: app
        )
        XCTAssertTrue(
            historicalHealthRecord.waitForExistence(timeout: 8) &&
                historicalHealthRecord.isHittable,
            "A historical week must expose at least one Apple Health workout."
        )
        XCTAssertNotEqual(
            historicalHealthRecord.identifier,
            currentHealthRecordIdentifier
        )

        return chart
    }

    @MainActor
    private func assertDurationIsNonZero(
        _ element: XCUIElement,
        name: String
    ) {
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                let presentation = [
                    element.label,
                    element.value.map { String(describing: $0) } ?? "",
                ].joined(separator: " ")
                return presentation.range(
                    of: "[1-9][0-9]*",
                    options: .regularExpression
                ) != nil
            },
            "Apple Health \(name) duration must be non-zero."
        )
    }

    @MainActor
    private func launchApp(
        route: String = "today",
        contentSizeCategory: String? = nil,
        seedsDemoData: Bool = true,
        replacesDemoDataOnLaunch: Bool = false,
        taskTitle: String? = nil,
        additionalLaunchArguments: [String] = [],
        additionalLaunchEnvironment: [String: String] = [:],
        autosaveDelayMilliseconds: Int? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let demoDataMode = if seedsDemoData == false {
            "off"
        } else if replacesDemoDataOnLaunch {
            "replaceOnLaunch"
        } else {
            "seedIfEmpty"
        }
        app.launchArguments = [
            "--uitesting",
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-TimeTrackerAutomaticDemoDataModeOverride",
            demoDataMode,
            "-TimeTrackerAutomaticDemoSeedingDisabled",
            seedsDemoData ? "NO" : "YES",
        ]
        app.launchArguments.append(contentsOf: additionalLaunchArguments)
        if additionalLaunchArguments.contains(where: {
            $0.hasPrefix("--uitesting-apple-health")
        }) {
            app.launchEnvironment[
                "TIMETRACKER_UI_TEST_APPLE_HEALTH"
            ] = "1"
        }
        if let contentSizeCategory {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                contentSizeCategory,
            ]
        }
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"
        for (key, value) in additionalLaunchEnvironment {
            app.launchEnvironment[key] = value
        }
        app.launchEnvironment["TIMETRACKER_UI_AUDIT_ROUTE"] = route
        if let taskTitle {
            app.launchEnvironment["TIMETRACKER_UI_AUDIT_TASK_TITLE"] = taskTitle
        }
        if let autosaveDelayMilliseconds {
            app.launchEnvironment[
                "TIMETRACKER_UI_AUTOSAVE_DELAY_MILLISECONDS"
            ] = String(autosaveDelayMilliseconds)
        }
        app.launch()
        if app.state != .runningForeground {
            app.activate()
        }
        if additionalLaunchArguments.contains(where: {
            $0.hasPrefix("--uitesting-apple-health")
        }) {
            assertNoAppleHealthAuthorizationSheet(in: app)
        }
        return app
    }

    private func liveLLMUITestConfiguration()
        throws -> LiveLLMUITestConfiguration
    {
        let directory = liveLLMUIHarnessDirectoryURL()
        guard FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("run").path
        ) else {
            throw XCTSkip(
                "Live DeepSeek UI verification is opt-in; use make test-llm-live-ui."
            )
        }

        func value(named name: String) throws -> String {
            let value = try String(
                contentsOf: directory.appendingPathComponent(name),
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty == false else {
                throw LiveLLMUITestConfigurationError.emptyValue
            }
            return value
        }

        return try LiveLLMUITestConfiguration(
            endpoint: value(named: "endpoint"),
            apiKey: value(named: "api-key"),
            modelID: value(named: "model")
        )
    }

    private func liveLLMUIScreenshotDirectoryURL() throws -> URL? {
        let directory = liveLLMUIHarnessDirectoryURL()
        guard FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("run").path
        ) else {
            return nil
        }
        let path = try String(
            contentsOf: directory.appendingPathComponent("screenshot-dir"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.isEmpty == false else {
            throw LiveLLMUITestConfigurationError.emptyValue
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func liveLLMUIHarnessDirectoryURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "build/LiveLLMUIHarness",
                isDirectory: true
            )
    }

    @MainActor
    private func assertNoAppleHealthAuthorizationSheet(
        in app: XCUIApplication
    ) {
        #if os(iOS)
        let healthPrivacyService = XCUIApplication(
            bundleIdentifier: "com.apple.HealthPrivacyService"
        )
        let appAllow = app.buttons["UIA.Health.Allow.Button"].firstMatch
        let appDeny = app.buttons["UIA.Health.DoNotAllow.Button"].firstMatch
        let systemAllow = healthPrivacyService.buttons[
            "UIA.Health.Allow.Button"
        ].firstMatch
        let systemDeny = healthPrivacyService.buttons[
            "UIA.Health.DoNotAllow.Button"
        ].firstMatch
        let systemPrompt = healthPrivacyService.staticTexts[
            "Health Access"
        ].firstMatch
        let appPromptCandidates = [
            appAllow,
            appDeny,
        ]
        let systemPromptCandidates = [
            systemAllow,
            systemDeny,
            systemPrompt,
        ]
        func authorizationPromptExists() -> Bool {
            if appPromptCandidates.contains(where: \.exists) {
                return true
            }
            guard healthPrivacyService.state == .runningForeground else {
                return false
            }
            return systemPromptCandidates.contains(where: \.exists)
        }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if authorizationPromptExists() {
                XCTFail(
                    "The deterministic Apple Health fixture must never present HealthKit authorization UI."
                )
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(authorizationPromptExists())
        #endif
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
    private func assertOverlappingTimelineMarks(
        in app: XCUIApplication,
        usesHorizontalTimeAxis: Bool
    ) throws {
        let expectedTitles = ["Timeline Overlap Context"] +
            (1 ... 10).map { String(format: "Timeline Burst %02d", $0) }
        let query = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label IN %@",
                "timeline.bar.",
                expectedTitles
            )
        )
        let contextMark = query.matching(
            NSPredicate(format: "label == %@", "Timeline Overlap Context")
        ).firstMatch
        scrollTodayUntilHittable(contextMark, in: app)
        XCTAssertTrue(
            waitUntil(timeout: 5) { query.count == expectedTitles.count },
            "The isolated fixture must render one context mark and ten burst marks."
        )
        let marks: [(label: String, frame: CGRect)] =
            query.allElementsBoundByIndex.compactMap { mark in
                let frame = mark.frame
                guard frame.width > 0, frame.height > 0 else { return nil }
                return (label: mark.label, frame: frame)
            }
        XCTAssertEqual(
            marks.count,
            11,
            "The overlap fixture must stay isolated from the regular demo timeline."
        )

        let footprintTolerance: CGFloat = 0.5
        let expectedIconLabels = expectedTitles.map { "\($0) icon" }
        let icons = app.images.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label IN %@",
                "timeline.barIcon.",
                expectedIconLabels
            )
        )
        XCTAssertTrue(
            waitUntil(timeout: 5) { icons.count >= expectedIconLabels.count },
            "Every overlap bar must expose its actual SF Symbol frame."
        )
        let iconSnapshots = icons.allElementsBoundByIndex.reduce(
            into: [String: (identifier: String, frame: CGRect)]()
        ) { result, icon in
            result[icon.label] = (
                identifier: icon.identifier,
                frame: icon.frame
            )
        }
        for mark in marks {
            XCTAssertGreaterThanOrEqual(
                mark.frame.width,
                20 - footprintTolerance,
                "\(mark.label) must preserve the icon footprint horizontally."
            )
            XCTAssertGreaterThanOrEqual(
                mark.frame.height,
                20 - footprintTolerance,
                "\(mark.label) must preserve the icon footprint vertically."
            )

            let iconLabel = "\(mark.label) icon"
            let icon = try XCTUnwrap(
                iconSnapshots[iconLabel],
                "Missing actual icon element for \(mark.label)."
            )
            let iconFrame = icon.frame
            XCTAssertTrue(icon.identifier.hasPrefix("timeline.barIcon."))
            XCTAssertGreaterThan(iconFrame.width, 0)
            XCTAssertGreaterThan(iconFrame.height, 0)
            XCTAssertTrue(
                mark.frame
                    .insetBy(dx: -footprintTolerance, dy: -footprintTolerance)
                    .contains(iconFrame),
                "\(mark.label) must contain its SF Symbol accessibility element."
            )
        }

        let laneCoordinates = Set(marks.map { mark in
            let midpoint = usesHorizontalTimeAxis
                ? mark.frame.midY
                : mark.frame.midX
            return Int(midpoint.rounded())
        })
        XCTAssertGreaterThanOrEqual(
            laneCoordinates.count,
            10,
            "Ten mutually overlapping short tasks must occupy ten visual lanes."
        )

        var representativePair: (CGRect, CGRect)?
        for firstIndex in marks.indices {
            for secondIndex in marks.indices where secondIndex > firstIndex {
                let first = marks[firstIndex].frame
                let second = marks[secondIndex].frame
                let horizontalOverlap = min(first.maxX, second.maxX) -
                    max(first.minX, second.minX)
                let verticalOverlap = min(first.maxY, second.maxY) -
                    max(first.minY, second.minY)
                let timeOverlap = usesHorizontalTimeAxis
                    ? horizontalOverlap
                    : verticalOverlap
                let laneOverlap = usesHorizontalTimeAxis
                    ? verticalOverlap
                    : horizontalOverlap
                let laneDistance = usesHorizontalTimeAxis
                    ? abs(first.midY - second.midY)
                    : abs(first.midX - second.midX)
                if timeOverlap > 0, laneOverlap <= 0, laneDistance >= 6 {
                    representativePair = (first, second)
                    break
                }
            }
            if representativePair != nil {
                break
            }
        }

        _ = try XCTUnwrap(
            representativePair,
            usesHorizontalTimeAxis
                ? "Horizontal timelines must overlap in X and separate lanes in Y."
                : "The iPhone timeline must overlap in Y and separate lanes in X."
        )
    }

    @MainActor
    private func assertOverlappingTimelineRecordIcons(
        in app: XCUIApplication
    ) {
        let expectedRecords = [
            (title: "Timeline Burst 02", symbol: "star.fill"),
            (title: "Timeline Burst 01", symbol: "bolt.fill"),
            (title: "Timeline Overlap Context", symbol: "rectangle.3.group"),
        ]
        var records: [XCUIElement] = []

        for expected in expectedRecords {
            let identifierPrefix = "timeline.record.\(expected.symbol)."
            let record = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                identifierPrefix,
                expected.title
            )).firstMatch
            scrollTodayUntilHittable(record, in: app)
            XCTAssertTrue(
                record.waitForExistence(timeout: 5) && record.isHittable,
                "Missing visible \(expected.title) record with \(expected.symbol)."
            )
            XCTAssertTrue(record.identifier.hasPrefix(identifierPrefix))
            XCTAssertTrue(
                app.windows.firstMatch.frame.intersects(record.frame),
                "\(expected.title) must be visible inside the app window."
            )
            records.append(record)
        }

        XCTAssertTrue(
            records.allSatisfy { $0.exists && $0.isHittable },
            "The three fixture icon rows must be visible together for screenshot evidence."
        )
    }

    @MainActor
    private func assertTimelineGapCapsulesHugText(
        in app: XCUIApplication
    ) throws {
        let textIdentifierPrefix = "timeline.gapText."
        let intrinsicTextIdentifierPrefix = "timeline.gapIntrinsicText."
        let capsuleIdentifierPrefix = "timeline.gapCapsule."
        let timeline = app.descendants(matching: .any)["home.timeline"].firstMatch
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        let textQuery = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                textIdentifierPrefix
            )
        )
        let intrinsicTextQuery = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                intrinsicTextIdentifierPrefix
            )
        )
        let capsuleQuery = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                capsuleIdentifierPrefix
            )
        )

        XCTAssertTrue(
            waitUntil(timeout: 5) {
                textQuery.count == 2 &&
                    intrinsicTextQuery.count == 2 &&
                    capsuleQuery.count == 2
            },
            "The Timeline must expose two probes of every kind; " +
                "actual=\(textQuery.count), " +
                "intrinsic=\(intrinsicTextQuery.count), " +
                "capsule=\(capsuleQuery.count)."
        )
        XCTAssertEqual(textQuery.count, 2)
        XCTAssertEqual(intrinsicTextQuery.count, 2)
        XCTAssertEqual(capsuleQuery.count, 2)

        let textSnapshots = textQuery.allElementsBoundByIndex.reduce(
            into: [String: (label: String, frame: CGRect)]()
        ) { result, element in
            let identifier = element.identifier
            guard identifier.hasPrefix(textIdentifierPrefix) else { return }
            let gapID = String(identifier.dropFirst(textIdentifierPrefix.count))
            XCTAssertFalse(gapID.isEmpty, "A gap text probe must include its stable ID.")
            XCTAssertNil(result[gapID], "Every gap must expose one text frame probe.")
            result[gapID] = (label: element.label, frame: element.frame)
        }
        let intrinsicTextSnapshots = intrinsicTextQuery.allElementsBoundByIndex.reduce(
            into: [String: (label: String, frame: CGRect)]()
        ) { result, element in
            let identifier = element.identifier
            guard identifier.hasPrefix(intrinsicTextIdentifierPrefix) else { return }
            let gapID = String(
                identifier.dropFirst(intrinsicTextIdentifierPrefix.count)
            )
            XCTAssertFalse(gapID.isEmpty, "An intrinsic text probe must include its ID.")
            XCTAssertNil(result[gapID], "Every gap must expose one intrinsic text probe.")
            result[gapID] = (label: element.label, frame: element.frame)
        }
        let capsuleSnapshots = capsuleQuery.allElementsBoundByIndex.reduce(
            into: [String: (label: String, frame: CGRect)]()
        ) { result, element in
            let identifier = element.identifier
            guard identifier.hasPrefix(capsuleIdentifierPrefix) else { return }
            let gapID = String(identifier.dropFirst(capsuleIdentifierPrefix.count))
            XCTAssertFalse(gapID.isEmpty, "A gap capsule probe must include its stable ID.")
            XCTAssertNil(result[gapID], "Every gap must expose one capsule frame probe.")
            result[gapID] = (label: element.label, frame: element.frame)
        }

        let gapIDs = textSnapshots.keys.sorted()
        XCTAssertEqual(gapIDs, intrinsicTextSnapshots.keys.sorted())
        XCTAssertEqual(gapIDs, capsuleSnapshots.keys.sorted())
        XCTAssertEqual(gapIDs.count, 2)

        let pixelTolerance: CGFloat = 1
        let pairs = try gapIDs.map { gapID in
            let text = try XCTUnwrap(textSnapshots[gapID])
            let intrinsicText = try XCTUnwrap(intrinsicTextSnapshots[gapID])
            let capsule = try XCTUnwrap(capsuleSnapshots[gapID])
            let textFrame = text.frame
            let intrinsicTextFrame = intrinsicText.frame
            let capsuleFrame = capsule.frame

            XCTAssertEqual(text.label, intrinsicText.label)
            XCTAssertEqual(text.label, capsule.label)
            XCTAssertFalse(text.label.isEmpty)
            XCTAssertFalse(text.label.contains("…"))
            XCTAssertFalse(text.label.contains("..."))
            for frame in [textFrame, intrinsicTextFrame, capsuleFrame] {
                XCTAssertFalse(frame.isNull)
                XCTAssertFalse(frame.isInfinite)
                XCTAssertTrue(frame.origin.x.isFinite)
                XCTAssertTrue(frame.origin.y.isFinite)
                XCTAssertTrue(frame.width.isFinite)
                XCTAssertTrue(frame.height.isFinite)
                XCTAssertGreaterThan(frame.width, 0)
                XCTAssertGreaterThan(frame.height, 0)
            }
            XCTAssertEqual(
                textFrame.width,
                intrinsicTextFrame.width,
                accuracy: pixelTolerance,
                "The rendered \(text.label) text must keep its intrinsic width."
            )
            XCTAssertEqual(
                textFrame.height,
                intrinsicTextFrame.height,
                accuracy: pixelTolerance,
                "The rendered \(text.label) text must keep its intrinsic height."
            )
            XCTAssertTrue(
                app.windows.firstMatch.frame.intersects(capsuleFrame),
                "The \(text.label) capsule must remain visible in the app window."
            )

            XCTAssertTrue(
                capsuleFrame
                    .insetBy(dx: -pixelTolerance, dy: -pixelTolerance)
                    .contains(textFrame),
                "The \(text.label) capsule must contain its complete text frame."
            )

            let leadingPadding = textFrame.minX - capsuleFrame.minX
            let trailingPadding = capsuleFrame.maxX - textFrame.maxX
            let topPadding = textFrame.minY - capsuleFrame.minY
            let bottomPadding = capsuleFrame.maxY - textFrame.maxY
            XCTAssertGreaterThan(
                min(leadingPadding, trailingPadding),
                0,
                "The \(text.label) capsule must retain horizontal padding."
            )
            XCTAssertGreaterThan(
                min(topPadding, bottomPadding),
                0,
                "The \(text.label) capsule must retain vertical padding."
            )
            XCTAssertEqual(
                leadingPadding,
                trailingPadding,
                accuracy: pixelTolerance,
                "The \(text.label) capsule must hug text symmetrically in X."
            )
            XCTAssertEqual(
                topPadding,
                bottomPadding,
                accuracy: pixelTolerance,
                "The \(text.label) capsule must hug text symmetrically in Y."
            )
            XCTAssertEqual(
                capsuleFrame.width - textFrame.width,
                leadingPadding + trailingPadding,
                accuracy: pixelTolerance
            )

            return (label: text.label, text: textFrame, capsule: capsuleFrame)
        }

        XCTAssertEqual(Set(pairs.map { $0.label }).count, 2)
        let widthOrdered = pairs.sorted { $0.text.width < $1.text.width }
        let short = try XCTUnwrap(widthOrdered.first)
        let long = try XCTUnwrap(widthOrdered.last)
        XCTAssertGreaterThan(
            long.text.width,
            short.text.width,
            "The fixture must include distinct short and long localized labels."
        )
        XCTAssertGreaterThan(
            long.capsule.width,
            short.capsule.width,
            "The capsule width must grow with its localized text."
        )
        XCTAssertEqual(
            long.capsule.width - short.capsule.width,
            long.text.width - short.text.width,
            accuracy: 2 * pixelTolerance,
            "Both capsules must add the same intrinsic horizontal padding."
        )

        let frames = pairs.map { $0.capsule }.sorted { $0.minY < $1.minY }
        let first = try XCTUnwrap(frames.first)
        let second = try XCTUnwrap(frames.dropFirst().first)
        let horizontalOverlap = min(first.maxX, second.maxX) -
            max(first.minX, second.minX)

        XCTAssertFalse(
            first.intersects(second),
            "Intrinsic omitted-gap capsules must never cover one another."
        )
        if horizontalOverlap > 0 {
            XCTAssertGreaterThanOrEqual(
                second.minY - first.maxY,
                3,
                "Overlapping horizontal footprints must move to separate annotation rows."
            )
        } else {
            let horizontallyOrdered = frames.sorted { $0.minX < $1.minX }
            let horizontalSpacing = horizontallyOrdered[1].minX -
                horizontallyOrdered[0].maxX
            XCTAssertGreaterThanOrEqual(
                horizontalSpacing,
                3,
                "Same-row gap labels must retain the four-point design spacing after pixel rounding."
            )
        }
    }

    @MainActor
    private func assertPhoneTimelineAxisLabelsStayLeadingAligned(
        in app: XCUIApplication
    ) throws {
        let axisLabelPrefix = "timeline.axisLabel.vertical."
        let gapCapsulePrefix = "timeline.gapCapsule."
        let chart = app.descendants(matching: .any)[
            "home.timeline.chart"
        ].firstMatch
        let axisLabels = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                axisLabelPrefix
            )
        )
        let gapCapsules = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                gapCapsulePrefix
            )
        )

        XCTAssertTrue(
            waitUntil(timeout: 5) {
                axisLabels.count >= 2 && gapCapsules.count == 2
            },
            """
            The compact Timeline must expose at least two time labels and two \
            skipped-gap capsules; labels=\(axisLabels.count), \
            capsules=\(gapCapsules.count).
            """
        )

        let chartFrame = try validVisibleFrame(for: chart, in: app)
        let axisFrames = try axisLabels.allElementsBoundByIndex.map {
            try validVisibleFrame(for: $0, in: app)
        }
        let capsuleFrames = try gapCapsules.allElementsBoundByIndex.map {
            try validVisibleFrame(for: $0, in: app)
        }
        let pixelTolerance: CGFloat = 2

        XCTAssertGreaterThanOrEqual(axisFrames.count, 2)
        XCTAssertEqual(capsuleFrames.count, 2)
        for frame in axisFrames {
            XCTAssertEqual(
                frame.minX,
                chartFrame.minX,
                accuracy: pixelTolerance,
                "Every compact time label must share the chart leading edge."
            )
            XCTAssertTrue(
                chartFrame
                    .insetBy(dx: -pixelTolerance, dy: -pixelTolerance)
                    .contains(frame),
                "Every compact time label must remain inside the Timeline chart."
            )
            for capsuleFrame in capsuleFrames {
                XCTAssertFalse(
                    frame.intersects(capsuleFrame),
                    "Time labels must continue yielding vertically to skipped gaps."
                )
            }
        }

        let leadingEdges = axisFrames.map(\.minX)
        let minimumLeadingEdge = try XCTUnwrap(leadingEdges.min())
        let maximumLeadingEdge = try XCTUnwrap(leadingEdges.max())
        XCTAssertLessThanOrEqual(
            maximumLeadingEdge - minimumLeadingEdge,
            pixelTolerance,
            "Start, interior, and end time labels must use one leading anchor."
        )

        XCTAssertFalse(
            capsuleFrames[0].intersects(capsuleFrames[1]),
            "Skipped-gap capsules must remain collision-free."
        )
    }

    @MainActor
    private func initialConfigurationIsReady(
        in app: XCUIApplication
    ) -> Bool {
        app.descendants(matching: .any)[
            "app.initialConfiguration.ready"
        ].firstMatch.waitForExistence(timeout: 20)
    }

    @MainActor
    private func analyticsIsReady(in app: XCUIApplication) -> Bool {
        guard app.descendants(matching: .any)["analytics.view"].waitForExistence(timeout: 8),
              app.descendants(matching: .any)["analytics.periodFilter"]
              .waitForExistence(timeout: 8)
        else {
            return false
        }
        return app.descendants(matching: .any)["analytics.summary"]
            .firstMatch
            .waitForExistence(timeout: 8)
    }

    @MainActor
    private func verifyAnalyticsCategory(
        _ expectation: (
            id: String,
            question: String,
            answer: String,
            destination: String
        ),
        in app: XCUIApplication
    ) {
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

    @MainActor
    private func launchSeededInboxSuggestions() -> XCUIApplication {
        let app = launchApp(
            contentSizeCategory: "UICTContentSizeCategoryL",
            replacesDemoDataOnLaunch: true,
            additionalLaunchArguments: ["--uitesting-inbox-suggestion"]
        )
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
        return app
    }

    @MainActor
    private func applySeededInboxSuggestion(
        kind: String,
        itemTitle: String,
        summary: String,
        in app: XCUIApplication
    ) {
        let suggestion = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "inbox.suggestion.ready.\(kind)."
            ))
            .firstMatch
        let apply = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "inbox.suggestion.apply.\(kind)."
            ))
            .firstMatch
        let itemField = app.textFields
            .matching(NSPredicate(format: "value == %@", itemTitle))
            .firstMatch

        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        XCTAssertEqual(suggestion.label, summary)
        XCTAssertTrue(itemField.waitForExistence(timeout: 5))
        scrollUntilHittable(apply, direction: .up, in: app)
        XCTAssertTrue(apply.isHittable)
        activate(apply)
        XCTAssertTrue(suggestion.waitForNonExistence(timeout: 5))
        XCTAssertTrue(itemField.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func expandTask(
        named title: String,
        in app: XCUIApplication
    ) {
        let disclosure = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND value == %@",
                "tasks.disclosure.",
                title
            ))
            .firstMatch
        scrollUntilHittable(disclosure, direction: .up, in: app)
        XCTAssertTrue(
            disclosure.waitForExistence(timeout: 5) && disclosure.isHittable
        )
        activate(disclosure)
    }

    private func taskRow(
        named title: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "tasks.row.",
                title
            ))
            .firstMatch
    }

    private func taskCategorySortRow(
        named title: String,
        in sorter: XCUIElement
    ) -> XCUIElement {
        sorter.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "taskCategory.sort.row.",
                title
            ))
            .firstMatch
    }

    private func taskCategoryID(
        fromSortRow row: XCUIElement
    ) throws -> String {
        let prefix = "taskCategory.sort.row."
        XCTAssertTrue(
            row.identifier.hasPrefix(prefix),
            "A Category sorter row must carry its stable Category identifier."
        )
        let identifier = String(row.identifier.dropFirst(prefix.count))
        _ = try XCTUnwrap(
            UUID(uuidString: identifier),
            "A Category sorter row identifier must end in a UUID."
        )
        return identifier
    }

    private func recurringTaskRow(
        named title: String,
        role: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "tasks.row.",
                title
            ))
            .matching(NSPredicate(
                format: "value CONTAINS[c] %@",
                role
            ))
            .firstMatch
    }

    @MainActor
    private func taskDetailIsReady(in app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)["task.detail"].waitForExistence(timeout: 5)
    }

    @MainActor
    private func taskDetailBackButton(
        to destinationTitle: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        #if os(macOS)
        app.windows
            .containing(.any, identifier: "task.detail")
            .firstMatch
            .buttons["Back"]
            .firstMatch
        #else
        app.navigationBars.buttons[destinationTitle].firstMatch
        #endif
    }

    @MainActor
    private func openTaskDetailFromTasks(
        named title: String,
        parentTitle: String = "Study",
        in app: XCUIApplication
    ) {
        openSection(
            "Tasks",
            tabIdentifier: "phone.tab.tasks",
            sidebarIdentifier: "sidebar.Tasks",
            in: app
        )
        let tasksView = app.descendants(matching: .any)["tasks.view"]
        let searchField = app.descendants(matching: .any)[
            "tasks.search.field"
        ].firstMatch
        let anyTaskRow = app.buttons
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@",
                "tasks.row."
            ))
            .firstMatch
        let tasksRootIsInteractive = {
            tasksView.exists &&
                (
                    tasksView.isHittable ||
                        searchField.isHittable ||
                        anyTaskRow.isHittable
                )
        }
        if waitUntil(timeout: 2, condition: tasksRootIsInteractive) == false {
            let detail = app.descendants(matching: .any)["task.detail"]
                .firstMatch
            XCTAssertTrue(
                detail.waitForExistence(timeout: 3),
                "Returning to Tasks may restore its retained detail stack."
            )
            let tasksBack = taskDetailBackButton(
                to: "Tasks",
                in: app
            )
            XCTAssertTrue(
                tasksBack.waitForExistence(timeout: 5) && tasksBack.isHittable,
                "The retained task detail must expose the system Tasks back action."
            )
            activate(tasksBack)
            XCTAssertTrue(detail.waitForNonExistence(timeout: 5))
        }
        XCTAssertTrue(
            waitUntil(timeout: 5, condition: tasksRootIsInteractive),
            "The Tasks root must be visible and interactive before reopening a task."
        )

        if searchField.waitForExistence(timeout: 3), searchField.isHittable {
            activate(searchField)
            replaceText(title, in: searchField)
            let matchingTask = app.buttons
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "tasks.row."))
                .matching(NSPredicate(format: "label == %@", title))
                .firstMatch
            XCTAssertTrue(
                matchingTask.waitForExistence(timeout: 5) && matchingTask.isHittable
            )
            activate(matchingTask)
            return
        }

        let task = taskRow(named: title, in: app)
        if task.waitForExistence(timeout: 1) {
            scrollUntilHittable(task, direction: .up, in: app)
            XCTAssertTrue(task.isHittable)
            activate(task)
            return
        }

        let parentDisclosure = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "tasks.disclosure."))
            .matching(NSPredicate(format: "value == %@", parentTitle))
            .firstMatch
        scrollUntilHittable(parentDisclosure, direction: .up, in: app)
        XCTAssertTrue(
            parentDisclosure.waitForExistence(timeout: 5) &&
                parentDisclosure.isHittable
        )
        activate(parentDisclosure)

        scrollUntilHittable(task, direction: .up, in: app)
        XCTAssertTrue(task.waitForExistence(timeout: 5) && task.isHittable)
        activate(task)
    }

    @MainActor
    private func ensureTaskDetailIsReady(
        named title: String,
        in app: XCUIApplication
    ) {
        guard taskDetailIsReady(in: app) == false else { return }
        openTaskDetailFromTasks(named: title, in: app)
        XCTAssertTrue(
            taskDetailIsReady(in: app),
            "The requested task detail must be available after route fallback."
        )
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
        if identifiedElement.waitForExistence(timeout: 1),
           identifiedElement.firstMatch.isHittable
        {
            activate(identifiedElement.firstMatch)
            return
        }

        if openCollapsedSidebarDestination(sidebarIdentifier, in: app) {
            return
        }

        let identifiedTab = app.descendants(matching: .any)[tabIdentifier]
        #if os(iOS)
        let identifiedTabExists = identifiedTab.waitForExistence(timeout: 2)
        if app.descendants(matching: .any)["phone.tabView"].exists,
           !identifiedTabExists || !identifiedTab.firstMatch.isHittable
        {
            // Focusing an inline field can minimize the system tab bar. Reveal
            // it through the same reverse-scroll gesture a user performs before
            // asking XCTest to activate a destination.
            app.swipeDown()
        }
        #endif
        if identifiedTab.waitForExistence(timeout: 2),
           identifiedTab.firstMatch.isHittable
        {
            activate(identifiedTab.firstMatch)
            return
        }

        #if os(iOS)
        if identifiedTab.firstMatch.exists {
            let tabFrame = identifiedTab.firstMatch.frame
            let appFrame = app.frame
            if tabFrame.width > 0,
               tabFrame.height > 0,
               appFrame.intersects(tabFrame)
            {
                // Xcode 27 beta can report {-1, -1} as the visible point for a
                // visually present SwiftUI Tab. A real touch at its frame center
                // still follows the production interaction path.
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(
                        CGVector(
                            dx: tabFrame.midX - appFrame.minX,
                            dy: tabFrame.midY - appFrame.minY
                        )
                    )
                    .tap()
                return
            }
        }
        #endif

        let titledTab = app.tabBars.buttons[tabTitle].firstMatch
        if titledTab.waitForExistence(timeout: 3), titledTab.isHittable {
            activate(titledTab)
            return
        }

        let titledButton = app.buttons[tabTitle].firstMatch
        if titledButton.waitForExistence(timeout: 1), titledButton.isHittable {
            activate(titledButton)
            return
        }

        let titledText = app.staticTexts[tabTitle].firstMatch
        if titledText.waitForExistence(timeout: 1), titledText.isHittable {
            activate(titledText)
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

        #if os(iOS)
        if app.descendants(matching: .any)["ipad.splitNavigation"]
            .waitForExistence(timeout: 1)
        {
            XCTAssertTrue(
                openCollapsedSidebarDestination("sidebar.Settings", in: app)
            )
            return
        }
        #endif

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
        let mainWindow = try XCTUnwrap(
            app.windows.allElementsBoundByIndex.max { lhs, rhs in
                lhs.frame.width * lhs.frame.height <
                    rhs.frame.width * rhs.frame.height
            },
            "The macOS app window must exist before capturing \(name)."
        )
        let screenshot = mainWindow.screenshot()
        XCTAssertGreaterThan(
            screenshot.pngRepresentation.count,
            1024,
            "The macOS app window must produce a valid PNG for \(name)."
        )
        #endif
        try recordScreenshot(screenshot, name: name)
    }

    @MainActor
    private func capture(_ name: String, element: XCUIElement) throws {
        XCTAssertTrue(element.exists, "Screenshot target must exist: \(name)")
        XCTAssertTrue(element.isHittable, "Screenshot target must be visible: \(name)")

        let frame = element.frame
        XCTAssertTrue(
            frame.origin.x.isFinite &&
                frame.origin.y.isFinite &&
                frame.width.isFinite &&
                frame.height.isFinite,
            "Screenshot target must have a finite frame: \(name)"
        )
        XCTAssertGreaterThan(frame.width, 0, "Screenshot target must have width: \(name)")
        XCTAssertGreaterThan(frame.height, 0, "Screenshot target must have height: \(name)")

        let screenshot = element.screenshot()
        XCTAssertGreaterThan(
            screenshot.pngRepresentation.count,
            1024,
            "Screenshot target must produce a valid PNG: \(name)"
        )
        try recordScreenshot(screenshot, name: name)
    }

    #if os(macOS)
    @MainActor
    private func placeMainWindowOnPrimaryScreen(
        in app: XCUIApplication
    ) throws {
        let uiWindow = app.windows.firstMatch
        try placeWindowOnPrimaryScreen(uiWindow, in: app)
    }

    @MainActor
    private func placeWindowOnPrimaryScreen(
        _ uiWindow: XCUIElement,
        in app: XCUIApplication
    ) throws {
        XCTAssertTrue(uiWindow.waitForExistence(timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3))
        uiWindow.coordinate(
            withNormalizedOffset: CGVector(dx: 0.85, dy: 0.02)
        ).click()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3))
        let primaryScreen = try XCTUnwrap(
            NSScreen.screens.first { $0.frame.origin == .zero },
            "The primary macOS screen must be available"
        )
        let primaryScreenFrame = CGRect(
            origin: .zero,
            size: primaryScreen.frame.size
        )
        var expectsPrimaryContainment = primaryScreenFrame.contains(
            uiWindow.frame
        )
        if !primaryScreenFrame.contains(uiWindow.frame) {
            let windowMenu = app.menuBars.menuBarItems["Window"].firstMatch
            XCTAssertTrue(
                windowMenu.waitForExistence(timeout: 3) &&
                    windowMenu.isHittable,
                "The macOS Window menu must be scriptable by XCUITest."
            )
            windowMenu.click()

            let targetDisplayItem = app.menuItems
                .matching(identifier: "_moveToDisplay:")
                .allElementsBoundByIndex
                .first { item in
                    item.title.localizedCaseInsensitiveContains(
                        primaryScreen.localizedName
                    ) || item.label.localizedCaseInsensitiveContains(
                        primaryScreen.localizedName
                    )
                }
            if let targetDisplayItem,
               targetDisplayItem.waitForExistence(timeout: 3),
               targetDisplayItem.isHittable
            {
                targetDisplayItem.click()
                expectsPrimaryContainment = true
            } else {
                let centerItem = app.menuItems
                    .matching(identifier: "_zoomCenter:")
                    .firstMatch
                if centerItem.waitForExistence(timeout: 3),
                   centerItem.isHittable
                {
                    centerItem.click()
                    expectsPrimaryContainment = true
                } else {
                    app.typeKey(.escape, modifierFlags: [])
                }
            }
        }

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3))
        XCTAssertTrue(waitUntil(timeout: 3) {
            let frame = uiWindow.frame
            return frame.width > 0 &&
                frame.height > 0 &&
                (expectsPrimaryContainment == false ||
                    primaryScreenFrame.contains(frame))
        }, "The macOS UI-test window must remain visible after scripted placement")
        uiWindow.coordinate(
            withNormalizedOffset: CGVector(dx: 0.85, dy: 0.02)
        ).click()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3))
    }
    #endif

    @MainActor
    private func recordScreenshot(
        _ screenshot: XCUIScreenshot,
        name: String
    ) throws {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directoryURL: URL
        if let directory = ProcessInfo.processInfo.environment["UI_SCREENSHOT_DIR"],
           !directory.isEmpty
        {
            directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        } else {
            #if os(iOS)
            directoryURL = try XCTUnwrap(
                screenshotRunDirectoryURL,
                "setUp must prepare an isolated screenshot directory."
            )
            #else
            return
            #endif
        }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try screenshot.pngRepresentation.write(
            to: directoryURL.appendingPathComponent("\(name).png")
        )
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
    private func activateVisibleButton(
        _ button: XCUIElement,
        diagnosticName: String
    ) -> Bool {
        guard button.waitForExistence(timeout: 3) else {
            XCTFail("Missing \(diagnosticName) button.")
            return false
        }
        if button.isHittable {
            activate(button)
            return true
        }

        let frame = button.frame
        guard frame.isNull == false,
              frame.isInfinite == false,
              frame.isEmpty == false
        else {
            XCTFail("The visible \(diagnosticName) button needs a finite frame.")
            return false
        }
        button.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
        return true
    }

    @MainActor
    private func enterTaskTitle(
        _ title: String,
        appending suffix: String,
        in field: XCUIElement
    ) {
        #if os(macOS)
        activate(field)
        replaceText(title, in: field)
        #else
        field.coordinate(
            withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)
        ).tap()
        field.typeText(suffix)
        #endif
        XCTAssertEqual(field.value as? String ?? field.label, title)
    }

    @MainActor
    private func submitTaskTitleIfKeyboardIsVisible(
        _ field: XCUIElement,
        in app: XCUIApplication
    ) {
        #if os(iOS)
        let keyboard = app.keyboards.firstMatch
        if keyboard.waitForExistence(timeout: 1) {
            field.typeText(XCUIKeyboardKey.return.rawValue)
            XCTAssertTrue(
                keyboard.waitForNonExistence(timeout: 3),
                "Submitting the title must release the keyboard before navigation."
            )
        }
        #endif
    }

    @MainActor
    private func replaceText(
        _ text: String,
        in element: XCUIElement
    ) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        let preservedItems = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(
                into: [NSPasteboard.PasteboardType: Data]()
            ) { contents, type in
                contents[type] = item.data(forType: type)
            }
        } ?? []
        defer {
            pasteboard.clearContents()
            let restoredItems = preservedItems.map { contents in
                let item = NSPasteboardItem()
                for (type, data) in contents {
                    item.setData(data, forType: type)
                }
                return item
            }
            if restoredItems.isEmpty == false {
                pasteboard.writeObjects(restoredItems)
            }
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        element.typeKey("a", modifierFlags: .command)
        element.typeKey("v", modifierFlags: .command)
        #else
        element.typeText(text)
        #endif
    }

    @MainActor
    private func replaceNumericText(
        _ text: String,
        in element: XCUIElement
    ) {
        #if os(macOS)
        activate(element)
        replaceText(text, in: element)
        #else
        activate(element)
        element.typeKey("a", modifierFlags: .command)
        element.typeText(text)
        #endif
    }

    @MainActor
    private func replaceTextCharacterByCharacter(
        _ text: String,
        in element: XCUIElement
    ) {
        activate(element)
        element.typeKey("a", modifierFlags: .command)
        var expected = ""
        for character in text {
            expected.append(character)
            element.typeText(String(character))
            XCTAssertTrue(waitUntil(timeout: 1) {
                (element.value as? String) == expected
            })
        }
    }

    @MainActor
    private func scrollUntilHittable(
        _ element: XCUIElement,
        direction: ScrollDirection,
        maximumScrolls: Int = 6,
        in app: XCUIApplication
    ) {
        for _ in 0 ..< maximumScrolls where !element.isHittable {
            scroll(direction: direction, toward: element, in: app)
        }
    }

    @MainActor
    private func gentlyScrollUntilHittable(
        _ element: XCUIElement,
        direction: ScrollDirection,
        maximumScrolls: Int = 14,
        in app: XCUIApplication
    ) {
        #if os(macOS)
        scrollUntilHittable(
            element,
            direction: direction,
            maximumScrolls: maximumScrolls,
            in: app
        )
        #else
        let startY: CGFloat = direction == .up ? 0.68 : 0.34
        let endY: CGFloat = direction == .up ? 0.56 : 0.46
        for _ in 0 ..< maximumScrolls where !element.isHittable {
            let start = app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: startY)
            )
            let end = app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: endY)
            )
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        #endif
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

        for _ in 0 ..< 6 where !element.isHittable {
            #if os(macOS)
            scroll(direction: .up, toward: element, in: app)
            #else
            dragContentUp(by: app.frame.height * 0.25, in: app)
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
        let appWindowFrame = app.windows.firstMatch.frame
        let targetScrollView = app.scrollViews.allElementsBoundByIndex
            .filter { scrollView in
                let frame = scrollView.frame
                return frame.width > 0 &&
                    frame.minX <= targetX &&
                    frame.maxX >= targetX &&
                    appWindowFrame.intersects(frame) &&
                    scrollView.isHittable
            }
            .max { $0.frame.height < $1.frame.height }
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
        #if os(macOS)
        for _ in 0 ..< 12 where !isFrameFullyVisibleAboveSystemChrome(element, in: app) {
            let windowFrame = app.windows.firstMatch.frame
            let direction: ScrollDirection = element.exists &&
                element.frame.minY < windowFrame.minY
                ? .down
                : .up
            scroll(direction: direction, toward: element, in: app)
        }
        #else
        for _ in 0 ..< 12 where !isFullyVisibleAboveSystemChrome(element, in: app) {
            let unobscuredBottom = systemChromeTop(in: app)
            let frame = element.frame

            if element.exists, frame.minY < app.frame.minY + 8 {
                dragContentDown(
                    by: app.frame.minY + 28 - frame.minY,
                    in: app
                )
            } else if element.exists,
                      frame.maxY > unobscuredBottom - 8
            {
                dragContentUp(
                    by: frame.maxY - unobscuredBottom + 20,
                    in: app
                )
            } else {
                app.swipeUp()
            }
        }
        #endif
    }

    @MainActor
    private func scrollUntilFrameFullyVisibleAboveSystemChrome(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) {
        for _ in 0 ..< 12 where
            !isFrameFullyVisibleAboveSystemChrome(element, in: app)
        {
            #if os(macOS)
            let windowFrame = app.windows.firstMatch.frame
            let direction: ScrollDirection = element.exists &&
                element.frame.minY < windowFrame.minY
                ? .down
                : .up
            scroll(direction: direction, toward: element, in: app)
            #else
            let unobscuredBottom = systemChromeTop(in: app)
            let frame = element.frame

            if element.exists, frame.minY < app.frame.minY + 8 {
                dragContentDown(
                    by: app.frame.minY + 28 - frame.minY,
                    in: app
                )
            } else if element.exists,
                      frame.maxY > unobscuredBottom - 8
            {
                dragContentUp(
                    by: frame.maxY - unobscuredBottom + 20,
                    in: app
                )
            } else {
                dragContentUp(by: 80, in: app)
            }
            #endif
        }
    }

    @MainActor
    private func scrollUntilFullyVisibleBelowNavigationBar(
        _ element: XCUIElement,
        navigationBarTitle: String,
        in app: XCUIApplication
    ) -> Bool {
        #if os(macOS)
        return element.isHittable
        #else
        let navigationBar = app.navigationBars[navigationBarTitle].firstMatch
        guard navigationBar.waitForExistence(timeout: 2) else {
            return element.isHittable
        }

        for _ in 0 ..< 5 {
            if element.isHittable,
               element.frame.minY >= navigationBar.frame.maxY + 8
            {
                return true
            }

            if element.exists,
               element.frame.minY < navigationBar.frame.maxY + 8
            {
                let start = app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40)
                )
                let end = app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.46)
                )
                start.press(forDuration: 0.05, thenDragTo: end)
            } else {
                scroll(direction: .up, toward: element, in: app)
            }
        }

        return element.isHittable
            && element.frame.minY >= navigationBar.frame.maxY + 8
        #endif
    }

    @MainActor
    private func isFullyVisibleAboveSystemChrome(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        guard element.isHittable else { return false }
        return isFrameFullyVisibleAboveSystemChrome(element, in: app)
    }

    @MainActor
    private func isFrameFullyVisibleAboveSystemChrome(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        guard element.exists else { return false }

        #if os(macOS)
        let windowFrame = app.windows.firstMatch.frame
        return element.frame.minY >= windowFrame.minY
            && element.frame.maxY <= windowFrame.maxY - 8
        #else
        let unobscuredBottom = systemChromeTop(in: app)
        return element.frame.minY >= app.frame.minY
            && element.frame.maxY <= unobscuredBottom - 8
        #endif
    }

    @MainActor
    private func validVisibleFrame(
        for element: XCUIElement,
        in app: XCUIApplication,
        requiresFullVisibility: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> CGRect {
        XCTAssertTrue(
            element.waitForExistence(timeout: 5),
            "Expected geometry probe to exist.",
            file: file,
            line: line
        )
        let frame = element.frame
        let values = [
            frame.minX,
            frame.minY,
            frame.width,
            frame.height,
        ]
        XCTAssertTrue(
            values.allSatisfy(\.isFinite),
            "Geometry probe must expose a finite frame: \(frame)",
            file: file,
            line: line
        )
        XCTAssertGreaterThan(
            frame.width,
            0,
            "Geometry probe must have positive width.",
            file: file,
            line: line
        )
        XCTAssertGreaterThan(
            frame.height,
            0,
            "Geometry probe must have positive height.",
            file: file,
            line: line
        )
        #if os(macOS)
        let applicationFrame = app.windows.firstMatch.frame
        #else
        let applicationFrame = app.frame
        #endif
        XCTAssertTrue(
            applicationFrame
                .insetBy(dx: -2, dy: -2)
                .contains(frame),
            "Geometry probe must remain inside the app window: \(frame)",
            file: file,
            line: line
        )
        if requiresFullVisibility {
            XCTAssertTrue(
                isFrameFullyVisibleAboveSystemChrome(element, in: app),
                "Geometry probe must be fully visible: \(frame)",
                file: file,
                line: line
            )
        }
        return frame
    }

    @MainActor
    private func heatmapCard(
        for grid: XCUIElement,
        in app: XCUIApplication
    ) -> XCUIElement {
        let gridPrefix = "home.heatmap.grid."
        XCTAssertTrue(
            grid.identifier.hasPrefix(gridPrefix),
            "Heatmap grids must expose their task identity."
        )
        let taskID = grid.identifier.dropFirst(gridPrefix.count)
        return app.descendants(matching: .any)[
            "home.heatmap.card.\(taskID)"
        ].firstMatch
    }

    @MainActor
    private func assertHeatmapCard(
        _ card: XCUIElement,
        contains grid: XCUIElement
    ) {
        XCTAssertTrue(
            card.waitForExistence(timeout: 3),
            "Every Heatmap must expose its own card boundary."
        )
        XCTAssertTrue(
            card.frame.insetBy(dx: -2, dy: -2).contains(grid.frame),
            "A Heatmap grid must belong only to its task card."
        )
    }

    @MainActor
    private func assertReadableHomeVisualization(
        card: XCUIElement,
        contains plot: XCUIElement? = nil,
        in app: XCUIApplication
    ) {
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        let cardFrame = card.frame
        let windowFrame = app.windows.firstMatch.frame
        XCTAssertTrue(
            cardFrame.origin.x.isFinite &&
                cardFrame.origin.y.isFinite &&
                cardFrame.width.isFinite &&
                cardFrame.height.isFinite
        )
        XCTAssertGreaterThan(cardFrame.width, 0)
        XCTAssertGreaterThan(cardFrame.height, 0)
        XCTAssertLessThanOrEqual(
            cardFrame.width,
            750,
            "Regular Today visualization cards must keep their 748-point readable-width cap."
        )
        XCTAssertGreaterThanOrEqual(cardFrame.minX, windowFrame.minX - 2)
        XCTAssertLessThanOrEqual(cardFrame.maxX, windowFrame.maxX + 2)

        guard let plot else { return }
        XCTAssertTrue(plot.waitForExistence(timeout: 5))
        let plotFrame = plot.frame
        XCTAssertTrue(
            plotFrame.origin.x.isFinite &&
                plotFrame.origin.y.isFinite &&
                plotFrame.width.isFinite &&
                plotFrame.height.isFinite
        )
        XCTAssertGreaterThan(plotFrame.width, 0)
        XCTAssertGreaterThan(plotFrame.height, 0)
        XCTAssertGreaterThanOrEqual(plotFrame.minX, cardFrame.minX - 2)
        XCTAssertLessThanOrEqual(plotFrame.maxX, cardFrame.maxX + 2)
        XCTAssertEqual(
            plotFrame.minX,
            cardFrame.minX + 14,
            accuracy: 2,
            "Visualization plots must align with the card's content edge instead of floating inside wide cards."
        )
    }

    @MainActor
    private func assertHorizontalHomeCardAlignment(
        _ card: XCUIElement,
        nativeReference: XCUIElement,
        in app: XCUIApplication
    ) {
        XCTAssertEqual(
            card.frame.minX,
            nativeReference.frame.minX,
            accuracy: 2,
            "Visualization cards must align with native Today card leading edges."
        )
        XCTAssertEqual(
            card.frame.maxX,
            nativeReference.frame.maxX,
            accuracy: 2,
            "Visualization cards must align with native Today card trailing edges."
        )
        assertSymmetricHorizontalInsets(for: card, in: app)
    }

    @MainActor
    private func assertSymmetricHorizontalInsets(
        for card: XCUIElement,
        in app: XCUIApplication
    ) {
        let viewport = app.windows.firstMatch.frame
        XCTAssertEqual(
            card.frame.minX - viewport.minX,
            viewport.maxX - card.frame.maxX,
            accuracy: 2,
            "Home card horizontal margins must be visually balanced."
        )
    }

    @MainActor
    private func assertSeparateCards(
        _ first: XCUIElement,
        _ second: XCUIElement
    ) {
        XCTAssertTrue(first.exists)
        XCTAssertTrue(second.exists)
        let upperFrame: CGRect
        let lowerFrame: CGRect
        if first.frame.minY <= second.frame.minY {
            upperFrame = first.frame
            lowerFrame = second.frame
        } else {
            upperFrame = second.frame
            lowerFrame = first.frame
        }
        XCTAssertFalse(
            upperFrame.intersects(lowerFrame),
            "Independent visualization cards must not overlap."
        )
        XCTAssertGreaterThanOrEqual(
            lowerFrame.minY - upperFrame.maxY,
            8,
            "Independent visualization cards need visible separation."
        )
    }

    @MainActor
    private func scrollUntilCardBoundaryIsVisible(
        _ first: XCUIElement,
        _ second: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        for _ in 0 ..< 12 {
            if first.exists, second.exists {
                let navigationBar = app.navigationBars.firstMatch
                let visibleTop = navigationBar.exists
                    ? navigationBar.frame.maxY + 8
                    : app.frame.minY + 8
                let visibleBottom = systemChromeTop(in: app) - 8
                let upperFrame = first.frame.minY <= second.frame.minY
                    ? first.frame
                    : second.frame
                let lowerFrame = first.frame.minY <= second.frame.minY
                    ? second.frame
                    : first.frame
                if upperFrame.maxY >= visibleTop + 8,
                   upperFrame.maxY <= visibleBottom - 8,
                   lowerFrame.minY >= visibleTop + 8,
                   lowerFrame.minY <= visibleBottom - 8
                {
                    return true
                }

                let pairMidpoint = (upperFrame.maxY + lowerFrame.minY) / 2
                let viewportMidpoint = (visibleTop + visibleBottom) / 2
                let distance = max(abs(pairMidpoint - viewportMidpoint), 48)
                if pairMidpoint > viewportMidpoint {
                    #if os(macOS)
                    scroll(direction: .up, toward: second, in: app)
                    #else
                    dragContentUp(by: distance, in: app)
                    #endif
                } else {
                    #if os(macOS)
                    scroll(direction: .down, toward: first, in: app)
                    #else
                    dragContentDown(by: distance, in: app)
                    #endif
                }
            } else if first.exists {
                #if os(macOS)
                scroll(direction: .up, toward: second, in: app)
                #else
                dragContentUp(by: 80, in: app)
                #endif
            } else {
                #if os(macOS)
                scroll(direction: .down, toward: first, in: app)
                #else
                dragContentDown(by: 80, in: app)
                #endif
            }
        }
        return false
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
    private func dragContentDown(by distance: CGFloat, in app: XCUIApplication) {
        let normalizedDistance = min(max(distance / app.frame.height, 0.06), 0.25)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        let end = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28 + normalizedDistance)
        )
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func anyStaticText(_ labels: [String], in app: XCUIApplication) -> Bool {
        labels.contains { app.staticTexts[$0].waitForExistence(timeout: 1) }
    }

    @MainActor
    private func hittableButton(
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

    @MainActor
    private func waitForScreenshotTransition() {
        // Search results can become hittable before the platform search-field
        // expansion finishes. This delay stabilizes evidence only; assertions
        // continue to synchronize on semantic UI state.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
}
