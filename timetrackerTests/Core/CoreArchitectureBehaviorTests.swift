import Foundation
import SwiftUI
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreArchitectureBehaviorTests {
    @Test
    func sidebarUsesSharedFlatTaskTreeContract() throws {
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarViews.swift")

        #expect(sidebarSource.contains("store.taskTreeSections(expandedTaskIDs: expansionState.expandedTaskIDs)"))
        #expect(sidebarSource.contains("TaskCategorySectionHeader"))
        #expect(sidebarSource.contains("DisclosureGroup(") == false)
    }

    @Test
    func enumDisplayTextUsesLocalizationKeys() throws {
        #expect(AnalyticsRange.today.displayName == AppStrings.localized("analytics.range.today"))
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
        let facadeSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+Analytics.swift")

        #expect(viewSource.contains("TimelineView") == false)
        #expect(detailSource.contains("TimelineView") == false)
        #expect(viewSource.contains("AnalyticsRefreshPlan.next("))
        #expect(viewSource.contains("scenePhase == .active"))
        #expect(viewSource.contains(".task(id: refreshPlan)"))
        #expect(viewSource.contains(".task(id: request)"))
        #expect(viewSource.contains(".NSSystemClockDidChange"))
        #expect(viewSource.contains(".NSSystemTimeZoneDidChange"))
        #expect(facadeSource.contains("liveRefreshBucket: liveRefreshBucket"))
        #expect(facadeSource.contains("cachedSnapshot("))
        #expect(taskDetailSource.contains(".task(id: request)"))
        #expect(taskDetailSource.contains("snapshot: store.taskAnalyticsSnapshot") == false)
        #expect(facadeSource.contains("cachedTaskSnapshot("))
    }

    @Test
    func checklistRowsUseIndexedOrCachedProgress() throws {
        let source = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+ChecklistReadModels.swift")

        #expect(source.contains("rollupDomainStore.rollup(for: taskID)?.checklistProgress"))
        #expect(source.contains("checklistByTaskID[taskID]"))
        #expect(source.contains("checklistItems: checklistItems") == false)
    }

    @Test
    func mutationRefreshUsesPersistentIndexesInsteadOfWholeSnapshotCopies() throws {
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

        #expect(refreshSource.contains("var store = rollupDomainStore") == false)
        #expect(refreshSource.contains("rollupDomainStore.refreshAffected("))
        #expect(refreshSource.contains("checklistDomainStore.items(for: taskID)"))
        #expect(taskReadSource.contains(
            "func forecastEligibleTaskIDs() -> Set<UUID> {\n        forecastEligibleTaskIDCache"
        ))
        #expect(calculationSource.contains("calculateUpdates(buildOrder:"))
        #expect(calculationSource.contains("return updates"))
        #expect(ledgerCommandSource.contains("ledgerDomainStore.segment(for:"))
        #expect(ledgerCommandSource.contains("allSegments.first") == false)
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
        #expect(InboxLayoutPolicy(horizontalSizeClass: .compact).isCompact)
        #expect(InboxLayoutPolicy(horizontalSizeClass: .compact).cardCornerRadius == 28)
        #expect(InboxLayoutPolicy(horizontalSizeClass: nil).cardCornerRadius == 24)
        #expect(SplitColumnLayoutPolicy.iPad.detail == ColumnWidth(min: 480, ideal: 760, max: nil))
        #expect(SplitColumnLayoutPolicy.mac.sidebar == ColumnWidth(min: 220, ideal: 240, max: 270))
        #expect(SplitColumnLayoutPolicy.mac.detail == ColumnWidth(min: 420, ideal: 720, max: nil))
    }
}
