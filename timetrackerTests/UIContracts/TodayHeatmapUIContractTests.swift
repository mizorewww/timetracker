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
            "heatmap.picker.title",
            "heatmap.picker.selectionHint",
            "heatmap.picker.emptyDescription",
            "heatmap.picker.clear",
            "heatmap.picker.hiddenSelectionCount",
            "heatmap.picker.removeHidden",
            "taskPicker.selection.selected",
            "taskPicker.selection.notSelected",
            "taskPicker.selection.countFormat",
            "taskPicker.selection.limitReachedFormat"
        ]

        for path in localizationPaths {
            let source = try sourceText(path)
            for key in keys {
                #expect(source.contains("\"\(key)\" ="))
            }
        }
    }
}
