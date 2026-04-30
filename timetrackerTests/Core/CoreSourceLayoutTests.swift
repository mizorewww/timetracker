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
            "timetracker/Stores/Domains/AnalyticsStore.swift",
            "timetracker/Stores/Refresh/StoreRefreshPlanning.swift",
            "timetracker/Services/Analytics/AnalyticsEngine.swift",
            "timetracker/Services/Forecasting/TaskRollupService.swift",
            "timetracker/Services/Tasks/TaskTreeServices.swift",
            "timetracker/SharedUI/Foundation/LayoutPolicies.swift",
            "timetracker/SharedUI/Components/SharedUI.swift",
            "timetracker/Features/Home/Controls/HomeActionsViews.swift",
            "timetracker/Features/Home/Sections/HomeMetricsViews.swift",
            "timetracker/Features/Home/Rows/HomeTimerRows.swift",
            "timetracker/Features/Tasks/Editor/TaskEditorViews.swift",
            "timetracker/Features/Tasks/Management/TasksViews.swift",
            "timetracker/Features/Analytics/Timeline/AnalyticsTimelineViews.swift",
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
    }
}
