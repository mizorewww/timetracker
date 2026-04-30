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
            "timetracker/SharedUI/Foundation/ColorSupport.swift",
            "timetracker/SharedUI/Components/SharedUI.swift",
            "timetracker/SharedUI/Components/ChecklistControls.swift",
            "timetracker/SharedUI/Components/ForecastInfoViews.swift",
            "timetracker/SharedUI/Components/StatusBadges.swift",
            "timetracker/SharedUI/Components/TaskVisuals.swift",
            "timetracker/SharedUI/Components/TaskProgressViews.swift",
            "timetracker/SharedUI/Components/SectionHeaders.swift",
            "timetracker/SharedUI/Components/ActionControls.swift",
            "timetracker/Features/Home/Controls/HomeActionsViews.swift",
            "timetracker/Features/Home/Sections/HomeMetricsViews.swift",
            "timetracker/Features/Home/Rows/HomeTimerRows.swift",
            "timetracker/Features/Tasks/Editor/TaskEditorViews.swift",
            "timetracker/Features/Tasks/Management/TasksViews.swift",
            "timetracker/Features/Settings/SettingsSectionsViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsOverviewViews.swift",
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

    @Test
    func projectMapDocumentsPrimaryFoldersAndEntryPoints() throws {
        let map = try sourceText("Docs/ProjectMap.md")
        let requiredFolders = [
            "`timetracker/App`",
            "`timetracker/Models`",
            "`timetracker/Repositories`",
            "`timetracker/Commands`",
            "`timetracker/Stores/Facade`",
            "`timetracker/Stores/Domains`",
            "`timetracker/Stores/Refresh`",
            "`timetracker/Services/Analytics`",
            "`timetracker/Services/Forecasting`",
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
            "Live Activity display",
            "Localization"
        ]

        for entryPoint in requiredEntryPoints {
            #expect(map.contains(entryPoint))
        }
    }
}
