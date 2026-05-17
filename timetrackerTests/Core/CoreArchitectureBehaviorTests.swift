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
    func macSettingsSceneAppliesPreferredColorScheme() throws {
        let settingsSceneSource = try sourceText("timetracker/App/SettingsSceneView.swift")

        #expect(settingsSceneSource.contains(".preferredColorScheme(settingsColorScheme)"))
        #expect(settingsSceneSource.contains("case \"light\": return .light"))
        #expect(settingsSceneSource.contains("case \"dark\": return .dark"))
        #expect(settingsSceneSource.contains("default: return nil"))
    }

    @Test
    func analyticsViewsPreferCachedSnapshotsOutsideBody() throws {
        let analyticsSource = try sourceText("timetracker/Features/Analytics/AnalyticsViews.swift")
        let detailSource = try sourceText("timetracker/Features/Analytics/AnalyticsCategoryDetailViews.swift")
        let storeSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+Analytics.swift")

        #expect(analyticsSource.contains("store.displayAnalyticsSnapshot(for: request)"))
        #expect(analyticsSource.contains(".task(id: request)"))
        #expect(analyticsSource.contains("guard isActive else { return }"))
        #expect(analyticsSource.contains("store.analyticsSnapshot(for: range, now:") == false)
        #expect(detailSource.contains("store.displayAnalyticsSnapshot(for: request)"))
        #expect(detailSource.contains(".task(id: request)"))
        #expect(storeSource.contains("func prewarmAnalyticsSnapshots"))
        #expect(storeSource.contains("func prewarmDestinationCache"))
    }

    @Test @MainActor
    func layoutPoliciesCentralizeResponsiveChoices() {
        #expect(HomeLayoutPolicy(width: 600).isCompact)
        #expect(HomeLayoutPolicy(width: 900).usesHorizontalMetrics)
        #expect(AnalyticsLayoutPolicy(horizontalSizeClass: nil).showsPageTitleInContent)
        #expect(InboxLayoutPolicy(horizontalSizeClass: .compact).isCompact)
        #expect(InboxLayoutPolicy(horizontalSizeClass: .compact).cardCornerRadius == 28)
        #expect(InboxLayoutPolicy(horizontalSizeClass: nil).cardCornerRadius == 24)
        #expect(InboxLayoutPolicy(horizontalSizeClass: .compact).rowBaseHeight == 78)
        #expect(SplitColumnLayoutPolicy.iPad.detail == ColumnWidth(min: 560, ideal: 780, max: nil))
        #expect(SplitColumnLayoutPolicy.mac.sidebar == ColumnWidth(min: 220, ideal: 240, max: 270))
    }
}
