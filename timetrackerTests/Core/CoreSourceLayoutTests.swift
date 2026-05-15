import Foundation
import Testing

@Suite(.serialized)
struct CoreSourceLayoutTests {
    @Test
    func sourceLayoutUsesSemanticStoreServiceFeatureAndSharedUIFolders() throws {
        let root = try projectRootURL()
        let expectedFiles = [
            "timetracker/Stores/Facade/TimeTrackerStore.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+ReadModels.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+TaskReadModels.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+LedgerReadModels.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+PomodoroReadModels.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+ChecklistReadModels.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+InboxReadModels.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+InboxSuggestions.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+InboxSuggestionCommands.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+ChecklistVisualSuggestions.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+WidgetSnapshot.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+WatchSnapshot.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+DeepLinks.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+Selection.swift",
            "timetracker/Stores/Domains/AnalyticsStore.swift",
            "timetracker/Stores/Domains/AnalyticsStore+SnapshotBuilding.swift",
            "timetracker/Stores/Domains/AnalyticsStore+Breakdowns.swift",
            "timetracker/Stores/Domains/AnalyticsStore+Overlap.swift",
            "timetracker/Stores/Domains/AnalyticsSnapshotModels.swift",
            "timetracker/Stores/Navigation/StoreSelectionCoordinator.swift",
            "timetracker/Stores/Refresh/StoreRefreshPlanning.swift",
            "timetracker/Services/Instrumentation/PerformanceSignpost.swift",
            "timetracker/Models/SchemaModels.swift",
            "timetracker/Models/SchemaLegacyModels.swift",
            "timetracker/Models/SchemaMigrationPlan.swift",
            "timetracker/Models/TimeTrackerModelRegistry.swift",
            "timetracker/Models/EditorDraftModels.swift",
            "timetracker/Models/AnalyticsReadModels.swift",
            "timetracker/Models/SyncFeedbackModels.swift",
            "timetracker/Services/Analytics/AnalyticsEngine.swift",
            "timetracker/Services/Analytics/TimelineLayoutModels.swift",
            "timetracker/Services/Analytics/TimelineAxisCompression.swift",
            "timetracker/Services/Checklist/ChecklistDraftService.swift",
            "timetracker/Services/Inbox/InboxSuggestionStateService.swift",
            "timetracker/Services/Forecasting/TaskRollupService.swift",
            "timetracker/Services/Forecasting/TaskRollupCalculationContext.swift",
            "timetracker/Services/Ledger/LedgerSummaryService.swift",
            "timetracker/Services/SystemIntegration/WidgetSnapshotCache.swift",
            "timetracker/Services/SystemIntegration/WatchCommandProcessor.swift",
            "timetracker/Services/SystemIntegration/WatchConnectivityBridge.swift",
            "timetracker/Services/SystemIntegration/WatchConnectivityPayloadCodec.swift",
            "timetracker/Services/Tasks/TaskTreeServices.swift",
            "timetracker/Shared/WatchCommandModels.swift",
            "timetracker/Shared/WatchStateSnapshotModels.swift",
            "timetracker/Repositories/SwiftDataTaskRepository.swift",
            "timetracker/Repositories/SwiftDataTaskRepository+Queries.swift",
            "timetracker/Repositories/SwiftDataTaskRepository+Categories.swift",
            "timetracker/Repositories/SwiftDataTaskRepository+TaskMutations.swift",
            "timetracker/Repositories/SwiftDataTaskRepository+Hierarchy.swift",
            "timetracker/Repositories/SwiftDataTimeTrackingRepository.swift",
            "timetracker/Repositories/SwiftDataTimeTrackingRepository+Queries.swift",
            "timetracker/Repositories/SwiftDataTimeTrackingRepository+Mutations.swift",
            "timetracker/SharedUI/Foundation/LayoutPolicies.swift",
            "timetracker/SharedUI/Foundation/ColorSupport.swift",
            "timetracker/SharedUI/Components/ChecklistControls.swift",
            "timetracker/SharedUI/Components/DurationLabels.swift",
            "timetracker/SharedUI/Components/EmptyStates.swift",
            "timetracker/SharedUI/Components/ForecastInfoViews.swift",
            "timetracker/SharedUI/Components/StatusBadges.swift",
            "timetracker/SharedUI/Components/TaskVisuals.swift",
            "timetracker/SharedUI/Components/TaskProgressViews.swift",
            "timetracker/SharedUI/Components/SectionHeaders.swift",
            "timetracker/SharedUI/Components/ActionControls.swift",
            "timetracker/SharedUI/Components/SettingsRows.swift",
            "timetracker/SharedUI/Components/SelectionPulse.swift",
            "timetracker/SharedUI/Components/SplitViewToolbarButtons.swift",
            "timetracker/Features/Home/Controls/HomeActionsViews.swift",
            "timetracker/Features/Home/Sections/HomeMetricsViews.swift",
            "timetracker/Features/Home/Rows/HomeTimerRows.swift",
            "timetracker/App/AppModelContainerFactory.swift",
            "timetracker/App/AppDemoDataConfiguration.swift",
            "timetracker/App/SettingsSceneView.swift",
            "timetracker/App/TimeTrackerCommands.swift",
            "timetracker/App/TimeTrackerAppDelegate.swift",
            "timetracker/App/AppDeepLinkRouter.swift",
            "timetracker/App/RootViews/DesktopRootViews.swift",
            "timetracker/App/RootViews/iOSRootViews.swift",
            "timetracker/AppIntents/TimeTrackerAppIntents.swift",
            "timetrackerWidgetExtension/TimeTrackerWidget.swift",
            "timetrackerWidgetExtension/Info.plist",
            "timetrackerWatchApp/TimeTrackerWatchApp.swift",
            "timetrackerWatchApp/WatchDashboardView.swift",
            "timetrackerWatchApp/WatchAppStore.swift",
            "timetracker/Features/Inbox/InboxViews.swift",
            "timetracker/Features/Inbox/InboxListView.swift",
            "timetracker/Features/Inbox/InboxCaptureRow.swift",
            "timetracker/Features/Inbox/InboxItemRow.swift",
            "timetracker/Features/Inbox/InboxSuggestionRow.swift",
            "timetracker/Features/Tasks/Editor/TaskEditorViews.swift",
            "timetracker/Features/Tasks/Editor/TaskEditorInfoSection.swift",
            "timetracker/Features/Tasks/Editor/TaskStatusPicker.swift",
            "timetracker/Features/Tasks/Editor/TaskPlanEditorSection.swift",
            "timetracker/Features/Tasks/Editor/TaskNotesEditorSection.swift",
            "timetracker/Features/Tasks/Editor/TaskChecklistEditorSection.swift",
            "timetracker/Features/Tasks/Editor/ChecklistEditorRow.swift",
            "timetracker/Features/Tasks/Management/TasksViews.swift",
            "timetracker/Features/Settings/SettingsSectionsViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsOverviewViews.swift",
            "timetracker/Features/Analytics/Timeline/AnalyticsTimelineViews.swift",
            "timetracker/Features/Analytics/Timeline/AnalyticsTimelineGridViews.swift",
            "timetracker/Features/Analytics/Timeline/AnalyticsTimelineRows.swift",
            "timetracker/Features/Inspector/Sections/InspectorInfoViews.swift"
        ]

        for relativePath in expectedFiles {
            #expect(FileManager.default.fileExists(atPath: root.appending(path: relativePath).path))
        }

        let flatStoreExtensions = try FileManager.default.contentsOfDirectory(
            atPath: root.appending(path: "timetracker/Stores").path
        )
        .filter { $0.hasPrefix("TimeTrackerStore+") }

        #expect(flatStoreExtensions.isEmpty)

        #expect(FileManager.default.fileExists(
            atPath: root.appending(path: "timetracker/SharedUI/Components/SharedUI.swift").path
        ) == false)
    }

    @Test
    func facadeFilesStayBelowRefactorSizeBudget() throws {
        let root = try projectRootURL()
        let facadeURL = root.appending(path: "timetracker/Stores/Facade")
        let files = try FileManager.default.contentsOfDirectory(at: facadeURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        for file in files {
            let lineCount = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
            #expect(lineCount <= 250, "\(file.lastPathComponent) has \(lineCount) lines")
        }
    }

    @Test
    func taskEditorFilesStaySplitBySection() throws {
        let root = try projectRootURL()
        let editorURL = root.appending(path: "timetracker/Features/Tasks/Editor")
        let focusedFiles = [
            "TaskEditorComponents.swift",
            "TaskEditorInfoSection.swift",
            "TaskStatusPicker.swift",
            "TaskPlanEditorSection.swift",
            "TaskNotesEditorSection.swift",
            "TaskChecklistEditorSection.swift",
            "ChecklistEditorRow.swift"
        ]

        for fileName in focusedFiles {
            let file = editorURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
            #expect(lineCount <= 180, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func analyticsStoreFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let domainURL = root.appending(path: "timetracker/Stores/Domains")
        let focusedFiles = [
            "AnalyticsStore.swift",
            "AnalyticsSnapshotModels.swift",
            "AnalyticsStore+SnapshotBuilding.swift",
            "AnalyticsStore+Breakdowns.swift",
            "AnalyticsStore+Overlap.swift"
        ]

        for fileName in focusedFiles {
            let file = domainURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
            #expect(lineCount <= 220, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func analyticsServiceFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let analyticsURL = root.appending(path: "timetracker/Services/Analytics")
        let focusedFiles = [
            "TimelineLayoutEngine.swift",
            "TimelineLayoutModels.swift",
            "TimelineAxisCompression.swift",
            "HourStackLayoutEngine.swift",
            "HourTaskActivityService.swift",
            "AnalyticsTimelineSnapshotService.swift",
            "LedgerBucketCache.swift"
        ]

        for fileName in focusedFiles {
            let file = analyticsURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
            #expect(lineCount <= 180, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func taskRepositoryFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let repositoryURL = root.appending(path: "timetracker/Repositories")
        let focusedFiles = [
            "SwiftDataTaskRepository.swift",
            "SwiftDataTaskRepository+Queries.swift",
            "SwiftDataTaskRepository+Categories.swift",
            "SwiftDataTaskRepository+TaskMutations.swift",
            "SwiftDataTaskRepository+Hierarchy.swift"
        ]

        for fileName in focusedFiles {
            let file = repositoryURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
            #expect(lineCount <= 180, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func ledgerRepositoryFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let repositoryURL = root.appending(path: "timetracker/Repositories")
        let focusedFiles = [
            "SwiftDataTimeTrackingRepository.swift",
            "SwiftDataTimeTrackingRepository+Queries.swift",
            "SwiftDataTimeTrackingRepository+Mutations.swift"
        ]

        for fileName in focusedFiles {
            let file = repositoryURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
            #expect(lineCount <= 180, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func forecastFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let forecastingURL = root.appending(path: "timetracker/Services/Forecasting")
        let focusedFiles = [
            "TaskRollupService.swift",
            "TaskRollupCalculationContext.swift",
            "TaskRollupForecastHelpers.swift",
            "ForecastDisplayService.swift"
        ]

        for fileName in focusedFiles {
            let file = forecastingURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
            #expect(lineCount <= 230, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func schemaAndReadModelFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let modelsURL = root.appending(path: "timetracker/Models")
        let focusedFiles = [
            "SchemaModels.swift",
            "SchemaLegacyModels.swift",
            "SchemaMigrationPlan.swift",
            "TimeTrackerModelRegistry.swift",
            "EditorDraftModels.swift",
            "AnalyticsReadModels.swift",
            "SyncFeedbackModels.swift"
        ]

        for fileName in focusedFiles {
            let file = modelsURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
            #expect(lineCount <= 260, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func appRootFilesStaySplitByPlatformResponsibility() throws {
        let root = try projectRootURL()
        let appURL = root.appending(path: "timetracker/App")
        let focusedFiles = [
            "timetrackerApp.swift",
            "AppModelContainerFactory.swift",
            "SettingsSceneView.swift",
            "TimeTrackerCommands.swift",
            "TimeTrackerAppDelegate.swift",
            "ContentView.swift",
            "RootViews/DesktopRootViews.swift",
            "RootViews/iOSRootViews.swift"
        ]

        for fileName in focusedFiles {
            let file = appURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
            #expect(lineCount <= 160, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func analyticsTimelineFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let timelineURL = root.appending(path: "timetracker/Features/Analytics/Timeline")
        let focusedFiles = [
            "AnalyticsTimelineViews.swift",
            "AnalyticsTimelineGridViews.swift",
            "AnalyticsTimelineRows.swift",
            "AnalyticsTimelineSupportViews.swift"
        ]

        for fileName in focusedFiles {
            let file = timelineURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
            #expect(lineCount <= 180, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func performanceSignpostsCoverRefreshAnalyticsRollupAndTimelineBoundaries() throws {
        let lifecycle = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+Lifecycle.swift")
        let coordinator = try sourceText("timetracker/Stores/Refresh/StoreRefreshCoordinator.swift")
        let analytics = try [
            "timetracker/Stores/Domains/AnalyticsStore.swift",
            "timetracker/Stores/Domains/AnalyticsStore+SnapshotBuilding.swift",
            "timetracker/Stores/Domains/AnalyticsStore+Breakdowns.swift",
            "timetracker/Stores/Domains/AnalyticsStore+Overlap.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
        let rollup = try sourceText("timetracker/Stores/Domains/RollupStore.swift")
        let timeline = try sourceText("timetracker/Services/Analytics/TimelineLayoutEngine.swift")
        let signpost = try sourceText("timetracker/Services/Instrumentation/PerformanceSignpost.swift")

        #expect(signpost.contains("OSSignposter"))
        #expect(lifecycle.contains("Store refresh planning"))
        #expect(coordinator.contains("Store refresh"))
        #expect(coordinator.contains("Ledger domain refresh"))
        #expect(analytics.contains("Analytics snapshot generation"))
        #expect(rollup.contains("Rollup service calculation"))
        #expect(timeline.contains("Timeline layout"))
    }

    @Test
    func selectionLogicIsIsolatedFromReadModels() throws {
        let readModels = try [
            "timetracker/Stores/Facade/TimeTrackerStore+ReadModels.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+TaskReadModels.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+LedgerReadModels.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+PomodoroReadModels.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+ChecklistReadModels.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+InboxReadModels.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+InboxSuggestions.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
        let selection = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+Selection.swift")
        let coordinator = try sourceText("timetracker/Stores/Navigation/StoreSelectionCoordinator.swift")
        let timerCommands = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+TimerCommands.swift")

        #expect(readModels.contains("var selectedTask: TaskNode?") == false)
        #expect(readModels.contains("func selectTask(") == false)
        #expect(readModels.contains("func ancestorTaskIDs") == false)
        #expect(readModels.contains("func affectedAncestorIDs") == false)
        #expect(selection.contains("var selectedTask: TaskNode?"))
        #expect(selection.contains("func selectTask(_ taskID: UUID"))
        #expect(selection.contains("selectionCoordinator"))
        #expect(coordinator.contains("struct StoreSelectionCoordinator"))
        #expect(timerCommands.contains("func selectTask(") == false)
    }

    @Test
    func commandErrorsUseTypedFacadeFailures() throws {
        let lifecycle = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+Lifecycle.swift")
        let ledger = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+LedgerCommands.swift")
        let pomodoro = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+PomodoroCommands.swift")
        let inbox = try [
            "timetracker/Stores/Facade/TimeTrackerStore+InboxCommands.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+InboxSuggestionCommands.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
        let taskCategories = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+TaskCategoryCommands.swift")

        #expect(lifecycle.contains("func fail(_ error: StoreError) -> Bool"))
        #expect(lifecycle.contains("case taskSelectionRequired"))
        #expect(lifecycle.contains("case pomodoroTaskSelectionRequired"))
        #expect(lifecycle.contains("case invalidTimeRange"))
        #expect(ledger.contains("fail(.taskSelectionRequired)"))
        #expect(ledger.contains("fail(.invalidTimeRange)"))
        #expect(pomodoro.contains("fail(.pomodoroTaskSelectionRequired)"))
        #expect(inbox.contains("fail(.invalidInboxSuggestion)"))
        #expect(taskCategories.contains("fail(.taskCategoryNameRequired)"))
        #expect(ledger.contains("errorMessage = AppStrings.localized(\"task.selectRequired\")") == false)
        #expect(ledger.contains("errorMessage = AppStrings.localized(\"time.endAfterStart\")") == false)
    }

    @Test
    func projectMapDocumentsPrimaryFoldersAndEntryPoints() throws {
        let map = try sourceText("Docs/ProjectMap.md")
        let requiredFolders = [
            "`timetracker/App`",
            "`timetracker/AppIntents`",
            "`timetrackerWidgetExtension`",
            "`timetrackerWatchApp`",
            "`timetracker/Models`",
            "`timetracker/Repositories`",
            "`timetracker/Commands`",
            "`timetracker/Stores/Facade`",
            "`timetracker/Stores/Domains`",
            "`timetracker/Stores/Refresh`",
            "`timetracker/Services/Analytics`",
            "`timetracker/Services/Checklist`",
            "`timetracker/Services/Inbox`",
            "`timetracker/Services/Forecasting`",
            "`timetracker/Services/SystemIntegration`",
            "`timetracker/Services/Tasks`",
            "`timetracker/Features/Home`",
            "`timetracker/Features/Tasks`",
            "`timetracker/Features/Analytics`",
            "`timetracker/Features/Settings`",
            "`timetracker/SharedUI/Foundation`",
            "`timetracker/SharedUI/Components`"
        ]

        for folder in requiredFolders {
            #expect(map.contains(folder))
        }

        let requiredEntryPoints = [
            "Start/pause/resume/stop timer behavior",
            "Task create/edit/move/delete",
            "Checklist UI or persistence",
            "Forecast math",
            "Analytics chart data",
            "Today layout",
            "Settings",
            "iCloud/user settings sync",
            "Siri/Shortcuts App Intents",
            "Deep links from Widget or system surfaces",
            "Widget extension UI",
            "Watch app UI",
            "Live Activity display",
            "Localization"
        ]

        for entryPoint in requiredEntryPoints {
            #expect(map.contains(entryPoint))
        }
    }
}
