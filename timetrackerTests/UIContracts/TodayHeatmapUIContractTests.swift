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
        #expect(settings.contains("store.todayHeatmapSelectedTaskIDs"))
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
        #expect(picker.contains("case .todayHeatmap:"))
        #expect(picker.contains("store.todayHeatmapSelectableTaskIDs"))
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
        #expect(commands.contains(
            "todayHeatmapRecurrenceProjection.canonicalTaskIDs(ids)"
        ))
        #expect(commands.contains(".todayHeatmapTaskIDs"))
        #expect(settings.contains("TodayHeatmapSettingsSection("))
        #expect(settings.contains("store.setTodayHeatmapTaskIDs(taskIDs)"))
    }

    @Test
    func heatmapPeriodUsesANativeMenuAndSyncedPreferenceCommand() throws {
        let model = try sourceText(
            "timetracker/Models/ActivityHeatmapModels.swift"
        )
        let preferences = try sourceText(
            "timetracker/Models/SyncedPreferences.swift"
        )
        let sanitizer = try sourceText(
            "timetracker/Models/PreferenceValueSanitizer.swift"
        )
        let commands = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+CloudPreferenceCommands.swift"
        )
        let section = try sourceText(
            "timetracker/Features/Settings/TodayHeatmapSettingsSection.swift"
        )
        let settings = try sourceText(
            "timetracker/Features/Settings/SettingsCategorySections.swift"
        )

        for token in [
            "case oneMonth",
            "case threeMonths",
            "case sixMonths",
            "case oneYear",
            "static let standard = ActivityHeatmapPeriod.oneYear",
            "case .oneMonth:",
            "case .threeMonths:",
            "case .sixMonths:",
            "case .oneYear:",
        ] {
            #expect(model.contains(token))
        }
        #expect(model.contains("Identifiable"))
        #expect(model.contains("Hashable"))
        #expect(preferences.contains("case todayHeatmapPeriod"))
        #expect(preferences.contains(
            "var todayHeatmapPeriod = ActivityHeatmapPeriod.standard"
        ))
        #expect(sanitizer.contains("static func todayHeatmapPeriod("))
        #expect(commands.contains(
            "func setTodayHeatmapPeriod(_ period: ActivityHeatmapPeriod)"
        ))
        #expect(commands.contains(".todayHeatmapPeriod"))

        #expect(section.contains("Picker("))
        #expect(section.contains("selection: periodBinding"))
        #expect(section.contains("ForEach(ActivityHeatmapPeriod.allCases)"))
        #expect(section.contains(".tag(period)"))
        #expect(section.contains("SettingsRowLabel("))
        #expect(section.contains("systemImage: \"calendar\""))
        #expect(section.contains(".pickerStyle(.menu)"))
        #expect(section.contains(
            ".accessibilityIdentifier(\"settings.todayHeatmap.period\")"
        ))
        #expect(section.contains(
            "\"settings.todayHeatmap.period.\\(period.rawValue)\""
        ))
        #expect(section.contains("onChangePeriod(period)"))
        #expect(settings.contains("onChangePeriod: { period in"))
        #expect(settings.contains("handleSettingsStoreMutation("))
        #expect(settings.contains("store.setTodayHeatmapPeriod(period)"))
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
        #expect(section.contains("store.todayHeatmapOwnerTaskID(for: task.id)"))
        #expect(section.contains("store.todayHeatmapSelectedTaskIDs.contains("))
        #expect(section.contains("task.detail.heatmap.recurringToggle"))
        #expect(section.contains("task.detail.heatmap.recurringFooter"))
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
            "heatmap.settings.period",
            "heatmap.settings.period.oneMonth",
            "heatmap.settings.period.threeMonths",
            "heatmap.settings.period.sixMonths",
            "heatmap.settings.period.oneYear",
            "heatmap.settings.tasks",
            "heatmap.settings.off",
            "heatmap.settings.taskCount",
            "heatmap.settings.footer",
            "task.detail.heatmap.title",
            "task.detail.heatmap.toggle",
            "task.detail.heatmap.recurringToggle",
            "task.detail.heatmap.footer",
            "task.detail.heatmap.recurringFooter",
            "task.detail.heatmap.unavailable",
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
            "home.info.format",
            "home.heatmap.info.duration",
            "home.heatmap.info.checklist",
            "home.heatmap.info.quantity.title",
            "home.heatmap.info.quantity",
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

        let expectedPeriodTranslations = [
            (
                "timetracker/en.lproj/Localizable.strings",
                [
                    "\"heatmap.settings.period\" = \"Default Range\";",
                    "\"heatmap.settings.period.oneMonth\" = \"1 Month\";",
                    "\"heatmap.settings.period.threeMonths\" = \"3 Months\";",
                    "\"heatmap.settings.period.sixMonths\" = \"6 Months\";",
                    "\"heatmap.settings.period.oneYear\" = \"1 Year\";",
                ]
            ),
            (
                "timetracker/zh-Hans.lproj/Localizable.strings",
                [
                    "\"heatmap.settings.period\" = \"默认范围\";",
                    "\"heatmap.settings.period.oneMonth\" = \"1 个月\";",
                    "\"heatmap.settings.period.threeMonths\" = \"3 个月\";",
                    "\"heatmap.settings.period.sixMonths\" = \"6 个月\";",
                    "\"heatmap.settings.period.oneYear\" = \"1 年\";",
                ]
            ),
            (
                "timetracker/zh-Hant.lproj/Localizable.strings",
                [
                    "\"heatmap.settings.period\" = \"預設範圍\";",
                    "\"heatmap.settings.period.oneMonth\" = \"1 個月\";",
                    "\"heatmap.settings.period.threeMonths\" = \"3 個月\";",
                    "\"heatmap.settings.period.sixMonths\" = \"6 個月\";",
                    "\"heatmap.settings.period.oneYear\" = \"1 年\";",
                ]
            ),
        ]
        for (path, translations) in expectedPeriodTranslations {
            let source = try sourceText(path)
            for translation in translations {
                #expect(source.contains(translation))
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
        let section = try [
            "timetracker/Features/Home/HomeSectionContainer.swift",
            "timetracker/Features/Home/Sections/HomeActivityHeatmapViews.swift",
            "timetracker/Features/Home/Sections/HomeActivityHeatmapCard.swift"
        ].map { try sourceText($0) }.joined(separator: "\n")
        let information = try sourceText(
            "timetracker/Features/Home/Controls/HomeInformationViews.swift"
        )
        let grid = try [
            "timetracker/SharedUI/Components/ActivityHeatmapGrid.swift",
            "timetracker/SharedUI/Components/ActivityHeatmapChart.swift",
            "timetracker/SharedUI/Components/ActivityHeatmapPalette.swift",
            "timetracker/SharedUI/Components/ActivityHeatmapValueFormatter.swift"
        ].map { try sourceText($0) }.joined(separator: "\n")
        let seed = try sourceText(
            "timetracker/App/SeedData+DemoBuild.swift"
        )

        #expect(
            phone.components(
                separatedBy: "HomeActivityHeatmapSection("
            ).count - 1 == 1
        )
        #expect(phone.contains("container: .listSection"))
        #expect(phone.contains(".homeVisualizationListSection()"))
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
        #expect(section.contains("ForEach(snapshots.dropFirst())") == false)
        #expect(section.contains(
            "ForEach(snapshots) { snapshot in\n                        Section {"
        ))
        #expect(section.contains("snapshot.id == snapshots.first?.id"))
        #expect(section.contains("TaskActivityHeatmapCard(snapshot: snapshot)"))
        #expect(section.contains("homeVisualizationListCard("))
        #expect(section.contains("homeVisualizationListSection()"))
        #expect(section.contains(".listRowBackground(Color.clear)"))
        #expect(section.contains(".listRowSeparator(.hidden)"))
        #expect(section.contains("RoundedRectangle(cornerRadius: 26, style: .continuous)"))
        #expect(section.contains("cornerRadius: AppLayout.cardRadius") == false)
        #expect(section.contains("home.heatmap.card.\\(snapshot.taskID.uuidString)"))
        #expect(section.contains("home.heatmap.grid.\\(snapshot.taskID.uuidString)"))
        #expect(section.contains("HomeSectionInformationButton.heatmaps"))
        #expect(information.contains("home.heatmaps.info"))
        #expect(information.contains("home.info.heatmaps.task."))
        #expect(section.contains("home.heatmaps.header"))
        #expect(
            section.contains(
                ".accessibilityIdentifier(\"home.heatmaps\")"
            ) == false
        )
        #expect(section.contains("metricExplanation") == false)
        #expect(section.contains("noActivityExplanation"))
        #expect(section.contains("snapshot.colorHex"))
        #expect(section.contains("case .trackedDuration:"))
        #expect(section.contains("case .checklistCompletions:"))
        #expect(section.contains("case .quantity:"))
        #expect(section.contains(
            "snapshot.totalValue.formatted(.number.locale(locale))"
        ))
        #expect(seed.contains("app.id.uuidString,"))
        #expect(seed.contains("client.id.uuidString"))
        #expect(seed.contains("title: \"Daily Push-ups\""))
        #expect(seed.contains("--uitesting-today-heatmap-template-id"))
        #expect(seed.contains("flatMap(UUID.init(uuidString:)) ?? UUID()"))
        #expect(seed.contains("TaskRecurrenceRule("))
        #expect(seed.contains("TaskRecurrenceOccurrence("))
        #expect(seed.contains("createGeneratedRecurrenceTask("))
        #expect(seed.contains("TaskQuantityGoal("))
        #expect(seed.contains("taskID: yesterdayTask.id"))
        #expect(seed.contains("taskID: todayTask.id"))
        #expect(seed.contains("todayTask.id.uuidString"))
        #expect(seed.contains("Morning Set") == false)
        #expect(grid.contains("struct ActivityHeatmapGrid: View"))
        #expect(grid.contains("import Charts"))
        #expect(grid.contains("Chart(cells)"))
        #expect(grid.contains("RectangleMark("))
        #expect(grid.contains("ScrollView(.horizontal)"))
        #expect(grid.contains(
            ".defaultScrollAnchor(.trailing, for: .initialOffset)"
        ))
        #expect(grid.contains(
            ".defaultScrollAnchor(.trailing, for: .alignment)"
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
        let service = try [
            "timetracker/Services/Analytics/TodayActivityHeatmapSnapshotService.swift",
            "timetracker/Services/Analytics/TodayActivityHeatmapSnapshotService+Indexing.swift",
            "timetracker/Services/Analytics/TodayActivityHeatmapSnapshotService+MetricValues.swift",
            "timetracker/Services/Analytics/TodayActivityHeatmapSnapshotService+CalendarProjection.swift"
        ].map { try sourceText($0) }.joined(separator: "\n")
        let store = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+TodayActivityHeatmap.swift"
        )

        for token in [
            "selectedTaskIDs",
            "analyticsRevision",
            "taskReadModelRevision",
            "localDay",
            "localWeekStart",
            "liveRefreshBucket",
            "clockRevision"
        ] {
            #expect(section.contains(token))
        }
        #expect(section.contains(".task(id: request)"))
        #expect(section.contains(".NSSystemClockDidChange"))
        #expect(section.contains(".NSSystemTimeZoneDidChange"))
        #expect(section.contains(".NSCalendarDayChanged"))
        #expect(section.contains("TimelineView(.periodic(from: .now, by: 60))"))
        #expect(section.contains("store.activeSegments.isEmpty"))
        #expect(section.contains("store.todayHeatmapRenderableTaskIDs"))
        #expect(section.contains("Int(now.timeIntervalSinceReferenceDate / 60)"))
        #expect(section.contains("now: context.date"))
        #expect(store.contains("taskByID: taskByID"))
        #expect(store.contains("childrenByParentID: childrenByParentID"))
        #expect(store.contains(
            "additionalContributingTaskIDsBySelectedTaskID:"
        ))
        #expect(store.contains("generatedTaskIDsByTemplateTaskID"))
        #expect(store.contains("segments: allSegments"))
        #expect(store.contains("quantityGoals: taskQuantityGoals"))
        #expect(store.contains("quantityEntries: taskQuantityEntries"))
        #expect(store.contains("tasks: tasks") == false)
        #expect(service.contains("let indexes = activityIndexes("))
        #expect(service.contains("func taskSnapshots("))
        #expect(service.contains("segments.visibleDeduplicatedByID()"))
        #expect(service.contains("quantityGoals.visibleDeduplicatedByID()"))
        #expect(service.contains("quantityEntries.visibleDeduplicatedByID()"))
        #expect(service.contains("for weekIndex in 0..<weekCount"))
        #expect(
            service.components(
                separatedBy: "checklistItems.visibleDeduplicatedByID()"
            ).count - 1 == 1
        )
    }

    @Test
    func heatmapPeriodDrivesRefreshRangeAndAdaptiveChartLayout() throws {
        let section = try sourceText(
            "timetracker/Features/Home/Sections/HomeActivityHeatmapViews.swift"
        )
        let service = try [
            "timetracker/Services/Analytics/TodayActivityHeatmapSnapshotService.swift",
            "timetracker/Services/Analytics/TodayActivityHeatmapSnapshotService+CalendarProjection.swift"
        ].map { try sourceText($0) }.joined(separator: "\n")
        let store = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+TodayActivityHeatmap.swift"
        )
        let chart = try sourceText(
            "timetracker/SharedUI/Components/ActivityHeatmapChart.swift"
        )
        let grid = try sourceText(
            "timetracker/SharedUI/Components/ActivityHeatmapGrid.swift"
        )

        #expect(section.contains("let period: ActivityHeatmapPeriod"))
        #expect(section.contains(
            "period = store.preferences.todayHeatmapPeriod"
        ))
        #expect(section.contains(".task(id: request)"))
        #expect(section.contains("period: request.period"))
        #expect(section.contains("ActivityHeatmapLayoutContext"))
        #expect(section.contains("case .card:"))
        #expect(section.contains(".regular"))
        #expect(section.contains("case .listSection:"))
        #expect(section.contains(".phone"))

        #expect(store.contains(
            "period: ActivityHeatmapPeriod,\n        now: Date"
        ))
        #expect(store.contains("period: period"))
        #expect(service.contains("period: ActivityHeatmapPeriod"))
        #expect(service.contains("weekCount: period.weekCount"))
        #expect(service.contains("result.reserveCapacity(weekCount)"))
        #expect(service.contains("for weekIndex in 0..<weekCount"))
        #expect(service.contains("value: -(period.weekCount - 1)"))
        #expect(service.contains("Self.weekCount") == false)

        #expect(chart.contains("struct ActivityHeatmapLayoutPolicy"))
        for token in [
            "case (.phone, ...5):\n            15",
            "case (.phone, ...14):\n            12",
            "case (.phone, ...27):\n            11",
            "case (.phone, _):\n            10",
            "case (.regular, ...5):\n            14",
            "case (.regular, ...14):\n            11",
            "case (.regular, ...27):\n            10",
            "case (.regular, _):\n            9",
        ] {
            #expect(chart.contains(token))
        }
        #expect(chart.contains("width: .fixed(layoutPolicy.cellSize)"))
        #expect(chart.contains("height: .fixed(layoutPolicy.cellSize)"))
        #expect(chart.contains("weekCount: snapshot.weeks.count"))
        #expect(chart.contains("width: layoutPolicy.chartWidth"))
        #expect(chart.contains("height: layoutPolicy.chartHeight"))
        #expect(chart.contains(
            "\"home.heatmap.chart.\\(snapshot.taskID.uuidString)\""
        ))
        #expect(grid.contains(
            ".defaultScrollAnchor(.trailing, for: .alignment)"
        ))
        #expect(grid.contains(
            "\"home.heatmap.range.\\(snapshot.taskID.uuidString)\""
        ))
    }
}
