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

    @Test @MainActor
    func regularWidthIOSUsesVisibleSystemSplitView() throws {
        let source = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")
        #expect(SplitColumnLayoutPolicy.iPad.sidebar == ColumnWidth(min: 240, ideal: 260, max: 300))
        #expect(SplitColumnLayoutPolicy.iPad.detail == ColumnWidth(min: 480, ideal: 760, max: nil))
        #expect(source.contains("iPadRootView(store: store)"))
        #expect(source.contains("struct iPadRootView"))
        #expect(source.contains("ipad.splitNavigation"))
        #expect(source.contains("SplitColumnLayoutPolicy.iPad"))
        #expect(source.contains(".navigationSplitViewColumnWidth("))
        #expect(source.contains("preferredCompactColumn: $preferredCompactColumn"))
        #expect(source.contains("preferredCompactColumn = .detail"))
        #expect(source.contains("SidebarRevealButton") == false)
        #expect(source.contains("ToolbarItem(placement: .topBarLeading)") == false)
        #expect(source.contains(".navigationSplitViewStyle(.balanced)"))
        #expect(source.contains(".tabViewStyle(.sidebarAdaptable)") == false)
        #expect(source.contains("ipad.topNavigation") == false)
        #expect(source.contains(".overlay(alignment: .topLeading)") == false)
    }

    @Test
    func phoneHomeUsesSystemLargeTitle() throws {
        let phoneHome = try sourceText("timetracker/Features/Home/PhoneHomeView.swift")

        #expect(phoneHome.contains(".navigationTitle(AppStrings.today)"))
        #expect(phoneHome.contains(".navigationBarTitleDisplayMode(.large)"))
        #expect(phoneHome.contains(".padding(.top, 10)") == false)
        #expect(phoneHome.contains("HeaderBar(store: store") == false)
        #expect(phoneHome.contains("DaySelectionControl") == false)
    }

    @Test
    func phoneNavigationExposesFivePrimaryDestinationsAndSettingsAction() throws {
        let contentSource = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")
        let homeSource = try sourceText("timetracker/Features/Home/PhoneHomeView.swift")

        #expect(contentSource.components(separatedBy: ".accessibilityIdentifier(\"phone.tab.").count - 1 == 5)
        #expect(contentSource.contains("phone.tab.today"))
        #expect(contentSource.contains("phone.tab.inbox"))
        #expect(contentSource.contains("phone.tab.tasks"))
        #expect(contentSource.contains("phone.tab.focus"))
        #expect(contentSource.contains("phone.tab.analytics"))
        #expect(contentSource.contains("phone.tab.settings") == false)
        #expect(contentSource.contains("phone.tabView"))
        #expect(contentSource.contains(".navigationDestination(for: PhoneTodayRoute.self)"))
        #expect(contentSource.contains("SettingsView(store: store)"))
        #expect(contentSource.contains("case settings"))
        #expect(homeSource.contains("Button(action: openSettings)"))
        #expect(homeSource.contains(".accessibilityIdentifier(\"settings.open\")"))
    }

    @Test
    func quickStartComposesPinnedAndFrequentRecentTasks() throws {
        let homeSource = try [
            "timetracker/Features/Home/Sections/HomeQuickStartViews.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartButtons.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartEditorViews.swift"
        ]
            .map(sourceText)
            .joined(separator: "\n")
        let storeSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+TaskReadModels.swift")

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
    func homeExposesQuickStartAndTimelineAsAccessibleSections() throws {
        let homeSource = try sourceText("timetracker/Features/Home/PhoneHomeView.swift")
        let quickStartSource = try sourceText("timetracker/Features/Home/Sections/HomeQuickStartViews.swift")
        let timelineSource = try sourceText("timetracker/Features/Home/Sections/HomeTimelineViews.swift")

        #expect(homeSource.contains(".accessibilityIdentifier(\"home.quickStart\")"))
        #expect(homeSource.contains(".accessibilityIdentifier(\"home.timeline\")"))
        #expect(quickStartSource.contains(".accessibilityIdentifier(\"home.quickStart\")"))
        #expect(timelineSource.contains(".accessibilityIdentifier(\"home.timeline\")"))
    }

    @Test
    func compactTaskPickerUsesTheSystemSheetMaterial() throws {
        let source = try sourceText("timetracker/Features/Home/Controls/HomeActionsViews.swift")

        #expect(source.contains(".presentationBackground(") == false)
        #expect(source.contains(".scrollContentBackground(.hidden)"))
    }

    @Test
    func trackingEntrypointsShareAvailabilityAndRunningStateSemantics() throws {
        let source = try [
            "timetracker/Features/Home/PhoneHomeView.swift",
            "timetracker/Features/Home/PhoneHomeRows.swift",
            "timetracker/Features/Home/Controls/HomeActionsViews.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartViews.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartButtons.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartEditorViews.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupViews.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")

        #expect(source.components(separatedBy: "isTaskAvailableForTracking").count >= 8)
        #expect(source.contains("let activeSegment = store.activeSegment(for: task.id)"))
        #expect(source.contains("store.stop(segment: activeSegment)"))
        #expect(source.contains("isRunning ? \"stop.fill\" : \"play.fill\""))
        #expect(source.contains("timer.task.stopHint"))
        #expect(source.contains(".presentationBackground(") == false)
    }

    @Test
    func todayMetricsUseSemanticTrendColorsAndEqualCompactActions() throws {
        let source = try [
            "timetracker/Features/Home/Sections/HomeMetricsViews.swift",
            "timetracker/Features/Home/Controls/HomeActionsViews.swift",
            "timetracker/SharedUI/Components/MetricCards.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
        let homeMetricsSource = try sourceText("timetracker/Features/Home/Sections/HomeMetricsViews.swift")
        let sharedMetricsSource = try sourceText("timetracker/SharedUI/Components/MetricCards.swift")

        #expect(source.contains("trendColor: grossTrend.color"))
        #expect(source.contains(".foregroundStyle(metric.trendColor)"))
        #expect(source.contains(".green"))
        #expect(source.contains(".red"))
        #expect(sharedMetricsSource.contains("struct MetricCell"))
        #expect(sharedMetricsSource.contains("struct MetricSummaryItem"))
        #expect(homeMetricsSource.contains("struct MetricCell") == false)
        #expect(source.contains("startButton\n                    .frame(maxWidth: .infinity)"))
        #expect(source.contains("newTaskButton\n                    .frame(maxWidth: .infinity)"))
        #expect(source.contains(".layoutPriority(1.1)") == false)
    }
}
