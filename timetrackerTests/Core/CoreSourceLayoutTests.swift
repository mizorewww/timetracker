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
            "timetracker/Stores/Domains/AnalyticsStore+Caching.swift",
            "timetracker/Stores/Domains/AnalyticsStore+SnapshotBuilding.swift",
            "timetracker/Stores/Domains/AnalyticsStore+Breakdowns.swift",
            "timetracker/Stores/Domains/AnalyticsStore+DecisionSupport.swift",
            "timetracker/Stores/Domains/AnalyticsStore+GroupBreakdowns.swift",
            "timetracker/Stores/Domains/AnalyticsStore+Metrics.swift",
            "timetracker/Stores/Domains/AnalyticsStore+Overlap.swift",
            "timetracker/Stores/Domains/AnalyticsStore+OverlapMaterialization.swift",
            "timetracker/Stores/Domains/AnalyticsStore+OverlapParticipants.swift",
            "timetracker/Stores/Domains/AnalyticsStore+OverlapSweep.swift",
            "timetracker/Stores/Domains/AnalyticsStore+TaskBreakdown.swift",
            "timetracker/Stores/Domains/AnalyticsStore+TaskSnapshot.swift",
            "timetracker/Stores/Domains/AnalyticsSnapshotModels.swift",
            "timetracker/Stores/Domains/ChecklistStore.swift",
            "timetracker/Stores/Domains/ChecklistStore+ArrayIndexes.swift",
            "timetracker/Stores/Domains/LedgerStore.swift",
            "timetracker/Stores/Domains/LedgerStore+FlatSegmentIndex.swift",
            "timetracker/Stores/Domains/LedgerStore+SegmentIndex.swift",
            "timetracker/Stores/Domains/LedgerStore+SegmentQueryIndex.swift",
            "timetracker/Stores/Domains/LedgerStore+Queries.swift",
            "timetracker/Stores/Domains/LedgerStore+RecordIndexes.swift",
            "timetracker/Stores/Domains/LedgerRollupIndex.swift",
            "timetracker/Stores/Domains/LedgerSessionIndex.swift",
            "timetracker/Stores/Domains/RollupIncrementalIndex.swift",
            "timetracker/Stores/Domains/RollupIncrementalIndex+Mutation.swift",
            "timetracker/Stores/Domains/RollupIncrementalIndex+Pace.swift",
            "timetracker/Stores/Domains/RollupIncrementalIndex+Topology.swift",
            "timetracker/Stores/Navigation/StoreSelectionCoordinator.swift",
            "timetracker/Stores/Refresh/StoreRefreshPlanning.swift",
            "timetracker/Services/Instrumentation/PerformanceSignpost.swift",
            "timetracker/Models/SchemaModels.swift",
            "timetracker/Models/SchemaLegacyModels.swift",
            "timetracker/Models/SchemaMigrationPlan.swift",
            "timetracker/Models/TimeTrackerModelRegistry.swift",
            "timetracker/Models/TaskEstimatePolicy.swift",
            "timetracker/Models/EditorDraftModels.swift",
            "timetracker/Models/TaskCategoryEditorDraftModels.swift",
            "timetracker/Models/AnalyticsPeriodModels.swift",
            "timetracker/Models/AnalyticsSummaryReadModels.swift",
            "timetracker/Models/AnalyticsTimelineReadModels.swift",
            "timetracker/Models/TaskAnalyticsReadModels.swift",
            "timetracker/Models/AnalyticsOverlapReadModels.swift",
            "timetracker/Models/PomodoroPreferenceModels.swift",
            "timetracker/Models/SyncFeedbackModels.swift",
            "timetracker/Services/Analytics/AnalyticsEngine.swift",
            "timetracker/Services/Analytics/AnalyticsSelectionPolicy.swift",
            "timetracker/Services/Analytics/TimelineLayoutModels.swift",
            "timetracker/Services/Analytics/TimelineAxisCompression.swift",
            "timetracker/Services/Checklist/ChecklistDraftService.swift",
            "timetracker/Services/Checklist/StoreScopedChecklistCommandCoordinator.swift",
            "timetracker/Services/Inbox/InboxSuggestionIdentityService.swift",
            "timetracker/Services/Inbox/InboxSuggestionStateService.swift",
            "timetracker/Services/Inbox/StoreScopedInboxCommandCoordinator.swift",
            "timetracker/Services/Forecasting/TaskRollupService.swift",
            "timetracker/Services/Forecasting/TaskRollupCalculationContext.swift",
            "timetracker/Services/Ledger/AppCloudSync.swift",
            "timetracker/Services/Ledger/PersistenceWriteSafety.swift",
            "timetracker/Services/Ledger/TimerCommand.swift",
            "timetracker/Services/Ledger/TimeAggregationService.swift",
            "timetracker/Services/Ledger/TimeFormatters.swift",
            "timetracker/Services/Ledger/DeviceIdentity.swift",
            "timetracker/Services/Ledger/LedgerSummaryService.swift",
            "timetracker/Services/SystemIntegration/SyncConflictService.swift",
            "timetracker/Services/SystemIntegration/SyncConflictService+CloudExport.swift",
            "timetracker/Services/SystemIntegration/SyncConflictService+CloudImport.swift",
            "timetracker/Services/SystemIntegration/SyncConflictService+Export.swift",
            "timetracker/Services/SystemIntegration/SyncConflictService+LocalMutation.swift",
            "timetracker/Services/SystemIntegration/SyncConflictService+Recovery.swift",
            "timetracker/Services/SystemIntegration/SyncConflictService+Resolution.swift",
            "timetracker/Services/SystemIntegration/SyncConflictService+State.swift",
            "timetracker/Services/SystemIntegration/SyncConflictService+StateLock.swift",
            "timetracker/Services/SystemIntegration/SyncConflictService+StateLocations.swift",
            "timetracker/Services/SystemIntegration/SyncConflictService+StoreTransaction.swift",
            "timetracker/Services/SystemIntegration/SyncConflictState.swift",
            "timetracker/Services/SystemIntegration/SyncDataSnapshot.swift",
            "timetracker/Services/SystemIntegration/SyncDataSnapshot+Capture.swift",
            "timetracker/Services/SystemIntegration/SyncDataSnapshot+Preflight.swift",
            "timetracker/Services/SystemIntegration/SyncDataSnapshot+PreflightContent.swift",
            "timetracker/Services/SystemIntegration/SyncDataSnapshot+PreflightSemantics.swift",
            "timetracker/Services/SystemIntegration/SyncDataSnapshot+Restore.swift",
            "timetracker/Services/SystemIntegration/SyncDataSnapshot+RestoreChecklist.swift",
            "timetracker/Services/SystemIntegration/SyncDataSnapshot+RestoreInbox.swift",
            "timetracker/Services/SystemIntegration/SyncDataSnapshot+RestoreLedger.swift",
            "timetracker/Services/SystemIntegration/SyncDataSnapshot+RestorePlanning.swift",
            "timetracker/Services/SystemIntegration/SyncDataSnapshot+RestoreTasks.swift",
            "timetracker/Services/SystemIntegration/SyncSnapshotRecords.swift",
            "timetracker/Services/SystemIntegration/SyncSnapshotChecklistRecords.swift",
            "timetracker/Services/SystemIntegration/SyncSnapshotInboxRecords.swift",
            "timetracker/Services/SystemIntegration/SyncSnapshotLedgerRecords.swift",
            "timetracker/Services/SystemIntegration/SyncSnapshotPlanningRecords.swift",
            "timetracker/Services/SystemIntegration/WidgetSnapshotCache.swift",
            "timetracker/Services/SystemIntegration/WatchCommandProcessor.swift",
            "timetracker/Services/SystemIntegration/WatchConnectivityBridge.swift",
            "timetracker/Services/SystemIntegration/WatchConnectivityPayloadCodec.swift",
            "timetracker/Services/SystemIntegration/WatchIncomingCommandStore.swift",
            "timetracker/Services/Tasks/TaskTrackingAvailabilityService.swift",
            "timetracker/Services/Tasks/StoreScopedTaskCategoryCommandCoordinator.swift",
            "timetracker/Services/Tasks/TaskHierarchyRepairPlan.swift",
            "timetracker/Services/Tasks/TaskTreeFlattener.swift",
            "timetracker/Services/Tasks/TaskTreeModels.swift",
            "timetracker/Services/Tasks/TaskTreeProjectionCache.swift",
            "timetracker/Services/Tasks/TaskTreeReadIndex.swift",
            "timetracker/Services/Tasks/TaskTreeService.swift",
            "timetracker/Services/Tasks/TaskTreeService+ReadIndex.swift",
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
            "timetracker/SharedUI/Components/SettingsPresentationModifiers.swift",
            "timetracker/SharedUI/Components/SettingsInputRows.swift",
            "timetracker/SharedUI/Components/SettingsActionRows.swift",
            "timetracker/SharedUI/Components/SettingsSyncFeedbackRow.swift",
            "timetracker/SharedUI/Components/SelectionPulse.swift",
            "timetracker/SharedUI/Components/InfoRows.swift",
            "timetracker/SharedUI/Components/SplitViewToolbarButtons.swift",
            "timetracker/Features/Home/Controls/HomeActionsViews.swift",
            "timetracker/Features/Home/Controls/TaskStartPickerEmptyState.swift",
            "timetracker/Features/Home/HomeViews.swift",
            "timetracker/Features/Home/PhoneHomeView.swift",
            "timetracker/Features/Home/PhoneHomeRows.swift",
            "timetracker/Features/Home/Sections/HomeMetricsViews.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartViews.swift",
            "timetracker/Features/Home/Rows/HomeTimerRows.swift",
            "timetracker/App/AppModelContainerFactory.swift",
            "timetracker/App/AppModelContainerFactory+Testing.swift",
            "timetracker/App/AppModelContainerFactory+Fallback.swift",
            "timetracker/App/AppDemoDataConfiguration.swift",
            "timetracker/App/SettingsSceneView.swift",
            "timetracker/App/TimeTrackerCommands.swift",
            "timetracker/App/TimeTrackerAppDelegate.swift",
            "timetracker/App/AppDeepLinkRouter.swift",
            "timetracker/App/WatchCommandRouter.swift",
            "timetracker/App/RootViews/DesktopRootViews.swift",
            "timetracker/App/RootViews/iOSRootViews.swift",
            "timetracker/AppIntents/TimeTrackerAppIntents.swift",
            "timetrackerWidgetExtension/TimeTrackerWidget.swift",
            "timetrackerWidgetExtension/ActiveTimerWidgetView.swift",
            "timetrackerWidgetExtension/WidgetSupplementaryViews.swift",
            "timetrackerWidgetExtension/WidgetSupport.swift",
            "timetrackerWidgetExtension/Info.plist",
            "timetrackerWatchApp/TimeTrackerWatchApp.swift",
            "timetrackerWatchApp/WatchDashboardView.swift",
            "timetrackerWatchApp/WatchTimerRows.swift",
            "timetrackerWatchApp/WatchStatusViews.swift",
            "timetrackerWatchApp/WatchColorSupport.swift",
            "timetrackerWatchApp/WatchAppStore.swift",
            "timetrackerWatchApp/WatchAppStore+Commands.swift",
            "timetrackerWatchApp/WatchAppStore+Connectivity.swift",
            "timetracker/Features/Inbox/InboxViews.swift",
            "timetracker/Features/Inbox/InboxListView.swift",
            "timetracker/Features/Inbox/InboxCaptureRow.swift",
            "timetracker/Features/Inbox/InboxItemRow.swift",
            "timetracker/Features/Inbox/InboxSuggestionRow.swift",
            "timetracker/Features/Tasks/Editor/TaskEditorViews.swift",
            "timetracker/Features/Tasks/Editor/TaskEditorInfoSection.swift",
            "timetracker/Features/Tasks/Editor/TaskEditorHierarchyRows.swift",
            "timetracker/Features/Tasks/Editor/TaskStatusPicker.swift",
            "timetracker/Features/Tasks/Editor/TaskPlanEditorSection.swift",
            "timetracker/Features/Tasks/Editor/TaskNotesEditorSection.swift",
            "timetracker/Features/Tasks/Editor/TaskChecklistEditorSection.swift",
            "timetracker/Features/Tasks/Editor/ChecklistEditorRow.swift",
            "timetracker/Features/Tasks/Editor/SymbolPickerViews.swift",
            "timetracker/Features/Tasks/Editor/SymbolColorPickerRow.swift",
            "timetracker/Features/Tasks/Editor/SymbolCatalog.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailView.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailActionsView.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailNavigationViews.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailIdentityViews.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailChecklistViews.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailOverviewViews.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailAnalyticsViews.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailRecordViews.swift",
            "timetracker/Features/Tasks/Management/TasksViews.swift",
            "timetracker/Features/Tasks/Management/TaskManagementRowViews.swift",
            "timetracker/Features/Tasks/Management/TaskManagementRowContent.swift",
            "timetracker/Features/Tasks/Management/TaskManagementAccessibility.swift",
            "timetracker/Features/Settings/SettingsViews.swift",
            "timetracker/Features/Settings/SettingsCategorySections.swift",
            "timetracker/Features/Settings/SettingsCategoryViews.swift",
            "timetracker/Features/Settings/LLMSettingsViews.swift",
            "timetracker/Features/Settings/LLMSettingsSection.swift",
            "timetracker/Features/Settings/DisplayTimingSettingsSection.swift",
            "timetracker/Features/Settings/PomodoroSettingsSection.swift",
            "timetracker/Features/Settings/PomodoroPickerViews.swift",
            "timetracker/Features/Settings/CountdownSettingsSection.swift",
            "timetracker/Features/Settings/SyncSettingsSection.swift",
            "timetracker/Features/Settings/SyncRecoverySettingsSection.swift",
            "timetracker/Features/Sidebar/SidebarViews.swift",
            "timetracker/Features/Sidebar/SidebarDestinationViews.swift",
            "timetracker/Features/Sidebar/SidebarTaskTreeViews.swift",
            "timetracker/Features/Pomodoro/PomodoroViews.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroActiveCountdownView.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroActiveViews.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroCountdownSchedule.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroFocusSetupControls.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroLedgerViews.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroPageLayout.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupEmptyState.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupSelectionViews.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupViews.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroTimerFace.swift",
            "timetracker/Features/Analytics/AnalyticsViews.swift",
            "timetracker/Features/Analytics/AnalyticsHomeContent.swift",
            "timetracker/Features/Analytics/AnalyticsCategoryDetailView.swift",
            "timetracker/Features/Analytics/AnalyticsCategory.swift",
            "timetracker/Features/Analytics/AnalyticsOverviewRows.swift",
            "timetracker/Features/Analytics/AnalyticsMetricListViews.swift",
            "timetracker/Features/Analytics/AnalyticsDetailListViews.swift",
            "timetracker/Features/Analytics/AnalyticsPeriodSection.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsActivityViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsActivityBarViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsDistributionSlice.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsDistributionViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsForecastViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsGroupBarLayout.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsGroupBreakdownPresentation.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsGroupBreakdownViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsOverlapViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsOverlapRow.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsQualityViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsTrendViews.swift",
            "timetracker/Features/Analytics/Timeline/AnalyticsTimelineViews.swift",
            "timetracker/Features/Analytics/Timeline/AnalyticsTimelineGridViews.swift",
            "timetracker/Features/Analytics/Timeline/AnalyticsTimelineRows.swift",
            "timetrackerLiveActivityExtension/TimeTrackerLiveActivityBundle.swift",
            "timetrackerLiveActivityExtension/LiveActivityTimerViews.swift",
            "timetrackerLiveActivityExtension/ExpandedActivityDetails.swift",
            "timetrackerLiveActivityExtension/LiveActivitySupport.swift"
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

        let retiredViews = [
            "timetracker/Features/Home/Sections/HomeSelectedTaskSummaryViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsDecisionViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsOverviewViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsRowsViews.swift",
            "timetracker/Features/Tasks/Detail/TaskForecastPanel.swift",
            "timetracker/Features/Settings/SettingsSectionsViews.swift",
            "timetracker/Services/Ledger/TimeTrackerServices.swift",
            "timetracker/Services/Tasks/TaskTreeServices.swift"
        ]
        for relativePath in retiredViews {
            #expect(FileManager.default.fileExists(atPath: root.appending(path: relativePath).path) == false)
        }
    }

    @Test
    func customMigrationBufferUsesSynchronizedOneShotStorage() throws {
        let source = try sourceText("timetracker/Models/SchemaMigrationPlan.swift")

        #expect(source.contains("OSAllocatedUnfairLock"))
        #expect(source.contains("LegacyTaskCategoryMigrationBuffer.consume()"))
        #expect(source.contains("nonisolated(unsafe)") == false)
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
            "TaskEditorHierarchyRows.swift",
            "TaskStatusPicker.swift",
            "TaskPlanEditorSection.swift",
            "TaskNotesEditorSection.swift",
            "TaskChecklistEditorSection.swift",
            "ChecklistEditorRow.swift",
            "SymbolPickerViews.swift",
            "SymbolColorPickerRow.swift",
            "SymbolCatalog.swift"
        ]

        for fileName in focusedFiles {
            let file = editorURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            let limit = fileName == "SymbolPickerViews.swift" ? 230 : 180
            #expect(lineCount <= limit, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func taskDetailFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let detailURL = root.appending(path: "timetracker/Features/Tasks/Detail")
        let focusedFiles = [
            "TaskDetailView.swift",
            "TaskDetailActionsView.swift",
            "TaskDetailNavigationViews.swift",
            "TaskDetailIdentityViews.swift",
            "TaskDetailChecklistViews.swift",
            "TaskDetailOverviewViews.swift",
            "TaskDetailAnalyticsViews.swift",
            "TaskDetailRecordViews.swift"
        ]

        for fileName in focusedFiles {
            let file = detailURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 180, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func settingsSectionFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let settingsURL = root.appending(path: "timetracker/Features/Settings")
        let focusedFiles = [
            "DisplayTimingSettingsSection.swift",
            "PomodoroSettingsSection.swift",
            "PomodoroPickerViews.swift",
            "CountdownSettingsSection.swift",
            "SyncSettingsSection.swift",
            "SyncRecoverySettingsSection.swift"
        ]

        for fileName in focusedFiles {
            let file = settingsURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 180, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func settingsSharedComponentFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let componentsURL = root.appending(path: "timetracker/SharedUI/Components")
        let focusedFiles = [
            "SettingsRows.swift",
            "SettingsPresentationModifiers.swift",
            "SettingsInputRows.swift",
            "SettingsActionRows.swift",
            "SettingsSyncFeedbackRow.swift"
        ]

        for fileName in focusedFiles {
            let file = componentsURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 180, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func pomodoroFeatureFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let pomodoroURL = root.appending(path: "timetracker/Features/Pomodoro")
        let focusedFiles = [
            "PomodoroViews.swift",
            "Sections/PomodoroActiveCountdownView.swift",
            "Sections/PomodoroActiveViews.swift",
            "Sections/PomodoroCountdownSchedule.swift",
            "Sections/PomodoroFocusSetupControls.swift",
            "Sections/PomodoroLedgerViews.swift",
            "Sections/PomodoroPageLayout.swift",
            "Sections/PomodoroSetupEmptyState.swift",
            "Sections/PomodoroSetupSelectionViews.swift",
            "Sections/PomodoroSetupViews.swift",
            "Sections/PomodoroTimerFace.swift"
        ]

        for fileName in focusedFiles {
            let file = pomodoroURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 180, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func companionPlatformUIFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let focusedFiles = [
            "timetrackerWidgetExtension/TimeTrackerWidget.swift",
            "timetrackerWidgetExtension/ActiveTimerWidgetView.swift",
            "timetrackerWidgetExtension/WidgetSupplementaryViews.swift",
            "timetrackerWidgetExtension/WidgetSupport.swift",
            "timetrackerWatchApp/WatchDashboardView.swift",
            "timetrackerWatchApp/WatchTimerRows.swift",
            "timetrackerWatchApp/WatchStatusViews.swift",
            "timetrackerWatchApp/WatchColorSupport.swift",
            "timetrackerLiveActivityExtension/TimeTrackerLiveActivityBundle.swift",
            "timetrackerLiveActivityExtension/LiveActivityTimerViews.swift",
            "timetrackerLiveActivityExtension/ExpandedActivityDetails.swift",
            "timetrackerLiveActivityExtension/LiveActivitySupport.swift"
        ]

        for relativePath in focusedFiles {
            let file = root.appending(path: relativePath)
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 230, "\(file.lastPathComponent) has \(lineCount) lines")
        }
    }

    @Test
    func primaryUICompositionFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let focusedFiles = [
            "timetracker/Features/Home/HomeViews.swift",
            "timetracker/Features/Home/PhoneHomeView.swift",
            "timetracker/Features/Home/PhoneHomeRows.swift",
            "timetracker/Features/Tasks/Management/TaskManagementRowViews.swift",
            "timetracker/Features/Tasks/Management/TaskManagementRowContent.swift",
            "timetracker/Features/Tasks/Management/TaskManagementAccessibility.swift",
            "timetracker/Features/Settings/SettingsViews.swift",
            "timetracker/Features/Settings/SettingsCategorySections.swift",
            "timetracker/Features/Settings/SettingsCategoryViews.swift",
            "timetracker/Features/Settings/LLMSettingsViews.swift",
            "timetracker/Features/Settings/LLMSettingsSection.swift",
            "timetracker/Features/Sidebar/SidebarViews.swift",
            "timetracker/Features/Sidebar/SidebarDestinationViews.swift",
            "timetracker/Features/Sidebar/SidebarTaskTreeViews.swift"
        ]

        for relativePath in focusedFiles {
            let file = root.appending(path: relativePath)
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 230, "\(file.lastPathComponent) has \(lineCount) lines")
        }
    }

    @Test
    func analyticsStoreFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let domainURL = root.appending(path: "timetracker/Stores/Domains")
        let focusedFiles = [
            "AnalyticsStore.swift",
            "AnalyticsStore+Caching.swift",
            "AnalyticsSnapshotModels.swift",
            "AnalyticsStore+SnapshotBuilding.swift",
            "AnalyticsStore+Breakdowns.swift",
            "AnalyticsStore+DecisionSupport.swift",
            "AnalyticsStore+GroupBreakdowns.swift",
            "AnalyticsStore+Metrics.swift",
            "AnalyticsStore+Overlap.swift",
            "AnalyticsStore+OverlapMaterialization.swift",
            "AnalyticsStore+OverlapParticipants.swift",
            "AnalyticsStore+OverlapSweep.swift",
            "AnalyticsStore+TaskBreakdown.swift",
            "AnalyticsStore+TaskSnapshot.swift"
        ]

        for fileName in focusedFiles {
            let file = domainURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
            #expect(lineCount <= 220, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func checklistAndLedgerMutationIndexesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let domainURL = root.appending(path: "timetracker/Stores/Domains")
        let focusedFiles = [
            "ChecklistStore.swift",
            "ChecklistStore+ArrayIndexes.swift",
            "LedgerStore.swift",
            "LedgerStore+FlatSegmentIndex.swift",
            "LedgerStore+SegmentIndex.swift",
            "LedgerStore+SegmentQueryIndex.swift",
            "LedgerStore+Queries.swift",
            "LedgerStore+RecordIndexes.swift",
            "LedgerRollupIndex.swift",
            "LedgerSessionIndex.swift"
        ]

        for fileName in focusedFiles {
            let file = domainURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 230, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func rollupMutationIndexesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let domainURL = root.appending(path: "timetracker/Stores/Domains")
        let focusedFiles = [
            "RollupIncrementalIndex.swift",
            "RollupIncrementalIndex+Mutation.swift",
            "RollupIncrementalIndex+Pace.swift",
            "RollupIncrementalIndex+Topology.swift"
        ]

        for fileName in focusedFiles {
            let file = domainURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 230, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func analyticsFeatureFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let analyticsURL = root.appending(path: "timetracker/Features/Analytics")
        let focusedFiles = [
            "AnalyticsViews.swift",
            "AnalyticsHomeContent.swift",
            "AnalyticsCategoryDetailView.swift",
            "AnalyticsCategory.swift",
            "AnalyticsOverviewRows.swift",
            "AnalyticsMetricListViews.swift",
            "AnalyticsDetailListViews.swift",
            "AnalyticsPeriodSection.swift",
            "Sections/AnalyticsActivityBarViews.swift",
            "Sections/AnalyticsActivityViews.swift",
            "Sections/AnalyticsDistributionSlice.swift",
            "Sections/AnalyticsDistributionViews.swift",
            "Sections/AnalyticsForecastViews.swift",
            "Sections/AnalyticsGroupBarLayout.swift",
            "Sections/AnalyticsGroupBreakdownPresentation.swift",
            "Sections/AnalyticsGroupBreakdownViews.swift",
            "Sections/AnalyticsOverlapViews.swift",
            "Sections/AnalyticsOverlapRow.swift",
            "Sections/AnalyticsQualityViews.swift",
            "Sections/AnalyticsTrendViews.swift"
        ]

        for fileName in focusedFiles {
            let file = analyticsURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 180, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func swiftUIEnumeratedCollectionsAreMaterializedBeforeForEach() throws {
        let root = try projectRootURL()
        let sourceRoots = [
            "timetracker",
            "timetrackerWidgetExtension",
            "timetrackerWatchApp",
            "timetrackerLiveActivityExtension"
        ]
        let directEnumeratedForEach = try NSRegularExpression(
            pattern: #"ForEach\s*\(\s*(?!Array\s*\()[^\n]*\.enumerated\(\)"#
        )

        for sourceRoot in sourceRoots {
            let sourceURL = root.appending(path: sourceRoot)
            guard let enumerator = FileManager.default.enumerator(
                at: sourceURL,
                includingPropertiesForKeys: nil
            ) else {
                Issue.record("Could not enumerate \(sourceRoot)")
                continue
            }

            for case let file as URL in enumerator where file.pathExtension == "swift" {
                let source = try String(contentsOf: file, encoding: .utf8)
                let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
                let matches = directEnumeratedForEach.matches(in: source, range: fullRange)
                #expect(matches.isEmpty, "\(file.lastPathComponent) passes an enumerated sequence directly to ForEach")
            }
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
            "AnalyticsSelectionPolicy.swift",
            "LedgerBucketCache.swift"
        ]

        for fileName in focusedFiles {
            let file = analyticsURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
            #expect(lineCount <= 220, "\(fileName) has \(lineCount) lines")
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
    func taskTreeServiceFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let taskServicesURL = root.appending(path: "timetracker/Services/Tasks")
        let focusedFiles = [
            "TaskHierarchyRepairPlan.swift",
            "TaskTreeFlattener.swift",
            "TaskTreeModels.swift",
            "TaskTreeProjectionCache.swift",
            "TaskTreeReadIndex.swift",
            "TaskTreeService.swift",
            "TaskTreeService+ReadIndex.swift"
        ]

        for fileName in focusedFiles {
            let file = taskServicesURL.appending(path: fileName)
            #expect(FileManager.default.fileExists(atPath: file.path))
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 160, "\(fileName) has \(lineCount) lines")
        }

        #expect(
            FileManager.default.fileExists(
                atPath: taskServicesURL.appending(path: "TaskTreeServices.swift").path
            ) == false
        )
    }

    @Test
    func ledgerRepositoryFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let repositoryURL = root.appending(path: "timetracker/Repositories")
        let focusedFiles = [
            "SwiftDataTimeTrackingRepository.swift",
            "SwiftDataTimeTrackingRepository+Queries.swift",
            "SwiftDataTimeTrackingRepository+Creation.swift",
            "SwiftDataTimeTrackingRepository+Mutations.swift"
        ]

        for fileName in focusedFiles {
            let file = repositoryURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
            #expect(lineCount <= 180, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func ledgerServiceFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let ledgerURL = root.appending(path: "timetracker/Services/Ledger")
        let focusedFiles = [
            "AppCloudSync.swift",
            "AppCloudSync+RecoveryState.swift",
            "StoreWriteAuthorization.swift",
            "PersistenceWriteSafety.swift",
            "TimerCommand.swift",
            "TimeAggregationService.swift",
            "TimeFormatters.swift",
            "DeviceIdentity.swift",
            "LedgerSummaryService.swift"
        ]

        for fileName in focusedFiles {
            let file = ledgerURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 220, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func syncConflictFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let integrationURL = root.appending(path: "timetracker/Services/SystemIntegration")
        let focusedFiles = [
            "SyncConflictService.swift",
            "SyncConflictService+CloudExport.swift",
            "SyncConflictService+CloudImport.swift",
            "SyncConflictService+Export.swift",
            "SyncConflictService+LocalMutation.swift",
            "SyncConflictService+Recovery.swift",
            "SyncConflictService+Resolution.swift",
            "SyncConflictService+State.swift",
            "SyncConflictService+StateLock.swift",
            "SyncConflictService+StateLocations.swift",
            "SyncConflictService+StateWriting.swift",
            "SyncConflictState.swift",
            "SyncDataSnapshot.swift",
            "SyncDataSnapshot+Capture.swift",
            "SyncDataSnapshot+Restore.swift",
            "SyncDataSnapshot+RestoreChecklist.swift",
            "SyncDataSnapshot+RestoreInbox.swift",
            "SyncDataSnapshot+RestoreLedger.swift",
            "SyncDataSnapshot+RestorePlanning.swift",
            "SyncDataSnapshot+RestoreTasks.swift",
            "SyncSnapshotRecords.swift",
            "SyncSnapshotChecklistRecords.swift",
            "SyncSnapshotInboxRecords.swift",
            "SyncSnapshotLedgerRecords.swift",
            "SyncSnapshotPlanningRecords.swift"
        ]

        for fileName in focusedFiles {
            let file = integrationURL.appending(path: fileName)
            #expect(FileManager.default.fileExists(atPath: file.path))
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 230, "\(fileName) has \(lineCount) lines")
        }

        let adjacentSafetyFiles = [
            "timetracker/Services/SystemIntegration/WatchIncomingCommandStore.swift",
            "timetracker/Services/Tasks/TaskTrackingAvailabilityService.swift"
        ]
        for relativePath in adjacentSafetyFiles {
            let file = root.appending(path: relativePath)
            #expect(FileManager.default.fileExists(atPath: file.path))
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 230, "\(file.lastPathComponent) has \(lineCount) lines")
        }
    }

    @Test
    func durableLocalFileInfrastructureStaysSplitByResponsibility() throws {
        let root = try projectRootURL()
        let integrationURL = root.appending(path: "timetracker/Services/SystemIntegration")
        let focusedFiles = [
            "PathFileLock.swift",
            "DurableLocalFile.swift",
            "DurableLocalFile+Paths.swift",
            "DurableLocalFile+Writing.swift",
            "DurableLocalFile+Synchronization.swift",
            "DurableLocalFile+Quarantine.swift",
            "DurableLocalFile+QuarantinePruning.swift"
        ]

        for fileName in focusedFiles {
            let file = integrationURL.appending(path: fileName)
            #expect(FileManager.default.fileExists(atPath: file.path))
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 160, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func forecastFilesStaySplitByResponsibility() throws {
        let root = try projectRootURL()
        let forecastingURL = root.appending(path: "timetracker/Services/Forecasting")
        let focusedFiles = [
            "TaskRollupService.swift",
            "TaskRollupCalculationContext.swift",
            "TaskRollupInputAggregation.swift",
            "TaskRollupResolutionService.swift",
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
            "TaskCategoryEditorDraftModels.swift",
            "AnalyticsPeriodModels.swift",
            "AnalyticsSummaryReadModels.swift",
            "AnalyticsTimelineReadModels.swift",
            "TaskAnalyticsReadModels.swift",
            "AnalyticsOverlapReadModels.swift",
            "SyncFeedbackModels.swift"
        ]

        for fileName in focusedFiles {
            let file = modelsURL.appending(path: fileName)
            let lineCount = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
            #expect(lineCount <= 260, "\(fileName) has \(lineCount) lines")
        }
    }

    @Test
    func legacyDailySummaryIsExcludedFromTheCurrentSchemaAndProductionMaintenancePaths() throws {
        let schemas = try sourceText("timetracker/Models/SchemaModels.swift")
        let currentRegistry = try sourceText("timetracker/Models/TimeTrackerModelRegistry.swift")
        let migrationPlan = try sourceText("timetracker/Models/SchemaMigrationPlan.swift")
        let legacyModel = try sourceText("timetracker/Models/SummaryModels.swift")
        let productionPaths = try [
            "timetracker/App/SeedData+Cleanup.swift",
            "timetracker/Services/Maintenance/MaintenanceServices.swift",
            "timetracker/Services/Analytics/DailySummaryService.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
        let v10Schema = schemas.components(separatedBy: "enum TimeTrackerSchemaV10").last ?? ""

        #expect(v10Schema.contains("DailySummary.self") == false)
        #expect(currentRegistry.contains("TimeTrackerSchemaV10"))
        #expect(migrationPlan.contains("fromVersion: TimeTrackerSchemaV8.self, toVersion: TimeTrackerSchemaV9.self"))
        #expect(migrationPlan.contains("fromVersion: TimeTrackerSchemaV9.self,\n                toVersion: TimeTrackerSchemaV10.self"))
        #expect(legacyModel.contains("Legacy persisted cache retained only"))
        #expect(productionPaths.contains("FetchDescriptor<DailySummary>") == false)
        #expect(productionPaths.contains("-> DailySummary {") == false)
    }

    @Test
    func appRootFilesStaySplitByPlatformResponsibility() throws {
        let root = try projectRootURL()
        let appURL = root.appending(path: "timetracker/App")
        let focusedFiles = [
            "timetrackerApp.swift",
            "AppModelContainerFactory.swift",
            "AppModelContainerFactory+Testing.swift",
            "AppModelContainerFactory+Fallback.swift",
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
            #expect(lineCount <= 200, "\(fileName) has \(lineCount) lines")
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
        let lifecycle = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+RepositoryRequirements.swift"
        )
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
            "Start/stop timer behavior",
            "Task create/edit/move/complete/reopen/archive/delete",
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
