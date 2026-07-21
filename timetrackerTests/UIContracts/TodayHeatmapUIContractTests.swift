import Foundation
import Testing

struct TodayHeatmapUIContractTests {
    @Test
    func settingsUsesTheSharedHierarchyPickerForImmediateTaskSelection() throws {
        let settings = try sourceText(
            "timetracker/Features/Settings/TodayHeatmapSettingsSection.swift"
        )
        let picker = try [
            "timetracker/SharedUI/Components/TaskHierarchyPicker.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerRows.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerBehavior.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")

        #expect(settings.contains("NavigationLink {"))
        #expect(settings.contains("TaskHierarchyPicker("))
        #expect(settings.contains("mode: .multipleSelection("))
        #expect(settings.contains("context: .todayHeatmap"))
        #expect(settings.contains("showsDismissButton") == false)
        #expect(settings.contains("OrderedTaskIDSelectionMutation.toggling("))
        #expect(settings.contains("hiddenSelectionRecovery"))
        #expect(settings.contains("OrderedTaskIDSelectionMutation.removing("))
        #expect(settings.contains(
            ".accessibilityIdentifier(\"settings.todayHeatmap.tasks\")"
        ))
        #expect(settings.contains(
            "\"settings.todayHeatmap.taskPicker.clear\""
        ))
        #expect(settings.contains(
            "\"settings.todayHeatmap.taskPicker.removeHidden\""
        ))
        #expect(settings.contains("List {") == false)
        #expect(picker.contains("case multipleSelection("))
        #expect(picker.contains("case .singleSelection, .multipleSelection:"))
        #expect(picker.contains("selectedTaskIDs.contains(item.id)"))
        #expect(picker.contains("isSelectionDisabled(for: item)"))
        #expect(picker.contains("current.subtracting(previous)"))
    }

    @Test
    func heatmapSelectionPersistsAsABoundedSyncedPreference() throws {
        let preferences = try sourceText(
            "timetracker/Models/SyncedPreferences.swift"
        )
        let sanitizer = try sourceText(
            "timetracker/Models/PreferenceValueSanitizer.swift"
        )
        let commands = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+CloudPreferenceCommands.swift"
        )
        let settings = try sourceText(
            "timetracker/Features/Settings/SettingsCategorySections.swift"
        )

        #expect(preferences.contains("case todayHeatmapTaskIDs"))
        #expect(preferences.contains("var todayHeatmapTaskIDs: [UUID] = []"))
        #expect(sanitizer.contains("maximumTodayHeatmapTaskCount"))
        #expect(sanitizer.contains("static func todayHeatmapTaskIDs("))
        #expect(commands.contains("func setTodayHeatmapTaskIDs("))
        #expect(commands.contains(".todayHeatmapTaskIDs"))
        #expect(settings.contains("TodayHeatmapSettingsSection("))
        #expect(settings.contains("store.setTodayHeatmapTaskIDs(taskIDs)"))
    }

    @Test
    func taskDetailUsesTheSameDefaultOffHeatmapPreference() throws {
        let detail = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailContentView.swift"
        )
        let section = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailHeatmapTrackingSection.swift"
        )
        let commands = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+CloudPreferenceCommands.swift"
        )
        let preferences = try sourceText(
            "timetracker/Models/SyncedPreferences.swift"
        )

        #expect(detail.contains("TaskDetailHeatmapTrackingSection("))
        #expect(section.contains("Toggle(isOn: trackingBinding)"))
        #expect(section.contains("preferences.todayHeatmapTaskIDs.contains(task.id)"))
        #expect(section.contains("store.setTodayHeatmapTrackingEnabled("))
        #expect(section.contains("task.detail.heatmapTracking"))
        #expect(section.contains("ActivityHeatmapPalettePreview("))
        #expect(section.contains("task.detail.heatmapPalette"))
        #expect(commands.contains("func setTodayHeatmapTrackingEnabled("))
        #expect(commands.contains("OrderedTaskIDSelectionMutation.adding("))
        #expect(commands.contains("OrderedTaskIDSelectionMutation.removing("))
        #expect(preferences.contains("var todayHeatmapTaskIDs: [UUID] = []"))
    }

    @Test
    func heatmapConfigurationCopyExistsInEveryLocale() throws {
        let localizationPaths = [
            "timetracker/en.lproj/Localizable.strings",
            "timetracker/zh-Hans.lproj/Localizable.strings",
            "timetracker/zh-Hant.lproj/Localizable.strings"
        ]
        let keys = [
            "heatmap.settings.title",
            "heatmap.settings.tasks",
            "heatmap.settings.off",
            "heatmap.settings.taskCount",
            "heatmap.settings.footer",
            "task.detail.heatmap.title",
            "task.detail.heatmap.toggle",
            "task.detail.heatmap.footer",
            "task.detail.heatmap.limitReached",
            "task.detail.heatmap.palette",
            "heatmap.picker.title",
            "heatmap.picker.selectionHint",
            "heatmap.picker.emptyDescription",
            "heatmap.picker.clear",
            "heatmap.picker.hiddenSelectionCount",
            "heatmap.picker.removeHidden",
            "taskPicker.selection.selected",
            "taskPicker.selection.notSelected",
            "taskPicker.selection.countFormat",
            "taskPicker.selection.limitReachedFormat",
            "home.heatmap.title",
            "home.heatmap.taskCount",
            "home.heatmap.section.footer",
            "home.heatmap.chart.accessibilityLabel",
            "home.heatmap.chart.week",
            "home.heatmap.chart.weekday",
            "home.heatmap.palette.accessibilityLabel",
            "home.heatmap.checklistValueFormat",
            "home.heatmap.quantityValueFormat",
            "home.heatmap.metric.duration",
            "home.heatmap.metric.checklist",
            "home.heatmap.metric.quantityFormat",
            "home.heatmap.footer.durationFormat",
            "home.heatmap.footer.checklistFormat",
            "home.heatmap.footer.quantityFormat",
            "home.heatmap.footer.noActivityFormat",
            "home.heatmap.accessibilitySummaryFormat",
            "home.heatmap.less",
            "home.heatmap.more",
            "home.heatmap.rangeFormat"
        ]

        for path in localizationPaths {
            let source = try sourceText(path)
            for key in keys {
                #expect(source.contains("\"\(key)\" ="))
            }
            if path.contains("zh-") {
                #expect(source.contains(
                    "\"home.heatmap.footer.durationFormat\" = \"此任务及其子任务每天的 Gross"
                ) == false)
                #expect(source.contains(
                    "\"home.heatmap.footer.durationFormat\" = \"此任務及其子任務每天的 Gross"
                ) == false)
            }
        }
    }

    @Test
    func todaySurfacesIndependentSwiftChartsHeatmapsAcrossLayouts() throws {
        let phone = try sourceText(
            "timetracker/Features/Home/PhoneHomeView.swift"
        )
        let desktop = try sourceText(
            "timetracker/Features/Home/HomeViews.swift"
        )
        let section = try sourceText(
            "timetracker/Features/Home/Sections/HomeActivityHeatmapViews.swift"
        )
        let grid = try sourceText(
            "timetracker/SharedUI/Components/ActivityHeatmapGrid.swift"
        )
        let seed = try sourceText(
            "timetracker/App/SeedData+DemoBuild.swift"
        )

        #expect(
            phone.components(
                separatedBy: "HomeActivityHeatmapSection("
            ).count - 1 == 1
        )
        #expect(phone.contains("container: .listSection"))
        #expect(
            desktop.components(
                separatedBy: "HomeActivityHeatmapSection("
            ).count - 1 == 1
        )
        #expect(desktop.contains("container: .card"))
        #expect(section.contains("struct HomeActivityHeatmapSection: View"))
        #expect(section.contains("let container: HomeSectionContainer"))
        #expect(section.contains("request.selectedTaskIDs.isEmpty == false"))
        #expect(section.contains("[TaskActivityHeatmapSnapshot]"))
        #expect(section.contains("ForEach(snapshots)"))
        #expect(section.contains("LazyVStack(spacing: 10)"))
        #expect(section.contains("TaskActivityHeatmapCard(snapshot: snapshot)"))
        #expect(section.contains("home.heatmap.\\(snapshot.taskID.uuidString)"))
        #expect(section.contains("home.heatmap.grid.\\(snapshot.taskID.uuidString)"))
        #expect(section.contains("snapshot.colorHex"))
        #expect(section.contains("case .trackedDuration:"))
        #expect(section.contains("case .checklistCompletions:"))
        #expect(section.contains("case .quantity:"))
        #expect(section.contains(
            "snapshot.totalValue.formatted(.number.locale(locale))"
        ))
        #expect(seed.contains("app.id.uuidString,"))
        #expect(seed.contains("client.id.uuidString"))
        #expect(grid.contains("struct ActivityHeatmapGrid: View"))
        #expect(grid.contains("import Charts"))
        #expect(grid.contains("Chart(cells)"))
        #expect(grid.contains("RectangleMark("))
        #expect(grid.contains("ScrollView(.horizontal)"))
        #expect(grid.contains(
            ".defaultScrollAnchor(.trailing, for: .initialOffset)"
        ))
        #expect(grid.contains(
            ".defaultScrollAnchor(.leading, for: .alignment)"
        ))
        #expect(grid.contains(".font(.caption2)"))
        #expect(grid.contains(".font(.system(size:") == false)
        #expect(grid.contains("id: \\.offset") == false)
        #expect(grid.contains("Button(") == false)
        #expect(grid.contains("AppColors.grossTime") == false)
        #expect(grid.contains("Color(hex: colorHex)"))
        #expect(grid.contains("DurationFormatter.chart(value, locale: locale)"))
        #expect(grid.contains(".accessibilityValue("))
    }

    @Test
    func heatmapRefreshIdentityTracksDataSelectionAndCalendarBoundaries() throws {
        let section = try sourceText(
            "timetracker/Features/Home/Sections/HomeActivityHeatmapViews.swift"
        )
        let service = try sourceText(
            "timetracker/Services/Analytics/TodayActivityHeatmapSnapshotService.swift"
        )
        let store = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+TodayActivityHeatmap.swift"
        )

        for token in [
            "selectedTaskIDs",
            "analyticsRevision",
            "taskReadModelRevision",
            "localDay",
            "localWeekStart",
            "clockRevision"
        ] {
            #expect(section.contains(token))
        }
        #expect(section.contains(".task(id: request)"))
        #expect(section.contains(".NSSystemClockDidChange"))
        #expect(section.contains(".NSSystemTimeZoneDidChange"))
        #expect(section.contains(".NSCalendarDayChanged"))
        #expect(store.contains("taskByID: taskByID"))
        #expect(store.contains("childrenByParentID: childrenByParentID"))
        #expect(store.contains("segments: allSegments"))
        #expect(store.contains("quantityGoals: taskQuantityGoals"))
        #expect(store.contains("quantityEntries: taskQuantityEntries"))
        #expect(store.contains("tasks: tasks") == false)
        #expect(service.contains("let indexes = activityIndexes("))
        #expect(service.contains("func taskSnapshots("))
        #expect(service.contains("segments.visibleDeduplicatedByID()"))
        #expect(service.contains("quantityGoals.visibleDeduplicatedByID()"))
        #expect(service.contains("quantityEntries.visibleDeduplicatedByID()"))
        #expect(service.contains("for weekIndex in 0..<Self.weekCount"))
        #expect(
            service.components(
                separatedBy: "checklistItems.visibleDeduplicatedByID()"
            ).count - 1 == 1
        )
    }
}
