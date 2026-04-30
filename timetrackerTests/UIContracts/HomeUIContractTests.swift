import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct HomeUIContractTests {
    @Test @MainActor
    func quickStartRecentTasksRankByFrequencyAndSkipPinnedTasks() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pinnedTask = try taskRepository.createTask(title: "Pinned", parentID: nil, colorHex: nil, iconName: nil)
        let frequentTask = try taskRepository.createTask(title: "Frequent", parentID: nil, colorHex: nil, iconName: nil)
        let occasionalTask = try taskRepository.createTask(title: "Occasional", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date(timeIntervalSince1970: 10_000)

        _ = try timeRepository.addManualSegment(
            taskID: occasionalTask.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: frequentTask.id,
            startedAt: start.addingTimeInterval(1_000),
            endedAt: start.addingTimeInterval(1_600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: frequentTask.id,
            startedAt: start.addingTimeInterval(2_000),
            endedAt: start.addingTimeInterval(2_600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: pinnedTask.id,
            startedAt: start.addingTimeInterval(3_000),
            endedAt: start.addingTimeInterval(3_600),
            note: nil
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        let quickStartTasks = store.frequentRecentTasks(excluding: [pinnedTask.id], limit: 2)

        #expect(quickStartTasks.map(\.id) == [frequentTask.id, occasionalTask.id])
    }


    @Test
    func localizationFilesExposeTheSameKeys() throws {
        let locales = ["en", "zh-Hans", "zh-Hant"]
        let keySets = try locales.map { locale -> Set<String> in
            let path = try #require(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: "\(locale).lproj"))
            let dictionary = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            #expect(dictionary.isEmpty == false)
            return Set(dictionary.keys)
        }

        let reference = try #require(keySets.first)
        for keys in keySets.dropFirst() {
            #expect(keys == reference)
        }
    }

    @Test
    func liveActivityExtensionLocalizationFilesExposeTheSameKeys() throws {
        let projectRoot = try projectRootURL()
        let locales = ["en", "zh-Hans", "zh-Hant"]
        let keySets = try locales.map { locale -> Set<String> in
            let path = projectRoot.appending(path: "timetrackerLiveActivityExtension/\(locale).lproj/Localizable.strings").path
            let dictionary = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            #expect(dictionary.isEmpty == false)
            return Set(dictionary.keys)
        }

        let reference = try #require(keySets.first)
        for keys in keySets.dropFirst() {
            #expect(keys == reference)
        }
    }

    @Test
    func swiftSourcesDoNotContainHardCodedChineseText() throws {
        let projectRoot = try projectRootURL()
        let sourceRoots = [
            projectRoot.appending(path: "timetracker"),
            projectRoot.appending(path: "timetrackerLiveActivityExtension"),
            projectRoot.appending(path: "SharedLiveActivity")
        ]
        let swiftFiles = try sourceRoots.flatMap { sourceRoot -> [URL] in
            let enumerator = try #require(FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil))
            return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
        let chinesePattern = try NSRegularExpression(pattern: "\\p{Han}")

        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            #expect(chinesePattern.firstMatch(in: source, range: range) == nil, "Move user-facing Chinese text into Localizable.strings: \(file.lastPathComponent)")
        }
    }

    @Test @MainActor
    func regularWidthIOSUsesVisibleSystemSplitView() throws {
        let source = try sourceText("timetracker/App/ContentView.swift")

        #expect(SplitColumnLayoutPolicy.iPad.sidebar == ColumnWidth(min: 240, ideal: 260, max: 300))
        #expect(SplitColumnLayoutPolicy.iPad.detail.min == 560)
        #expect(source.contains("iPadRootView(store: store)"))
        #expect(source.contains("struct iPadRootView"))
        #expect(source.contains("ipad.splitNavigation"))
        #expect(source.contains("SplitColumnLayoutPolicy.iPad"))
        #expect(source.contains(".navigationSplitViewColumnWidth("))
        #expect(source.contains("NavigationSplitView(columnVisibility: $columnVisibility)"))
        #expect(source.contains("ToolbarItem(placement: .topBarLeading)"))
        #expect(source.contains("if columnVisibility != .all"))
        #expect(source.contains("\"sidebar.left\""))
        #expect(source.contains(".navigationSplitViewStyle(.balanced)"))
        #expect(source.contains(".tabViewStyle(.sidebarAdaptable)") == false)
        #expect(source.contains("ipad.topNavigation") == false)
        #expect(source.contains(".overlay(alignment: .topLeading)") == false)
    }

    @Test
    func phoneHomeUsesSystemLargeTitle() throws {
        let source = try sourceText("timetracker/Features/Home/HomeViews.swift")

        guard
            let start = source.range(of: "struct PhoneHomeView"),
            let end = source.range(of: "struct HeaderBar")
        else {
            Issue.record("Could not locate PhoneHomeView")
            return
        }
        let phoneHome = String(source[start.lowerBound..<end.lowerBound])

        #expect(phoneHome.contains(".navigationTitle(AppStrings.today)"))
        #expect(phoneHome.contains(".navigationBarTitleDisplayMode(.large)"))
        #expect(phoneHome.contains(".padding(.top, 10)") == false)
        #expect(phoneHome.contains("HeaderBar(store: store") == false)
    }

    @Test
    func quickStartComposesPinnedAndFrequentRecentTasks() throws {
        let homeSource = try sourceText("timetracker/Features/Home/HomeQuickStartViews.swift")
        let storeSource = try sourceText("timetracker/Stores/TimeTrackerStore+ReadModels.swift")

        #expect(homeSource.contains("private var pinnedTasks"))
        #expect(homeSource.contains("private var recentFillTasks"))
        #expect(homeSource.contains("limit: 3"))
        #expect(homeSource.contains("QuickStartTaskButton"))
        #expect(homeSource.contains("private let maxPinnedTasks = 3") == false)
        #expect(homeSource.contains("QuickStartSelectableTaskRow"))
        #expect(homeSource.contains("selectedIDs.append(task.id)"))
        #expect(homeSource.contains("selectedIDs.remove(atOffsets: offsets)"))
        #expect(storeSource.contains("func frequentRecentTasks(excluding excludedIDs: Set<UUID> = [], limit: Int = 3)"))
    }

    @Test
    func homePlacesQuickStartBeforeTimeline() throws {
        let source = try sourceText("timetracker/Features/Home/HomeViews.swift")

        guard
            let desktopStart = source.range(of: "struct DesktopMainView"),
            let phoneStart = source.range(of: "struct PhoneHomeView"),
            let headerStart = source.range(of: "struct HeaderBar")
        else {
            Issue.record("Could not locate home view sections")
            return
        }

        let desktopMain = String(source[desktopStart.lowerBound..<phoneStart.lowerBound])
        let phoneHome = String(source[phoneStart.lowerBound..<headerStart.lowerBound])
        let desktopQuickStart = try #require(desktopMain.range(of: "QuickStartSection(store: store)")?.lowerBound)
        let desktopTimeline = try #require(desktopMain.range(of: "TimelineSection(store: store)")?.lowerBound)
        let phoneQuickStart = try #require(phoneHome.range(of: "QuickStartSection(store: store)")?.lowerBound)
        let phoneTimeline = try #require(phoneHome.range(of: "TimelineSection(store: store)")?.lowerBound)

        #expect(desktopQuickStart < desktopTimeline)
        #expect(phoneQuickStart < phoneTimeline)
    }

    @Test
    func compactTaskPickerUsesOpaqueSystemSheet() throws {
        let source = try sourceText("timetracker/Features/Home/HomeActionsViews.swift")

        #expect(source.contains(".presentationBackground(Color(uiColor: .systemGroupedBackground))"))
        #expect(source.contains(".scrollContentBackground(.hidden)"))
    }

    @Test
    func taskTreeUsesFlatVisibleRowsSoEachTaskOwnsItsListRow() throws {
        let source = try sourceText("timetracker/Features/Tasks/TasksViews.swift")
        let serviceSource = try sourceText("timetracker/Services/TaskTreeServices.swift")

        #expect(source.contains("ForEach(store.taskTreeRows(expandedTaskIDs: expansionState.expandedTaskIDs))"))
        #expect(source.contains("TaskManagementTreeRow") == false)
        #expect(source.contains("DisclosureGroup(") == false)
        #expect(serviceSource.contains("struct TaskTreeFlattener"))
        #expect(serviceSource.contains("TaskTreeRowModel"))
        #expect(source.contains("rotationEffect") == false)
    }

    @Test
    func todayMetricsUseSemanticTrendColorsAndEqualCompactActions() throws {
        let source = try [
            "timetracker/Features/Home/HomeMetricsViews.swift",
            "timetracker/Features/Home/HomeActionsViews.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")

        #expect(source.contains("trendColor: grossTrend.color"))
        #expect(source.contains(".foregroundStyle(metric.trendColor)"))
        #expect(source.contains(".green"))
        #expect(source.contains(".red"))
        #expect(source.contains("startButton\n                    .frame(maxWidth: .infinity)"))
        #expect(source.contains("newTaskButton\n                    .frame(maxWidth: .infinity)"))
        #expect(source.contains(".layoutPriority(1.1)") == false)
    }

    @Test
    func compactTaskRowsShowChecklistProgressBar() throws {
        let source = try sourceText("timetracker/Features/Tasks/TaskManagementRowViews.swift")

        #expect(source.contains("CompactChecklistProgressLine("))
        #expect(source.contains("ProgressView(value: progress.fraction)"))
        #expect(source.contains("checklist.progressFormat"))
        #expect(source.contains("if progress.totalCount > 0 {\n                    CompactChecklistProgressLine"))
    }

    @Test
    func taskRowsUseLifetimeRollupDurationInsteadOfTodayOnlyDuration() throws {
        let tasksSource = try sourceText("timetracker/Features/Tasks/TaskManagementRowViews.swift")
        let inspectorSource = try sourceText("timetracker/Features/Inspector/InspectorInfoViews.swift")
        let forecastSource = try sourceText("timetracker/Features/Inspector/InspectorForecastViews.swift")

        #expect(tasksSource.contains("rollup?.workedSeconds ?? store.secondsForTaskTotalRollup(task)"))
        #expect(tasksSource.contains("secondsForTaskTodayRollup(task)") == false)
        #expect(inspectorSource.contains("task.field.total"))
        #expect(forecastSource.contains("forecast.worked"))
    }

    @Test
    func taskEditorUsesInlineStatusPickerAndRemovesTaskKindClassification() throws {
        let editorSource = try [
            "timetracker/Features/Tasks/TaskEditorViews.swift",
            "timetracker/Features/Tasks/TaskEditorComponents.swift"
        ]
        .map { path in
            try sourceText(path)
        }
        .joined(separator: "\n")
        let modelsSource = try sourceText("timetracker/Models/TaskModels.swift")
        let englishStrings = try sourceText("timetracker/en.lproj/Localizable.strings")

        #expect(editorSource.contains("TaskStatusPicker(selection: $draft.status)"))
        #expect(editorSource.contains(".pickerStyle(.inline)"))
        #expect(editorSource.contains("TaskStatusPickerOption(status: status)"))
        #expect(editorSource.contains("TaskKindPicker") == false)
        #expect(modelsSource.contains("enum TaskNodeKind") == false)
        #expect(englishStrings.contains("editor.task.kind") == false)
    }

    @Test
    func taskListShowsStatusBadgesInsteadOfTaskKindBadges() throws {
        let tasksSource = try sourceText("timetracker/Features/Tasks/TaskManagementRowViews.swift")
        let sharedSource = try sourceText("timetracker/SharedUI/SharedUI.swift")

        #expect(tasksSource.contains("TaskStatusBadge(status: task.status)"))
        #expect(tasksSource.contains("TaskKindBadge") == false)
        #expect(sharedSource.contains("struct TaskKindBadge") == false)
    }

    @Test
    func checklistUsesTodoStyleAndKeepsCompletedHistoryHint() throws {
        let editorSource = try sourceText("timetracker/Features/Tasks/TaskEditorComponents.swift")
        let inspectorSource = try sourceText("timetracker/Features/Inspector/InspectorChecklistViews.swift")
        let sharedSource = try sourceText("timetracker/SharedUI/SharedUI.swift")
        let englishStrings = try sourceText("timetracker/en.lproj/Localizable.strings")

        #expect(sharedSource.contains("\"checkmark.circle.fill\""))
        #expect(editorSource.contains("ChecklistCompletionButton"))
        #expect(editorSource.contains(".strikethrough(item.isCompleted)"))
        #expect(inspectorSource.contains("store.toggleChecklistItem(item)"))
        #expect(inspectorSource.contains("visibleItems.prefix(5)"))
        #expect(englishStrings.contains("\"checklist.keepCompletedHint\""))
    }
}
