import Foundation
import SwiftUI
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreArchitectureBehaviorTests {
    @Test @MainActor
    func rootLayoutPolicyUsesStableInterfaceIdiom() {
        #expect(RootLayoutPolicy(interfaceIdiom: .phone).shell == .phone)
        #expect(RootLayoutPolicy(interfaceIdiom: .pad).shell == .pad)
        #expect(RootLayoutPolicy(interfaceIdiom: .unsupported).shell == .phone)

        #if os(iOS)
        #expect(RootLayoutPolicy(userInterfaceIdiom: .phone).shell == .phone)
        #expect(RootLayoutPolicy(userInterfaceIdiom: .pad).shell == .pad)
        #expect(RootLayoutPolicy(userInterfaceIdiom: .unspecified).shell == .phone)
        #endif
    }

    @Test
    func sidebarUsesSharedFlatTaskTreeContract() throws {
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarViews.swift")

        #expect(sidebarSource.contains("store.taskTreeSections(expandedTaskIDs: expansionState.expandedTaskIDs)"))
        #expect(sidebarSource.contains("TaskCategorySectionHeader"))
        #expect(sidebarSource.contains("DisclosureGroup(") == false)
    }

    @Test
    func focusPickerSeparatesTaskTitleFromParentContext() throws {
        let source = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupSelectionViews.swift"
        )

        #expect(source.contains("value: selectedTask?.title"))
        #expect(source.contains("detail: selectedTask.flatMap(store.parentPath(for:))"))
        #expect(source.contains("value: selectedTask.map(store.path(for:))") == false)
        #expect(source.contains(".truncationMode(.middle)"))
    }

    @Test
    func enumDisplayTextUsesLocalizationKeys() throws {
        #expect(AnalyticsRange.today.displayName == AppStrings.localized("analytics.range.day"))
        #expect(TimeSessionSource.importCalendar.displayName == AppStrings.localized("source.calendar"))

        let analyticsSource = try sourceText("timetracker/Features/Analytics/AnalyticsViews.swift")
        let storeSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore.swift")

        #expect(analyticsSource.contains("Text(range.rawValue)") == false)
        #expect(storeSource.contains("return \"Ready\"") == false)
        #expect(storeSource.contains("return \"Focus\"") == false)
    }

    @Test
    func analyticsLoadsVersionedSnapshotsOutsideTheViewBody() throws {
        let viewSource = try sourceText("timetracker/Features/Analytics/AnalyticsViews.swift")
        let detailSource = try sourceText("timetracker/Features/Analytics/AnalyticsCategoryDetailView.swift")
        let taskDetailSource = try sourceText("timetracker/Features/Tasks/Detail/TaskDetailView.swift")
        let taskDetailContentSource = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailContentView.swift"
        )
        let facadeSource = try [
            "timetracker/Stores/Facade/TimeTrackerStore+Analytics.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+AnalyticsLoading.swift"
        ].map(sourceText).joined(separator: "\n")
        let visualTaskSource = try sourceText(
            "timetracker/Services/Analytics/AnalyticsVisualSnapshotModels.swift"
        )

        #expect(viewSource.contains("TimelineView") == false)
        #expect(detailSource.contains("TimelineView") == false)
        #expect(viewSource.contains("AnalyticsRefreshPlan.next("))
        #expect(viewSource.contains("scenePhase == .active"))
        #expect(viewSource.contains(".task(id: refreshPlan)"))
        #expect(viewSource.contains(".task(id: request)"))
        #expect(viewSource.contains("canRemainVisible(whileLoading: request)"))
        #expect(viewSource.contains("await Task.yield()"))
        #expect(viewSource.contains("await store.loadAnalyticsSnapshot("))
        #expect(detailSource.contains("await store.loadAnalyticsSnapshot("))
        #expect(viewSource.contains(".NSSystemClockDidChange"))
        #expect(viewSource.contains(".NSSystemTimeZoneDidChange"))
        #expect(facadeSource.contains("liveRefreshBucket: liveRefreshBucket"))
        #expect(facadeSource.contains("cachedSnapshot("))
        #expect(facadeSource.contains("if range == .today"))
        #expect(facadeSource.contains("AnalyticsVisualSnapshotTask.resolve"))
        #expect(visualTaskSource.contains("Task.detached(priority: .userInitiated)"))
        #expect(visualTaskSource.contains("withTaskCancellationHandler"))
        #expect(taskDetailSource.contains(".task(id: request)"))
        #expect(taskDetailSource.contains("snapshot: store.taskAnalyticsSnapshot") == false)
        #expect(taskDetailSource.contains("TimelineView") == false)
        #expect(taskDetailSource.contains("AnalyticsRefreshPlan.next("))
        #expect(taskDetailSource.contains("scenePhase == .active"))
        #expect(taskDetailSource.contains(".task(id: refreshPlan)"))
        #expect(taskDetailSource.contains("canRemainVisible(whileLoading: request)"))
        #expect(taskDetailSource.contains("snapshot = resolvedSnapshot"))
        #expect(taskDetailSource.contains("loadedRequest = request"))
        #expect(taskDetailContentSource.contains("task.detail.analyticsLoading"))
        #expect(taskDetailSource.contains("store.taskAnalyticsSnapshotRequest("))
        #expect(taskDetailSource.contains("store.analyticsLiveRefreshBucket(") == false)
        #expect(taskDetailSource.contains("TaskAnalyticsSnapshotRequest(") == false)
        #expect(detailSource.contains("canRemainVisible(whileLoading: request)"))
        #expect(detailSource.contains("await Task.yield()"))
        #expect(facadeSource.contains("cachedTaskSnapshot("))
        #expect(facadeSource.contains("taskIDs: request.taskIDs"))
        #expect(facadeSource.contains("evaluationKey: request.evaluationKey"))
        #expect(facadeSource.contains("visibleSegments(forTaskIDs:") == false)
        #expect(facadeSource.contains("overlapping: decisionInterval"))
        #expect(facadeSource.contains("taskIDs: request.taskIDs"))
        #expect(facadeSource.contains("visibleRecentSegments(forTaskIDs: request.taskIDs)"))
        #expect(facadeSource.contains("recentSegments: recentSegments"))
    }

    @Test
    func checklistRowsUseIndexedOrCachedProgress() throws {
        let source = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+ChecklistReadModels.swift")

        #expect(source.contains("rollupDomainStore.rollup(for: taskID)?.checklistProgress"))
        #expect(source.contains("checklistByTaskID[taskID]"))
        #expect(source.contains("checklistItems: checklistItems") == false)
    }

    @Test
    func mutationRefreshAndSegmentCommandsUseScopedIndexes() throws {
        let refreshSource = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+DomainRefreshes.swift"
        )
        let taskReadSource = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+TaskReadModels.swift"
        )
        let calculationSource = try sourceText(
            "timetracker/Services/Forecasting/TaskRollupCalculationContext.swift"
        )
        let ledgerCommandSource = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+LedgerCommands.swift"
        )
        let preferenceCommandSource = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+PreferenceCommands.swift"
        )
        let countdownCommandSource = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+CountdownCommands.swift"
        )
        let preferenceCoordinatorSource = try sourceText(
            "timetracker/Services/Preferences/StoreScopedPreferenceCommandCoordinator.swift"
        )
        let pomodoroCommandSource = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+PomodoroCommands.swift"
        )
        let pomodoroCoordinatorSource = try sourceText(
            "timetracker/Services/TimeTracking/StoreScopedPomodoroCommandCoordinator.swift"
        )
        let segmentCoordinatorSource = try [
            "timetracker/Services/TimeTracking/StoreScopedSegmentCommandCoordinator.swift",
            "timetracker/Services/TimeTracking/StoreScopedSegmentCommandCoordinator+Validation.swift"
        ].map(sourceText).joined(separator: "\n")

        #expect(refreshSource.contains("var store = rollupDomainStore") == false)
        #expect(refreshSource.contains("rollupDomainStore.refreshAffected("))
        #expect(refreshSource.contains("checklistDomainStore.items(for: taskID)"))
        #expect(taskReadSource.contains(
            "func forecastEligibleTaskIDs() -> Set<UUID> {\n        forecastEligibleTaskIDCache"
        ))
        #expect(calculationSource.contains("calculateUpdates(buildOrder:"))
        #expect(calculationSource.contains("return updates"))
        #expect(ledgerCommandSource.contains("StoreScopedSegmentCommandCoordinator("))
        #expect(ledgerCommandSource.contains(".addManualTime(draft: draft, taskID: taskID)"))
        #expect(ledgerCommandSource.contains("ledgerCommandHandler.addManualTime") == false)
        #expect(ledgerCommandSource.contains("allSegments.first") == false)
        #expect(ledgerCommandSource.contains("preferences.allowParallelTimers") == false)
        #expect(preferenceCommandSource.contains("StoreScopedPreferenceCommandCoordinator("))
        #expect(preferenceCommandSource.contains("perform(event:") == false)
        #expect(countdownCommandSource.contains("StoreScopedCountdownCommandCoordinator("))
        #expect(countdownCommandSource.contains("countdownCommandHandler.add") == false)
        #expect(preferenceCoordinatorSource.contains("transaction.withFreshContext"))
        #expect(preferenceCoordinatorSource.contains("withLockedStoreAccess"))
        #expect(pomodoroCommandSource.contains("preferences.allowParallelTimers") == false)
        #expect(
            pomodoroCoordinatorSource.components(
                separatedBy: "TimerAdmissionPreferenceResolver"
            ).count - 1 == 2
        )
        #expect(segmentCoordinatorSource.contains("TimerAdmissionPreferenceResolver"))
        #expect(segmentCoordinatorSource.contains("transaction.withFreshContext"))
        #expect(segmentCoordinatorSource.contains("func addManualTime("))
        #expect(segmentCoordinatorSource.contains("timeRepository.segments(ids: [segmentID]).first"))
        #expect(segmentCoordinatorSource.contains("allSegments.first") == false)
    }

    @Test @MainActor
    func layoutPoliciesCentralizeResponsiveChoices() {
        #expect(HomeLayoutPolicy(width: 600).isCompact)
        #expect(HomeLayoutPolicy(width: 900).usesTwoColumnContent == false)
        #expect(HomeLayoutPolicy(width: 1_022).contentWidth == 966)
        #expect(HomeLayoutPolicy(width: 1_022).usesTwoColumnContent == false)
        #expect(HomeLayoutPolicy(width: 1_055).usesTwoColumnContent == false)
        #expect(HomeLayoutPolicy(width: 1_056).contentWidth == 1_000)
        #expect(HomeLayoutPolicy(width: 1_056).usesTwoColumnContent)
        #expect(HomeLayoutPolicy(width: 1_236).contentWidth == 1_180)
        #expect(HomeLayoutPolicy(width: 1_400).contentWidth == 1_180)
        #expect(HomeLayoutPolicy(width: 1_100).contentMaxWidth == 1_180)
        #expect(HomeLayoutPolicy(width: 1_100).supportingColumnWidth == 360)
        #expect(AnalyticsLayoutPolicy(horizontalSizeClass: nil).showsPageTitleInContent)
        #expect(SplitColumnLayoutPolicy.iPad.detail == ColumnWidth(min: 480, ideal: 760, max: nil))
        #expect(SplitColumnLayoutPolicy.mac.sidebar == ColumnWidth(min: 220, ideal: 240, max: 270))
        #expect(SplitColumnLayoutPolicy.mac.detail == ColumnWidth(min: 420, ideal: 720, max: nil))
        #expect(PomodoroLayoutPolicy(horizontalSizeClass: .compact).setupCardPadding == 18)
        #expect(PomodoroLayoutPolicy(horizontalSizeClass: .compact).setupSectionSpacing == 20)
        #expect(PomodoroLayoutPolicy(horizontalSizeClass: .regular).setupCardPadding == 24)
        #expect(PomodoroPageLayoutPolicy(viewportWidth: 390, prefersSingleColumn: false).verticalPadding == 16)
        #expect(PomodoroPageLayoutPolicy(viewportWidth: 900, prefersSingleColumn: false).verticalPadding == 24)
    }
}
