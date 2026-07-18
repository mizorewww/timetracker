import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct HomeUIContractTests {
    @Test
    func todayMetricTrendHandlesEveryComparisonState() {
        #expect(TodayMetricTrend(current: 100, previous: 0) == .noComparison)
        #expect(TodayMetricTrend(current: 150, previous: 100) == .increased(percent: 50))
        #expect(TodayMetricTrend(current: 50, previous: 100) == .decreased(percent: 50))
        #expect(TodayMetricTrend(current: 100, previous: 100) == .unchanged)
        #expect(TodayMetricTrend(current: 1004, previous: 1000) == .unchanged)
    }

    @Test @MainActor
    func todayMetricsClipBothDaysAndSeparateGrossFromWallTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 9,
            hour: 12
        )))
        let todayStart = calendar.startOfDay(for: now)
        let previousStart = try #require(calendar.date(byAdding: .day, value: -1, to: todayStart))
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Metrics",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )

        func addSegment(start: Date, end: Date) throws {
            _ = try timeRepository.addManualSegment(
                taskID: task.id,
                startedAt: start,
                endedAt: end,
                note: nil
            )
        }

        try addSegment(
            start: previousStart.addingTimeInterval(23.5 * 3_600),
            end: todayStart.addingTimeInterval(30 * 60)
        )
        try addSegment(
            start: previousStart.addingTimeInterval(23.75 * 3_600),
            end: todayStart.addingTimeInterval(15 * 60)
        )
        try addSegment(
            start: todayStart.addingTimeInterval(9 * 3_600),
            end: todayStart.addingTimeInterval(10 * 3_600)
        )
        try addSegment(
            start: todayStart.addingTimeInterval(9.5 * 3_600),
            end: todayStart.addingTimeInterval(10.5 * 3_600)
        )

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        let snapshot = store.todayMetricsSnapshot(now: now, calendar: calendar)

        #expect(snapshot.grossSeconds == 9_900)
        #expect(snapshot.wallSeconds == 7_200)
        #expect(snapshot.previousGrossSeconds == 2_700)
        #expect(snapshot.previousWallSeconds == 1_800)
    }

    @Test
    func todayMetricsNormalizeAndTraverseSegmentsOnlyOnce() throws {
        let source = try sourceText("timetracker/Features/Home/HomeReadModels.swift")

        #expect(source.components(separatedBy: ".visibleDeduplicatedByID()").count - 1 == 1)
        #expect(source.components(separatedBy: "for segment in segments").count - 1 == 1)
        #expect(source.components(separatedBy: "visibleSegments(overlapping:").count - 1 == 1)
        #expect(source.contains("ledgerSummaryService.secondsInInterval") == false)
    }

    @Test @MainActor
    func todayCountdownOrderingIsStableForMatchingDatesAndTitles() {
        let date = Date(timeIntervalSince1970: 10_000)
        let later = CountdownEvent(title: "Later", date: date.addingTimeInterval(1), deviceID: "test")
        let beta = CountdownEvent(title: "Beta", date: date, deviceID: "test")
        let alphaB = CountdownEvent(title: "Alpha", date: date, deviceID: "test")
        let alphaA = CountdownEvent(title: "Alpha", date: date, deviceID: "test")
        alphaA.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        alphaB.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        let sorted = TodayHomeContent.sortedCountdownEvents([later, beta, alphaB, alphaA])

        #expect(sorted.map(\.id) == [alphaA.id, alphaB.id, beta.id, later.id])
    }

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

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        let quickStartTasks = store.frequentRecentTasks(excluding: [pinnedTask.id], limit: 2)

        #expect(quickStartTasks.map(\.id) == [frequentTask.id, occasionalTask.id])
    }

    @Test @MainActor
    func ipadIdiomUsesSystemSplitViewAcrossWindowWidths() throws {
        let source = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")
        #expect(SplitColumnLayoutPolicy.iPad.sidebar == ColumnWidth(min: 240, ideal: 260, max: 300))
        #expect(SplitColumnLayoutPolicy.iPad.detail == ColumnWidth(min: 480, ideal: 760, max: nil))
        #expect(source.contains("UIDevice.current.userInterfaceIdiom"))
        #expect(source.contains("switch layoutPolicy.shell"))
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
        let homeSource = try [
            "timetracker/Features/Home/PhoneHomeView.swift",
            "timetracker/Features/Home/PhoneHomeSections.swift"
        ]
            .map(sourceText)
            .joined(separator: "\n")

        #expect(contentSource.components(separatedBy: ".accessibilityIdentifier(\"phone.tab.").count - 1 == 5)
        #expect(contentSource.contains("phone.tab.today"))
        #expect(contentSource.contains("phone.tab.inbox"))
        #expect(contentSource.contains("phone.tab.tasks"))
        #expect(contentSource.contains("phone.tab.focus"))
        #expect(contentSource.contains("phone.tab.analytics"))
        #expect(contentSource.contains("phone.tab.settings") == false)
        #expect(contentSource.contains("phone.tabView"))
        #expect(contentSource.contains("presentationRouter.presentSettings()"))
        #expect(contentSource.contains("PhoneTodayRoute") == false)
        #expect(contentSource.contains("todayPath") == false)
        #expect(contentSource.contains("SettingsView(store: store)") == false)
        #expect(homeSource.contains("Button(action: openSettings)"))
        #expect(homeSource.contains(".accessibilityIdentifier(\"settings.open\")"))
        #expect(homeSource.contains("home.toolbar.newTask") == false)
    }

    @Test
    func quickStartComposesPinnedAndFrequentRecentTasks() throws {
        let homeSource = try [
            "timetracker/Features/Home/HomeReadModels.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartViews.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartButtons.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartEditorViews.swift"
        ]
            .map(sourceText)
            .joined(separator: "\n")
        let storeSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+TaskReadModels.swift")

        #expect(homeSource.contains("let pinnedTasks = store.preferences.quickStartTaskIDs"))
        #expect(homeSource.contains("let recentTasks = store.frequentRecentTasks("))
        #expect(homeSource.contains("quickStartLimit - pinnedTasks.count"))
        #expect(homeSource.contains(".deduplicatedByID()"))
        #expect(homeSource.contains("QuickStartTaskGroup(tasks: tasks"))
        #expect(homeSource.contains("QuickStartTaskButton"))
        #expect(homeSource.contains(".lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)"))
        #expect(homeSource.contains(".multilineTextAlignment(.leading)"))
        #expect(homeSource.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(homeSource.contains("private let maxPinnedTasks = 3") == false)
        #expect(homeSource.contains("QuickStartSelectableTaskRow"))
        #expect(homeSource.contains("selectedIDs.append(task.id)"))
        #expect(homeSource.contains("QuickStartSelectionMutation.removingVisibleSelections("))
        #expect(homeSource.contains("visibleIDs: pinnedTasks.map(\\.id)"))
        #expect(homeSource.contains("selectedIDs.remove(atOffsets: offsets)") == false)
        #expect(storeSource.contains("func frequentRecentTasks(excluding excludedIDs: Set<UUID> = [], limit: Int = 3)"))
    }

    @Test
    func quickStartUsesIndexedTaskIdentityAndSeparatesNavigationFromTimerActions() throws {
        let identitySource = try sourceText(
            "timetracker/Services/Tasks/TaskIdentityPresentation.swift"
        )
        let quickStartSource = try [
            "timetracker/Features/Home/PhoneHomeRows.swift",
            "timetracker/Features/Home/PhoneHomeSections.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartButtons.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartEditorViews.swift"
        ]
            .map(sourceText)
            .joined(separator: "\n")

        #expect(identitySource.contains("struct TaskIdentityText: Equatable, Sendable"))
        #expect(identitySource.contains("struct TaskVisualPresentation: Equatable, Sendable"))
        #expect(identitySource.contains("struct TaskIdentityPresentation: Equatable, Sendable"))
        #expect(identitySource.contains("case hierarchical"))
        #expect(identitySource.contains("case standard"))
        #expect(identitySource.contains("case compact"))
        #expect(identitySource.contains("taskByID[taskID]"))
        #expect(identitySource.contains("taskParentPathByID[taskID]"))
        #expect(identitySource.contains("taskPathByID[taskID]"))
        #expect(identitySource.contains("components(separatedBy:") == false)
        #expect(identitySource.contains(".split(separator:") == false)
        #expect(quickStartSource.contains(".text(for: .standard)"))
        #expect(quickStartSource.contains("TaskIcon(visual: presentation.visual"))
        #expect(quickStartSource.contains("RunningStatusBadge()"))
        #expect(quickStartSource.contains("struct QuickStartTimerAction"))
        #expect(quickStartSource.contains("Button(action: openTask)"))
        #expect(quickStartSource.contains("home.quickStart.timer."))
        #expect(quickStartSource.contains("performTimerPickerSelection(task)"))
        #expect(quickStartSource.contains("store.stop(segment: activeSegment)"))
        #expect(quickStartSource.contains("stop.fill"))
        #expect(quickStartSource.contains("store.openTaskDetail(task.id)"))
        #expect(quickStartSource.contains("store.path(for: task)") == false)
        #expect(quickStartSource.contains("Text(path)") == false)
    }

    @Test
    func homeExposesQuickStartAndTimelineAsAccessibleSections() throws {
        let homeSource = try [
            "timetracker/Features/Home/PhoneHomeView.swift",
            "timetracker/Features/Home/PhoneHomeSections.swift"
        ]
            .map(sourceText)
            .joined(separator: "\n")
        let quickStartSource = try sourceText("timetracker/Features/Home/Sections/HomeQuickStartViews.swift")
        let timelineSource = try sourceText("timetracker/Features/Home/Sections/HomeTimelineViews.swift")

        #expect(homeSource.contains(".accessibilityIdentifier(\"home.quickStart\")"))
        #expect(homeSource.contains(".accessibilityIdentifier(\"home.timeline\")"))
        #expect(quickStartSource.contains(".accessibilityIdentifier(\"home.quickStart\")"))
        #expect(timelineSource.contains(".accessibilityIdentifier(\"home.timeline\")"))
    }

    @Test
    func todayAndAnalyticsShareOneGraphicalTimelineComponent() throws {
        let sharedSource = try [
            "timetracker/SharedUI/Components/TimelineChart.swift",
            "timetracker/SharedUI/Components/TimelineChartGrid.swift",
            "timetracker/SharedUI/Components/TimelineChartBars.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
        let homeSource = try [
            "timetracker/Features/Home/Sections/HomeTimelineViews.swift",
            "timetracker/Features/Home/PhoneHomeSections.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
        let analyticsSource = try sourceText(
            "timetracker/Features/Analytics/Timeline/AnalyticsTimelineViews.swift"
        )

        #expect(sharedSource.contains("struct TimelineChart: View"))
        #expect(sharedSource.contains("TimelineAxisCompression"))
        #expect(sharedSource.contains("horizontalTimeline"))
        #expect(sharedSource.contains("verticalTimeline"))
        #expect(homeSource.contains("TodayTimelineChart("))
        #expect(homeSource.contains(".accessibilityIdentifier(\"home.timeline.graph\")"))
        #expect(analyticsSource.contains("TimelineChart("))
        #expect(analyticsSource.contains("horizontalTimeline") == false)
        #expect(analyticsSource.contains("verticalTimeline") == false)
    }

    @Test
    func trackedTimeRowsUseSharedBoundedDisplayPolicy() throws {
        let sharedSource = try sourceText("timetracker/SharedUI/Components/DurationLabels.swift")
        let homeTimelineSource = try sourceText("timetracker/Features/Home/Rows/HomeTimelineRows.swift")
        let taskRecordsSource = try sourceText("timetracker/Features/Tasks/Detail/TaskDetailRecordViews.swift")

        #expect(sharedSource.contains("struct TrackedTimeDisplaySnapshot"))
        #expect(sharedSource.contains("TrackedTimePolicy.interval("))
        #expect(sharedSource.contains("TrackedTimePolicy.boundedEnd("))
        #expect(sharedSource.contains("TrackedTimePolicy.elapsedSeconds("))
        #expect(sharedSource.contains("endedAt.map({ $0 <= now }) == true"))
        #expect(homeTimelineSource.contains("TrackedTimeDisplaySnapshot("))
        #expect(homeTimelineSource.contains("DurationLabel(startedAt: segment.startedAt"))
        #expect(homeTimelineSource.contains("TimelineView(.periodic(from: .now, by: 1))") == false)
        #expect(homeTimelineSource.contains("taskButton(at: context.date)") == false)
        #expect(homeTimelineSource.contains("Text(.app(\"common.now\"))") == false)
        #expect(taskRecordsSource.contains("TrackedTimeDisplaySnapshot("))
        #expect(homeTimelineSource.contains("timeIntervalSince(segment.startedAt)") == false)
        #expect(homeTimelineSource.contains("now: Date()\n        )") == false)
        #expect(homeTimelineSource.contains("segment.endedAt.map { TimeDisplayFormatter") == false)
        #expect(taskRecordsSource.contains("record.endedAt.map { TimeDisplayFormatter") == false)
    }

    @Test
    func timelineDeletionKeepsItsBaselineAndConfirmationTogether() throws {
        let source = try sourceText(
            "timetracker/Features/Home/Rows/HomeTimelineRows.swift"
        )

        #expect(source.contains("pendingDeletionRequest"))
        #expect(source.contains("isDeleteConfirmationPresented") == false)
        #expect(source.contains("deleteBaseline") == false)
        #expect(source.contains("SegmentDeletionImpact("))
        #expect(source.contains("expectedBaseline: pendingDeletionRequest"))
    }

    @Test
    func compactTaskPickerUsesTheSystemSheetMaterial() throws {
        let source = try sourceText("timetracker/Features/Home/Controls/HomeActionsViews.swift")

        #expect(source.contains(".presentationBackground(") == false)
        #expect(source.contains(".scrollContentBackground(.hidden)"))
        #expect(source.contains("struct TaskStartPickerSheet"))
        #expect(source.contains("dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]"))
    }

    @Test
    func trackingEntrypointsShareAvailabilityAndRunningStateSemantics() throws {
        let source = try [
            "timetracker/Features/Home/HomeReadModels.swift",
            "timetracker/Features/Home/PhoneHomeView.swift",
            "timetracker/Features/Home/PhoneHomeRows.swift",
            "timetracker/Features/Home/PhoneHomeSections.swift",
            "timetracker/Features/Home/Controls/HomeActionsViews.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartViews.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartButtons.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartEditorViews.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroFocusSetupControls.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupEmptyState.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupSelectionViews.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupViews.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroTimerFace.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")

        #expect(source.components(separatedBy: "isTaskAvailableForTracking").count >= 8)
        #expect(source.contains("let activeSegment = store.activeSegment(for: task.id)"))
        #expect(source.contains("store.stop(segment: activeSegment)"))
        #expect(source.contains("QuickStartTimerAction"))
        #expect(source.contains("tasks.openDetail"))
        #expect(source.contains(".presentationBackground(") == false)
    }

    @Test
    func phoneTodayPrioritizesCurrentStateAndReflowsAtAccessibilitySizes() throws {
        let homeSource = try sourceText("timetracker/Features/Home/PhoneHomeView.swift")
        let timerSource = try sourceText("timetracker/Features/Home/Rows/HomeTimerRows.swift")
        let timelineSource = try sourceText("timetracker/Features/Home/Rows/HomeTimelineRows.swift")
        let forecastSource = try sourceText("timetracker/Features/Home/Sections/HomeForecastViews.swift")

        let nowIndex = try #require(homeSource.range(of: "PhoneNowSection(")?.lowerBound)
        let overviewIndex = try #require(homeSource.range(of: "home.overview.title")?.lowerBound)
        let quickStartIndex = try #require(homeSource.range(of: "PhoneQuickStartSection(")?.lowerBound)
        let timelineIndex = try #require(homeSource.range(of: "PhoneTimelineSection(")?.lowerBound)
        let forecastIndex = try #require(homeSource.range(of: "PhoneForecastSection(")?.lowerBound)

        #expect(nowIndex < overviewIndex)
        #expect(overviewIndex < quickStartIndex)
        #expect(quickStartIndex < timelineIndex)
        #expect(timelineIndex < forecastIndex)
        #expect(homeSource.contains("TodayHomeContent(store: store)"))
        #expect(homeSource.contains("home.toolbar.newTask") == false)
        let sectionSource = try sourceText("timetracker/Features/Home/PhoneHomeSections.swift")
        #expect(sectionSource.contains("@Environment(\\.dynamicTypeSize)") == false)
        #expect(sectionSource.contains("if !dynamicTypeSize.isAccessibilitySize") == false)
        #expect(sectionSource.contains("!segments.isEmpty && dynamicTypeSize.isAccessibilitySize") == false)
        #expect(sectionSource.contains("home.switchTimer"))
        #expect(sectionSource.contains("Text(activeTimerActionTitle)"))
        #expect(sectionSource.contains(".lineLimit(nil)"))
        #expect(sectionSource.contains(".accessibilityLabel(activeTimerActionTitle)") == false)
        #expect(timerSource.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(timelineSource.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(forecastSource.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(forecastSource.contains("ForecastPresentationRow(item: item, task: $0)"))
        #expect(forecastSource.contains("if !rows.isEmpty"))
        #expect(forecastSource.contains("item.taskID != forecasts.last?.taskID") == false)
    }

    @Test
    func todayMetricsUseNeutralComparisonColorsAndSingleTodayAction() throws {
        let source = try [
            "timetracker/Features/Home/Sections/HomeMetricsViews.swift",
            "timetracker/Features/Home/Controls/HomeActionsViews.swift",
            "timetracker/SharedUI/Components/MetricCards.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
        let homeMetricsSource = try sourceText("timetracker/Features/Home/Sections/HomeMetricsViews.swift")
        let sharedMetricsSource = try sourceText("timetracker/SharedUI/Components/MetricCards.swift")
        let timerActionSource = try sourceText(
            "timetracker/Features/Home/Controls/HomeActionsViews.swift"
        )
        let timerPickerRowSource = try sourceText(
            "timetracker/Features/Home/Controls/TaskStartPickerRows.swift"
        )

        #expect(source.contains("trendColor: grossTrend.color"))
        #expect(source.contains(".foregroundStyle(metric.trendColor)"))
        #expect(homeMetricsSource.contains("home.metric.upFromYesterday\"), percent), .secondary"))
        #expect(homeMetricsSource.contains("home.metric.downFromYesterday\"), percent), .secondary"))
        #expect(homeMetricsSource.contains("), .red)") == false)
        #expect(sharedMetricsSource.contains("struct MetricCell"))
        #expect(sharedMetricsSource.contains("struct MetricSummaryItem"))
        #expect(homeMetricsSource.contains("struct MetricCell") == false)
        #expect(homeMetricsSource.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(homeMetricsSource.contains("verticalMetrics(metrics)"))
        #expect(source.contains("AppActionLabel(title: actionTitle"))
        #expect(timerActionSource.contains("store.timerPickerMode.title"))
        #expect(timerPickerRowSource.contains("case .switchTimer:"))
        #expect(timerPickerRowSource.contains("home.switchTimer"))
        #expect(source.contains("home.newTask") == false)
        #expect(source.contains(".layoutPriority(1.1)") == false)
    }

    @Test
    func desktopTodayUsesSharedPriorityAndBoundedWideLayout() throws {
        let source = try sourceText("timetracker/Features/Home/HomeViews.swift")

        let nowIndex = try #require(source.range(of: "ActiveTimersSection(")?.lowerBound)
        let overviewIndex = try #require(source.range(of: "TodayOverviewSection(")?.lowerBound)
        let quickStartIndex = try #require(source.range(of: "QuickStartSection(")?.lowerBound)
        let timelineIndex = try #require(source.range(of: "TimelineSection(")?.lowerBound)
        let forecastIndex = try #require(source.range(of: "TaskForecastSummarySection(")?.lowerBound)

        #expect(nowIndex < overviewIndex)
        #expect(overviewIndex < quickStartIndex)
        #expect(quickStartIndex < timelineIndex)
        #expect(timelineIndex < forecastIndex)
        #expect(source.contains("TodayHomeContent(store: store, quickStartLimit: 6)"))
        #expect(source.contains("layout.usesTwoColumnContent && content.hasSupportingContent"))
        #expect(source.contains(".frame(width: layout.contentWidth"))
        #expect(source.contains(".padding(.vertical, layout.pagePadding)"))
        #expect(source.contains(".padding(layout.pagePadding)") == false)
        #expect(source.contains("supportingColumnWidth"))
    }
}
