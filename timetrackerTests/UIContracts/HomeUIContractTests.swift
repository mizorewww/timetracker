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
        let start = try #require(
            source.range(of: "func todayMetricsSnapshot")?.lowerBound
        )
        let end = try #require(
            source.range(of: "func weeklyGrossTimeSnapshot")?.lowerBound
        )
        let todayMetricsSource = String(source[start..<end])

        #expect(todayMetricsSource.components(separatedBy: ".visibleDeduplicatedByID()").count - 1 == 1)
        #expect(todayMetricsSource.components(separatedBy: "for segment in segments").count - 1 == 1)
        #expect(todayMetricsSource.components(separatedBy: "visibleSegments(overlapping:").count - 1 == 1)
        #expect(todayMetricsSource.contains("ledgerSummaryService.secondsInInterval") == false)
    }

    @Test @MainActor
    func weeklyGrossTimeUsesCalendarDaysAndGrossOverlapSemantics() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 9,
            hour: 12
        )))
        let week = try #require(
            calendar.dateInterval(of: .weekOfYear, for: now)
        )
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test"
        )
        let task = try taskRepository.createTask(
            title: "Weekly",
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
            start: week.start.addingTimeInterval(-1_800),
            end: week.start.addingTimeInterval(1_800)
        )
        try addSegment(
            start: week.start.addingTimeInterval(9 * 3_600),
            end: week.start.addingTimeInterval(10 * 3_600)
        )
        try addSegment(
            start: week.start.addingTimeInterval(9.5 * 3_600),
            end: week.start.addingTimeInterval(10.5 * 3_600)
        )
        let wednesday = try #require(
            calendar.date(byAdding: .day, value: 2, to: week.start)
        )
        try addSegment(
            start: wednesday.addingTimeInterval(23.5 * 3_600),
            end: wednesday.addingTimeInterval(24.5 * 3_600)
        )
        try addSegment(
            start: now.addingTimeInterval(-2 * 3_600),
            end: now.addingTimeInterval(3_600)
        )
        let friday = try #require(
            calendar.date(byAdding: .day, value: 4, to: week.start)
        )
        try addSegment(
            start: friday.addingTimeInterval(10 * 3_600),
            end: friday.addingTimeInterval(11 * 3_600)
        )

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        let snapshot = store.weeklyGrossTimeSnapshot(
            now: now,
            calendar: calendar
        )

        #expect(snapshot.interval == week)
        #expect(snapshot.daily.count == 4)
        #expect(snapshot.daily.map(\.grossSeconds) == [9_000, 0, 1_800, 9_000])
        #expect(snapshot.daily.map(\.wallSeconds) == [7_200, 0, 1_800, 9_000])
        #expect(snapshot.totalGrossSeconds == 19_800)
        #expect(snapshot.hasTrackedTime)
        #expect(snapshot.requiresLiveRefresh)
    }

    @Test @MainActor
    func weeklyGrossTimeReevaluatesAClosedFutureEndAtEachCutoff() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 8,
            hour: 10
        )))
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test"
        )
        let task = try taskRepository.createTask(
            title: "Clock skew",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600),
            note: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        let first = store.weeklyGrossTimeSnapshot(
            now: start.addingTimeInterval(600),
            calendar: calendar
        )
        let second = store.weeklyGrossTimeSnapshot(
            now: start.addingTimeInterval(1_200),
            calendar: calendar
        )

        #expect(first.totalGrossSeconds == 600)
        #expect(second.totalGrossSeconds == 1_200)
        #expect(first.requiresLiveRefresh)
        #expect(second.requiresLiveRefresh)
    }

    @Test @MainActor
    func weeklyGrossTimeRefreshesAcrossFutureStartAndClockRewindBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 8,
            hour: 10
        )))
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test"
        )
        let task = try taskRepository.createTask(
            title: "Future import",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600),
            note: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let beforeDate = start.addingTimeInterval(-600)
        let duringDate = start.addingTimeInterval(600)
        let afterDate = start.addingTimeInterval(4_200)

        let before = store.weeklyGrossTimeSnapshot(
            now: beforeDate,
            calendar: calendar
        )
        let during = store.weeklyGrossTimeSnapshot(
            now: duringDate,
            calendar: calendar
        )
        let after = store.weeklyGrossTimeSnapshot(
            now: afterDate,
            calendar: calendar
        )
        let waitingRequest = HomeWeeklyGrossTimeRefreshRequest(
            store: store,
            snapshot: before,
            now: beforeDate,
            clockRevision: 0,
            calendar: calendar
        )
        let settledRequest = HomeWeeklyGrossTimeRefreshRequest(
            store: store,
            snapshot: after,
            now: afterDate,
            clockRevision: 0,
            calendar: calendar
        )
        let rewoundRequest = HomeWeeklyGrossTimeRefreshRequest(
            store: store,
            snapshot: after,
            now: beforeDate,
            clockRevision: 1,
            calendar: calendar
        )

        #expect(before.totalGrossSeconds == 0)
        #expect(before.requiresLiveRefresh)
        #expect(waitingRequest.evaluationKey.liveRefreshBucket != nil)
        #expect(during.totalGrossSeconds == 600)
        #expect(during.requiresLiveRefresh)
        #expect(after.totalGrossSeconds == 3_600)
        #expect(after.requiresLiveRefresh == false)
        #expect(settledRequest.evaluationKey.liveRefreshBucket == nil)
        #expect(rewoundRequest != settledRequest)
    }

    @Test
    func todayAndAnalyticsShareTheDailyTimeSeriesChart() throws {
        let chartSource = try sourceText(
            "timetracker/SharedUI/Components/DailyTimeSeriesChart.swift"
        )
        let homeSource = try [
            "timetracker/Features/Home/HomeReadModels.swift",
            "timetracker/Features/Home/Sections/HomeWeeklyGrossTimeChart.swift",
            "timetracker/Features/Home/Sections/HomeWeeklyGrossTimeRefresh.swift",
            "timetracker/Features/Home/Sections/HomeWeeklyGrossTimeViews.swift",
            "timetracker/Features/Home/HomeViews.swift",
            "timetracker/Features/Home/PhoneHomeView.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
        let analyticsSource = try sourceText(
            "timetracker/Features/Analytics/Sections/AnalyticsTrendViews.swift"
        )
        let metricSources = try [
            "timetracker/Features/Home/Sections/HomeMetricsViews.swift",
            "timetracker/Features/Home/PhoneHomeRows.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailOverviewViews.swift",
            "timetracker/Features/Analytics/AnalyticsMetricListViews.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")

        #expect(chartSource.contains("import Charts"))
        #expect(chartSource.contains("struct DailyTimeSeriesChart: View"))
        #expect(chartSource.contains("case grossBars"))
        #expect(chartSource.contains("case wallBarsAndGrossLine"))
        #expect(chartSource.contains("BarMark("))
        #expect(chartSource.contains("point.date"))
        #expect(chartSource.contains("AxisMarks(values: .stride(by: .day))"))
        #expect(chartSource.contains("endPadding: trailingAxisClearance"))
        #expect(chartSource.contains(".automatic(includesZero: true)"))
        #expect(chartSource.contains("DurationFormatter.spoken"))
        #expect(homeSource.contains("analyticsDomainStore.dailyBreakdown("))
        #expect(homeSource.contains(".visibleDeduplicatedByID()"))
        #expect(homeSource.contains("allSegments") == false)
        #expect(homeSource.components(separatedBy: "HomeWeeklyGrossTimeSection(").count - 1 == 2)
        #expect(homeSource.contains("mode: .grossBars"))
        #expect(homeSource.contains("home.weeklyGross.chart"))
        #expect(homeSource.contains(".accessibilityElement(children: .contain)"))
        #expect(homeSource.contains("HomeWeeklyGrossTimeRefreshRequest"))
        #expect(homeSource.contains("AnalyticsEvaluationCacheKey("))
        #expect(homeSource.contains("let liveRefreshBucket = needsLiveRefresh"))
        #expect(homeSource.contains("clockRevision"))
        #expect(analyticsSource.contains("DailyTimeSeriesChart("))
        #expect(analyticsSource.contains("mode: .wallBarsAndGrossLine"))
        #expect(analyticsSource.contains("import Charts") == false)
        #expect(analyticsSource.contains("BarMark(") == false)
        #expect(metricSources.components(separatedBy: "AppColors.grossTime").count - 1 == 4)
        #expect(metricSources.components(separatedBy: "AppColors.wallTime").count - 1 == 4)
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
        let source = try [
            "timetracker/App/RootViews/iOSRootViews.swift",
            "timetracker/App/RootViews/iPadRootView.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
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
        #expect(homeSource.contains("QuickStartTaskGroup("))
        #expect(homeSource.contains("openTask: openTask"))
        #expect(homeSource.contains("HomeTimerTaskRow("))
        #expect(homeSource.contains("QuickStartTaskButton") == false)
        #expect(homeSource.contains("dynamicTypeSize.isAccessibilitySize ? 360 : 300"))
        #expect(homeSource.contains("private let maxPinnedTasks = 3") == false)
        #expect(homeSource.contains("QuickStartEditorTaskRow"))
        #expect(homeSource.contains("QuickStartPinnedTaskRow") == false)
        #expect(homeSource.contains("QuickStartSelectableTaskRow") == false)
        #expect(homeSource.contains("OrderedTaskIDSelectionMutation.adding("))
        #expect(homeSource.contains("!selectedIDSet.contains($0.id)"))
        #expect(homeSource.contains("OrderedTaskIDSelectionMutation.removingVisibleSelections("))
        #expect(homeSource.contains("visibleIDs: pinnedTasks.map(\\.id)"))
        #expect(homeSource.contains("selectedIDs.remove(atOffsets: offsets)") == false)
        #expect(storeSource.contains("func frequentRecentTasks(excluding excludedIDs: Set<UUID> = [], limit: Int = 3)"))
    }

    @Test
    func quickStartEditorMovesRowsBetweenExclusiveAnimatedSections() throws {
        let source = try sourceText(
            "timetracker/Features/Home/Sections/HomeQuickStartEditorViews.swift"
        )

        #expect(source.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(source.contains("withAnimation(reduceMotion ? nil : .snappy(duration: 0.28))"))
        #expect(source.contains("quickStart.availableTasks"))
        #expect(source.contains("TaskIdentityRow(presentation: presentation)"))
        #expect(source.contains(".accessibilityIdentifier(\"quickStart.editor\")"))
        #expect(source.contains("quickStart.editor.available."))
        #expect(source.contains("quickStart.editor.pinned."))
        #expect(source.contains(".accessibilityAddTraits(.isSelected)"))
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
        let timerRowSource = try sourceText(
            "timetracker/Features/Home/Rows/HomeTimerRows.swift"
        )
        let timerActionSource = try sourceText(
            "timetracker/SharedUI/Components/TaskTimerActionButton.swift"
        )

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
        #expect(identitySource.contains("taskBreadcrumbByID[taskID]"))
        #expect(quickStartSource.components(separatedBy: "HomeTimerTaskRow(").count - 1 == 2)
        #expect(quickStartSource.contains("PhoneQuickStartRow") == false)
        #expect(quickStartSource.contains("RunningStatusBadge()") == false)
        #expect(quickStartSource.contains("struct QuickStartTimerAction") == false)
        #expect(timerRowSource.contains("TaskIcon(visual: presentation.visual"))
        #expect(timerRowSource.contains("Button(action: openTask)"))
        #expect(timerRowSource.contains("HomeTimerTaskPathText"))
        #expect(timerRowSource.contains("ViewThatFits(in: .horizontal)"))
        #expect(quickStartSource.contains("home.quickStart.timer."))
        #expect(quickStartSource.contains("performTimerPickerSelection(task)"))
        #expect(quickStartSource.contains("store.stop(segment: activeSegment)"))
        #expect(timerRowSource.contains("TaskTimerActionButton("))
        #expect(timerActionSource.contains("stop.fill"))
        #expect(quickStartSource.contains("openTask(task.id)"))
        #expect(quickStartSource.contains("store.openTaskDetail(task.id)") == false)
        #expect(quickStartSource.contains("store.path(for: task)") == false)
        #expect(quickStartSource.contains("Text(path)") == false)
        #expect(timerActionSource.contains("enum TaskTimerActionLabelStyle"))
        #expect(timerActionSource.contains("labelStyle == .iconOnly"))
        #expect(timerRowSource.contains("horizontalSizeClass") == false)
        #expect(quickStartSource.contains("actionLabelStyle: .iconOnly"))
        #expect(quickStartSource.contains("actionLabelStyle: .titleAndIcon"))
        #expect(timerActionSource.contains("AppStrings.localized(\"timer.action.stop\")"))
        #expect(timerActionSource.contains(".buttonBorderShape(usesIconOnly ? .circle : .capsule)"))
        #expect(timerActionSource.contains("width: minimumLabelDimension"))
        #expect(timerActionSource.contains(".controlSize(platformControlSize)"))
    }

    @Test
    func todayTaskNavigationIsSharedAcrossPlatformsAndEntryPoints() throws {
        let homeSource = try [
            "timetracker/Features/Home/HomeViews.swift",
            "timetracker/Features/Home/Sections/HomeTimelineViews.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartViews.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartButtons.swift",
            "timetracker/Features/Home/Sections/HomeForecastViews.swift"
        ]
            .map(sourceText)
            .joined(separator: "\n")
        let phoneRoot = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")
        let navigation = try sourceText(
            "timetracker/Features/Home/TodayTaskNavigation.swift"
        )

        #expect(homeSource.contains("@State private var todayTaskRoute: TasksRoute?"))
        #expect(homeSource.contains("todayTaskRoute = store.prepareTaskDetailRoute(taskID)"))
        #expect(homeSource.components(separatedBy: "openTask: openTask").count - 1 >= 5)
        #expect(phoneRoot.contains(".todayTaskNavigationDestination("))
        #expect(homeSource.contains(".todayTaskNavigationDestination("))
        #expect(navigation.contains("TaskDetailView("))
        #expect(navigation.contains("returnDestination: .today"))
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
            "timetracker/SharedUI/Components/TimelineChartLayout.swift",
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
        #expect(sharedSource.contains("TimelineChartLayout.horizontalLanes("))
        #expect(sharedSource.contains("TimelineChartLayout.verticalLanes("))
        #expect(sharedSource.contains("TimelineChartLayout.axisTicks("))
        #expect(sharedSource.contains("tick.role.isBoundary"))
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
        let source = try [
            "timetracker/SharedUI/Components/TaskHierarchyPicker.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerSheet.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")

        #expect(source.contains(".presentationBackground(") == false)
        #expect(source.contains(".scrollContentBackground(.hidden)"))
        #expect(source.contains("struct TaskHierarchyPickerSheet"))
        #expect(source.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(source.contains("[.medium, .large]"))
    }

    @Test
    func trackingEntrypointsShareAvailabilityAndRunningStateSemantics() throws {
        let source = try [
            "timetracker/Features/Home/HomeReadModels.swift",
            "timetracker/Features/Home/PhoneHomeView.swift",
            "timetracker/Features/Home/PhoneHomeRows.swift",
            "timetracker/Features/Home/PhoneHomeSections.swift",
            "timetracker/Features/Home/Controls/HomeActionsViews.swift",
            "timetracker/Features/Home/Rows/HomeTimerRows.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartViews.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartButtons.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartEditorViews.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroFocusSetupControls.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupEmptyState.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupSelectionViews.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupViews.swift",
            "timetracker/Features/Pomodoro/Sections/PomodoroTimerFace.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPicker.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerRows.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerBehavior.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerPresentation.swift",
            "timetracker/SharedUI/Components/TimerPickerPresentation.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerSheet.swift",
            "timetracker/SharedUI/Components/TaskHierarchyProjection.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")

        #expect(source.components(separatedBy: "isTaskAvailableForTracking").count >= 8)
        #expect(source.contains("let activeSegment = store.activeSegment(for: task.id)"))
        #expect(source.contains("store.stop(segment: activeSegment)"))
        #expect(source.contains("HomeTimerTaskRow"))
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
        let weeklyIndex = try #require(homeSource.range(of: "HomeWeeklyGrossTimeSection(")?.lowerBound)
        let quickStartIndex = try #require(homeSource.range(of: "PhoneQuickStartSection(")?.lowerBound)
        let timelineIndex = try #require(homeSource.range(of: "PhoneTimelineSection(")?.lowerBound)
        let forecastIndex = try #require(homeSource.range(of: "PhoneForecastSection(")?.lowerBound)

        #expect(nowIndex < overviewIndex)
        #expect(overviewIndex < weeklyIndex)
        #expect(weeklyIndex < quickStartIndex)
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
        let timerPickerRowSource = try [
            "timetracker/SharedUI/Components/TaskHierarchyPickerRows.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerPresentation.swift",
            "timetracker/SharedUI/Components/TimerPickerPresentation.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")

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

        let currentStateIndex = try #require(
            source.range(of: "DesktopTodayCurrentStateSections(")?.lowerBound
        )
        let weeklyIndex = try #require(source.range(of: "HomeWeeklyGrossTimeSection(")?.lowerBound)
        let quickStartIndex = try #require(source.range(of: "QuickStartSection(")?.lowerBound)
        let timelineIndex = try #require(source.range(of: "TimelineSection(")?.lowerBound)
        let forecastIndex = try #require(source.range(of: "TaskForecastSummarySection(")?.lowerBound)

        #expect(currentStateIndex < weeklyIndex)
        #expect(weeklyIndex < quickStartIndex)
        #expect(quickStartIndex < timelineIndex)
        #expect(timelineIndex < forecastIndex)
        #expect(source.contains("TodayHomeContent(store: store, quickStartLimit: 6)"))
        #expect(source.contains("struct DesktopTodayCurrentStateSections: View"))
        #expect(
            source.components(separatedBy: "ActiveTimersSection(").count - 1 == 1
        )
        #expect(
            source.components(separatedBy: "TodayOverviewSection(").count - 1 == 1
        )
        #expect(source.contains("usesSideBySideCurrentState("))
        #expect(source.contains("prefersSingleColumn: dynamicTypeSize.isAccessibilitySize"))
        #expect(source.contains("HStack(alignment: .top, spacing: layout.contentSpacing)"))
        #expect(source.contains("layout.currentStatePrimaryColumnWidth"))
        #expect(source.contains("layout.currentStateOverviewColumnWidth"))
        #expect(source.contains("maxHeight: .infinity") == false)
        #expect(source.contains("layout.usesTwoColumnContent && content.hasSupportingContent"))
        #expect(source.contains(".frame(width: layout.contentWidth"))
        #expect(source.contains(".padding(.vertical, layout.pagePadding)"))
        #expect(source.contains(".padding(layout.pagePadding)") == false)
        #expect(source.contains("supportingColumnWidth"))
    }
}
