import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreRefactorTests {
    @Test @MainActor
    func analyticsSnapshotCompactsDenseOverlapsWithSweepLine() {
        let start = Date(timeIntervalSince1970: 10_000)
        let tasks = (0..<5).map { index in
            TaskNode(
                title: "Task \(index)",
                parentID: nil,
                deviceID: "test",
                colorHex: nil,
                iconName: nil
            )
        }
        let sessions = tasks.map { task in
            TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: start, titleSnapshot: task.title)
        }
        let segments = zip(tasks, sessions).map { task, session in
            TimeSegment(
                sessionID: session.id,
                taskID: task.id,
                source: .timer,
                deviceID: "test",
                startedAt: start,
                endedAt: start.addingTimeInterval(3_600)
            )
        }

        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: tasks,
            segments: segments,
            sessions: sessions,
            taskPathByID: [:],
            taskParentPathByID: [:],
            now: start.addingTimeInterval(3_600)
        )

        #expect(snapshot.overview.grossSeconds == 18_000)
        #expect(snapshot.overview.wallSeconds == 3_600)
        #expect(snapshot.overlaps.count == 1)
        #expect(snapshot.overlaps.first?.durationSeconds == 3_600)
    }

    @Test @MainActor
    func ledgerVisibleRefreshDoesNotFetchFullHistory() throws {
        let repository = LedgerRefreshSpyRepository()
        var store = LedgerStore()

        try store.refreshVisible(repository: repository, now: Date(timeIntervalSince1970: 10_000))

        #expect(repository.activeSegmentsCallCount == 1)
        #expect(repository.pausedSessionsCallCount == 1)
        #expect(repository.rangeSegmentsCallCount == 1)
        #expect(repository.allSegmentsCallCount == 0)
        #expect(repository.sessionsCallCount == 0)
    }

    @Test @MainActor
    func analyticsStoreOwnsSnapshotCache() {
        let task = TaskNode(title: "Cached Task", parentID: nil, deviceID: "test")
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: Date(timeIntervalSince1970: 20_000), titleSnapshot: task.title)
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: session.startedAt,
            endedAt: session.startedAt.addingTimeInterval(600)
        )
        var store = AnalyticsStore()

        #expect(store.cachedSnapshot(for: .today) == nil)

        store.refreshSnapshot(
            range: .today,
            tasks: [task],
            segments: [segment],
            sessions: [session],
            taskPathByID: [task.id: task.title],
            taskParentPathByID: [:],
            now: session.startedAt.addingTimeInterval(900)
        )

        #expect(store.cachedSnapshot(for: .today)?.overview.grossSeconds == 600)
        #expect(store.cachedSnapshot(for: .today)?.taskBreakdown.first?.title == "Cached Task")
    }

    @Test @MainActor
    func dailySummaryServiceClipsCrossDaySegmentsIntoEachDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let taskID = UUID()
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 23, minute: 30)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 0, minute: 30)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 12)))
        let session = TimeSession(taskID: taskID, source: .timer, deviceID: "test", startedAt: start)
        let segment = TimeSegment(sessionID: session.id, taskID: taskID, source: .timer, deviceID: "test", startedAt: start, endedAt: end)

        let summaries = DailySummaryService().summaries(
            segments: [segment],
            interval: DateInterval(start: calendar.startOfDay(for: start), end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end),
            now: now,
            calendar: calendar
        )

        #expect(summaries.map(\.grossSeconds) == [1_800, 1_800])
        #expect(summaries.map(\.wallClockSeconds) == [1_800, 1_800])
        #expect(summaries.first?.taskID == nil)
    }

    @Test @MainActor
    func ledgerBucketCacheInvalidatesOnlyAffectedDayBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let taskID = UUID()
        let dayOne = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9)))
        let dayTwo = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 2, hour: 9)))
        let interval = DateInterval(
            start: calendar.startOfDay(for: dayOne),
            end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dayTwo)) ?? dayTwo
        )
        let firstSession = TimeSession(taskID: taskID, source: .timer, deviceID: "test", startedAt: dayOne)
        let secondSession = TimeSession(taskID: taskID, source: .timer, deviceID: "test", startedAt: dayTwo)
        let firstSegment = TimeSegment(
            sessionID: firstSession.id,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: dayOne,
            endedAt: dayOne.addingTimeInterval(600)
        )
        let secondSegment = TimeSegment(
            sessionID: secondSession.id,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: dayTwo,
            endedAt: dayTwo.addingTimeInterval(1_200)
        )
        var cache = LedgerBucketCache()

        let firstSummaries = cache.summaries(
            segments: [firstSegment, secondSegment],
            interval: interval,
            now: dayTwo.addingTimeInterval(2_000),
            calendar: calendar
        )
        #expect(firstSummaries.map(\.grossSeconds) == [600, 1_200])
        #expect(cache.bucketCount == 2)

        cache.invalidate(intervals: [
            DateInterval(start: calendar.startOfDay(for: dayTwo), duration: 24 * 60 * 60)
        ])
        #expect(cache.bucketCount == 1)

        let longerSecondSegment = TimeSegment(
            sessionID: secondSession.id,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: dayTwo,
            endedAt: dayTwo.addingTimeInterval(1_800)
        )
        let refreshedSummaries = cache.summaries(
            segments: [firstSegment, longerSecondSegment],
            interval: interval,
            now: dayTwo.addingTimeInterval(2_000),
            calendar: calendar
        )

        #expect(refreshedSummaries.map(\.grossSeconds) == [600, 1_800])
        #expect(cache.bucketCount == 2)
    }

    @Test @MainActor
    func analyticsStoreBuildsDailyPointsThroughLedgerBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let task = TaskNode(title: "Bucketed Analytics", parentID: nil, deviceID: "test")
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 3, hour: 10)))
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: start, titleSnapshot: task.title)
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(900)
        )
        var store = AnalyticsStore()

        let snapshot = store.refreshSnapshot(
            range: .month,
            tasks: [task],
            segments: [segment],
            sessions: [session],
            taskPathByID: [task.id: task.title],
            taskParentPathByID: [:],
            now: start,
            calendar: calendar
        )

        #expect(snapshot.daily.contains { $0.date == calendar.startOfDay(for: start) && $0.grossSeconds == 900 })
        #expect(store.ledgerBucketCount >= 1)
    }

    @Test @MainActor
    func rollupStoreOwnsForecastStateSeparatelyFromAnalyticsCache() {
        let task = TaskNode(title: "Rollup Task", parentID: nil, deviceID: "test")
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: Date(timeIntervalSince1970: 25_000), titleSnapshot: task.title)
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: session.startedAt,
            endedAt: session.startedAt.addingTimeInterval(900)
        )
        let checklist = [
            ChecklistItem(taskID: task.id, title: "Done", isCompleted: true, sortOrder: 0, deviceID: "test"),
            ChecklistItem(taskID: task.id, title: "Next", isCompleted: false, sortOrder: 1, deviceID: "test")
        ]
        var rollupStore = RollupStore()
        let analyticsStore = AnalyticsStore()

        rollupStore.refresh(tasks: [task], segments: [segment], checklistItems: checklist, now: session.startedAt.addingTimeInterval(1_000))

        #expect(rollupStore.rollup(for: task.id)?.workedSeconds == 900)
        #expect(rollupStore.checklistProgress(for: task.id, checklistItems: checklist).label == "1/2")
        #expect(analyticsStore.cachedSnapshot(for: .today) == nil)
    }

    @Test @MainActor
    func rollupStoreRefreshAffectedRecomputesImpactedBranchAndAncestors() throws {
        let start = Date(timeIntervalSince1970: 30_000)
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let changedChild = TaskNode(title: "Changed Child", parentID: parent.id, deviceID: "test")
        let untouchedChild = TaskNode(title: "Untouched Child", parentID: parent.id, deviceID: "test")
        let changedSession = TimeSession(taskID: changedChild.id, source: .timer, deviceID: "test", startedAt: start)
        let untouchedSession = TimeSession(taskID: untouchedChild.id, source: .timer, deviceID: "test", startedAt: start)
        let changedSegment = TimeSegment(
            sessionID: changedSession.id,
            taskID: changedChild.id,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(600)
        )
        let untouchedSegment = TimeSegment(
            sessionID: untouchedSession.id,
            taskID: untouchedChild.id,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(1_200)
        )
        let initialChecklist = [
            ChecklistItem(taskID: changedChild.id, title: "Done", isCompleted: true, sortOrder: 0, deviceID: "test"),
            ChecklistItem(taskID: changedChild.id, title: "Next", isCompleted: false, sortOrder: 1, deviceID: "test"),
            ChecklistItem(taskID: untouchedChild.id, title: "Done", isCompleted: true, sortOrder: 0, deviceID: "test"),
            ChecklistItem(taskID: untouchedChild.id, title: "Next", isCompleted: false, sortOrder: 1, deviceID: "test")
        ]
        var store = RollupStore()
        store.refresh(
            tasks: [parent, changedChild, untouchedChild],
            segments: [changedSegment, untouchedSegment],
            checklistItems: initialChecklist,
            now: start.addingTimeInterval(2_000)
        )

        let initialUntouched = try #require(store.rollup(for: untouchedChild.id))
        #expect(initialUntouched.workedSeconds == 1_200)
        #expect(store.rollup(for: parent.id)?.remainingSeconds == 1_800)

        let staleIfRecomputedSegment = TimeSegment(
            sessionID: untouchedSession.id,
            taskID: untouchedChild.id,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(7_200)
        )
        let updatedChecklist = initialChecklist + [
            ChecklistItem(taskID: changedChild.id, title: "Later", isCompleted: false, sortOrder: 2, deviceID: "test")
        ]

        store.refreshAffected(
            taskIDs: [changedChild.id],
            tasks: [parent, changedChild, untouchedChild],
            segments: [changedSegment, staleIfRecomputedSegment],
            checklistItems: updatedChecklist,
            now: start.addingTimeInterval(8_000)
        )

        #expect(store.rollup(for: changedChild.id)?.remainingSeconds == 1_200)
        #expect(store.rollup(for: untouchedChild.id) == initialUntouched)
        #expect(store.rollup(for: parent.id)?.remainingSeconds == 2_400)
    }

    @Test @MainActor
    func refreshPlannerMapsDomainEventsToDomainSizedScopes() {
        let planner = StoreRefreshPlanner()
        let taskID = UUID()
        let range = StoreInvalidationRange(start: Date(timeIntervalSince1970: 1), end: Date(timeIntervalSince1970: 2))

        #expect(planner.scopes(after: [.checklistChanged(taskID: taskID, affectedAncestorIDs: [])]) == [.checklist, .rollups, .analytics])
        #expect(planner.scopes(after: [.taskChanged(taskID: taskID, affectedAncestorIDs: [])]) == [.tasks, .rollups, .analytics, .liveActivities])
        #expect(planner.scopes(after: [.ledgerChanged(taskID: taskID, dateInterval: range, isVisible: true)]) == [.ledgerVisible, .pomodoro, .rollups, .analytics, .liveActivities])
        #expect(planner.scopes(after: [.pomodoroChanged(runID: nil, sessionID: nil, taskID: taskID)]) == [.ledgerVisible, .pomodoro, .rollups, .analytics, .liveActivities])
        #expect(planner.scopes(after: [.ledgerChanged(taskID: taskID, dateInterval: range, isVisible: false)]) == [.ledgerHistory, .rollups, .analytics, .liveActivities])
        #expect(planner.scopes(after: [.preferenceChanged(key: AppPreferenceKey.quickStartTaskIDs.rawValue)]) == [.preferences])
        #expect(planner.scopes(after: [.fullSync]) == StoreRefreshScope.full)
        #expect(planner.scopes(after: [.remoteImportCompleted]) == StoreRefreshScope.full)
        #expect(StoreDomainEvent.checklistChanged(taskID: taskID, affectedAncestorIDs: []).affectedTaskIDs == [taskID])
    }

    @Test @MainActor
    func refreshPlannerCoalescesMultipleDomainEventsWithoutEscalatingToFullRefresh() {
        let taskID = UUID()
        let scopes = StoreRefreshPlanner().scopes(after: [
            .taskChanged(taskID: taskID, affectedAncestorIDs: []),
            .checklistChanged(taskID: taskID, affectedAncestorIDs: []),
            .ledgerChanged(taskID: taskID, dateInterval: nil, isVisible: true)
        ])

        #expect(scopes.contains(.tasks))
        #expect(scopes.contains(.checklist))
        #expect(scopes.contains(.ledgerVisible))
        #expect(scopes.contains(.rollups))
        #expect(scopes.contains(.analytics))
        #expect(scopes.contains(.preferences) == false)
        #expect(scopes != StoreRefreshScope.full)
    }

    @Test @MainActor
    func refreshPlanCentralizesDerivedRefreshRules() {
        let planner = StoreRefreshPlanner()
        let taskID = UUID()
        let ancestorID = UUID()

        let checklistPlan = planner.plan(after: [.checklistChanged(taskID: taskID, affectedAncestorIDs: [ancestorID])])
        #expect(checklistPlan.affectedTaskIDs == [taskID, ancestorID])
        #expect(checklistPlan.affectedLedgerRanges.isEmpty)
        #expect(checklistPlan.refreshChecklist)
        #expect(checklistPlan.refreshRollups)
        #expect(checklistPlan.refreshAnalytics)
        #expect(checklistPlan.refreshLedger == false)
        #expect(checklistPlan.syncLiveActivities == false)

        let timerPlan = planner.plan(after: [.ledgerChanged(taskID: taskID, dateInterval: nil, isVisible: true)])
        #expect(timerPlan.refreshLedger)
        #expect(timerPlan.includeLedgerHistory == false)
        #expect(timerPlan.refreshPomodoro)
        #expect(timerPlan.refreshRollups)
        #expect(timerPlan.refreshAnalytics)
        #expect(timerPlan.syncLiveActivities)

        let range = StoreInvalidationRange(start: Date(timeIntervalSince1970: 1), end: Date(timeIntervalSince1970: 2))
        let historyPlan = planner.plan(after: [
            .ledgerChanged(
                taskID: taskID,
                dateInterval: range,
                isVisible: false
            )
        ])
        #expect(historyPlan.affectedTaskIDs == [taskID])
        #expect(historyPlan.affectedLedgerRanges == [range])
        #expect(historyPlan.refreshLedger)
        #expect(historyPlan.includeLedgerHistory)
        #expect(historyPlan.validateSelection)
    }

    @Test @MainActor
    func checklistCommandHandlerOwnsAddAndToggleSemantics() throws {
        let context = try makeContext()
        let task = TaskNode(title: "Command Task", parentID: nil, deviceID: "test")
        context.insert(task)
        try context.save()

        let handler = ChecklistCommandHandler()
        let firstResult = try handler.add(taskID: task.id, title: " First ", existingItems: [], context: context, deviceID: "test")
        let first = try #require(firstResult)
        let secondResult = try handler.add(taskID: task.id, title: "Second", existingItems: [first], context: context, deviceID: "test")
        let second = try #require(secondResult)
        let blank = try handler.add(taskID: task.id, title: "   ", existingItems: [first, second], context: context, deviceID: "test")

        #expect(blank == nil)
        #expect(first.title == "First")
        #expect(second.sortOrder > first.sortOrder)

        try handler.toggle(first, context: context, now: Date(timeIntervalSince1970: 1_000))
        #expect(first.isCompleted)
        #expect(first.completedAt == Date(timeIntervalSince1970: 1_000))

        try handler.toggle(first, context: context, now: Date(timeIntervalSince1970: 2_000))
        #expect(first.isCompleted == false)
        #expect(first.completedAt == nil)
    }

    @Test @MainActor
    func timerCommandHandlerCoordinatesLedgerAndParallelTimerPolicy() throws {
        let context = try makeContext()
        let repository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTaskID = UUID()
        let secondTaskID = UUID()
        let firstSegment = try repository.startTask(taskID: firstTaskID, source: .timer)

        try TimerCommandHandler().startTask(
            taskID: secondTaskID,
            allowParallelTimers: false,
            activeSegments: [firstSegment],
            pausedSessions: [],
            pomodoroRuns: [],
            timeRepository: repository,
            context: context
        )

        let activeSegments = try repository.activeSegments()
        #expect(firstSegment.endedAt != nil)
        #expect(activeSegments.count == 1)
        #expect(activeSegments.first?.taskID == secondTaskID)
    }

    @Test @MainActor
    func pomodoroCommandHandlerOwnsTimerStateTransitions() throws {
        let context = try makeContext()
        let sessionID = UUID()
        let run = PomodoroRun(taskID: UUID(), deviceID: "test")
        run.sessionID = sessionID
        run.state = .focusing
        context.insert(run)
        try context.save()

        let handler = PomodoroCommandHandler()
        let interruptedAt = Date(timeIntervalSince1970: 1_000)
        try handler.interruptIfNeeded(sessionID: sessionID, runs: [run], context: context, now: interruptedAt)
        #expect(run.state == .interrupted)
        #expect(run.updatedAt == interruptedAt)

        let resumedAt = Date(timeIntervalSince1970: 2_000)
        try handler.resumeIfNeeded(sessionID: sessionID, runs: [run], context: context, now: resumedAt)
        #expect(run.state == .focusing)
        #expect(run.updatedAt == resumedAt)

        let cancelledAt = Date(timeIntervalSince1970: 3_000)
        try handler.cancelIfNeeded(sessionID: sessionID, runs: [run], context: context, now: cancelledAt)
        #expect(run.state == .cancelled)
        #expect(run.endedAt == cancelledAt)
    }

    @Test @MainActor
    func ledgerCommandHandlerOwnsManualSegmentWrites() throws {
        let context = try makeContext()
        let repository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = TaskNode(title: "Ledger Task", parentID: nil, deviceID: "test")
        var draft = ManualTimeDraft(taskID: task.id, tasks: [task])
        draft.startedAt = Date(timeIntervalSince1970: 10_000)
        draft.endedAt = draft.startedAt.addingTimeInterval(1_200)
        draft.note = "   "

        let segment = try LedgerCommandHandler().addManualTime(draft: draft, taskID: task.id, repository: repository)
        let session = try #require(try repository.sessions().first { $0.id == segment.sessionID })

        #expect(segment.taskID == task.id)
        #expect(session.note == "Manual")

        var editDraft = SegmentEditorDraft(segment: segment, note: " Updated ")
        editDraft.isActive = true
        try LedgerCommandHandler().updateSegment(draft: editDraft, taskID: task.id, repository: repository)
        #expect(segment.endedAt == nil)
        #expect(session.note == "Updated")

        try LedgerCommandHandler().softDeleteSegment(segment.id, repository: repository)
        #expect(segment.deletedAt != nil)
    }

    @Test @MainActor
    func countdownCommandHandlerOwnsCountdownWrites() throws {
        let context = try makeContext()
        let handler = CountdownCommandHandler()
        let event = try handler.add(context: context, deviceID: "test")
        let date = Date(timeIntervalSince1970: 50_000)

        try handler.update(event, title: "Ship", date: date, context: context, now: Date(timeIntervalSince1970: 40_000))
        #expect(event.title == "Ship")
        #expect(event.date == date)
        #expect(event.updatedAt == Date(timeIntervalSince1970: 40_000))

        try handler.softDelete(event, context: context, now: Date(timeIntervalSince1970: 60_000))
        #expect(event.deletedAt == Date(timeIntervalSince1970: 60_000))
    }

    @Test @MainActor
    func csvExportServiceEscapesRowsAndUsesSessionFallbackForDeletedTasks() {
        let taskID = UUID()
        let session = TimeSession(
            taskID: taskID,
            source: .manual,
            deviceID: "test",
            startedAt: Date(timeIntervalSince1970: 30_000),
            titleSnapshot: "Deleted, Task"
        )
        session.endedAt = session.startedAt.addingTimeInterval(120)
        session.note = "Said \"hello\""
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .manual,
            deviceID: "test",
            startedAt: session.startedAt,
            endedAt: session.endedAt
        )

        let csv = CSVExportService().export(
            segments: [segment],
            sessions: [session],
            taskByID: [:],
            taskParentPathByID: [:],
            now: session.endedAt ?? session.startedAt
        )

        #expect(csv.contains("\"Deleted, Task\""))
        #expect(csv.contains(AppStrings.localized("task.deleted.path")))
        #expect(csv.contains("\"Said \"\"hello\"\"\""))
    }

    @Test
    func sidebarUsesSharedFlatTaskTreeContract() throws {
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarInspectorViews.swift")

        #expect(sidebarSource.contains("store.taskTreeRows(expandedTaskIDs: expansionState.expandedTaskIDs)"))
        #expect(sidebarSource.contains("DisclosureGroup(") == false)
    }

    @Test
    func enumDisplayTextUsesLocalizationKeys() throws {
        #expect(AnalyticsRange.today.displayName == AppStrings.localized("analytics.range.today"))
        #expect(TimeSessionSource.importCalendar.displayName == AppStrings.localized("source.calendar"))

        let analyticsSource = try sourceText("timetracker/Features/Analytics/AnalyticsViews.swift")
        let storeSource = try sourceText("timetracker/Stores/TimeTrackerStore.swift")

        #expect(analyticsSource.contains("Text(range.rawValue)") == false)
        #expect(storeSource.contains("return \"Ready\"") == false)
        #expect(storeSource.contains("return \"Focus\"") == false)
    }

    @Test @MainActor
    func layoutPoliciesCentralizeResponsiveChoices() {
        #expect(HomeLayoutPolicy(width: 600).isCompact)
        #expect(HomeLayoutPolicy(width: 900).usesHorizontalMetrics)
        #expect(AnalyticsLayoutPolicy(horizontalSizeClass: nil).showsPageTitleInContent)
        #expect(SplitColumnLayoutPolicy.iPad.inspector == ColumnWidth(min: 240, ideal: 260, max: 320))
        #expect(SplitColumnLayoutPolicy.mac.sidebar == ColumnWidth(min: 220, ideal: 240, max: 270))
    }

    @Test @MainActor
    func taskTreeFlatteningStaysWithinPerformanceBudget() {
        let roots = (0..<500).map { index in
            TaskNode(title: "Root \(index)", parentID: nil, deviceID: "test")
        }
        let children = roots.enumerated().map { index, root in
            TaskNode(title: "Child \(index)", parentID: root.id, deviceID: "test")
        }
        let childrenByParent = Dictionary(grouping: children) { $0.parentID }
        let expandedIDs = Set(roots.map(\.id))

        let start = CFAbsoluteTimeGetCurrent()
        let rows = TaskTreeFlattener.visibleRows(
            rootTasks: roots,
            children: { task in childrenByParent[Optional(task.id)] ?? [] },
            expandedTaskIDs: expandedIDs
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(rows.count == 1_000)
        #expect(elapsed < 2.0)
    }

    @Test @MainActor
    func analyticsSnapshotStaysWithinPerformanceBudget() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 8)) ?? Date(timeIntervalSince1970: 1_775_000_000)
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 16, hour: 12)) ?? startDate.addingTimeInterval(15 * 24 * 60 * 60)
        let tasks = (0..<40).map { index in
            TaskNode(title: "Analytics Task \(index)", parentID: nil, deviceID: "test")
        }
        let sessions = (0..<720).map { index in
            TimeSession(
                taskID: tasks[index % tasks.count].id,
                source: .timer,
                deviceID: "test",
                startedAt: startDate.addingTimeInterval(Double(index * 1_800)),
                titleSnapshot: tasks[index % tasks.count].title
            )
        }
        let segments = sessions.enumerated().map { index, session in
            TimeSegment(
                sessionID: session.id,
                taskID: session.taskID,
                source: .timer,
                deviceID: "test",
                startedAt: session.startedAt,
                endedAt: session.startedAt.addingTimeInterval(Double(600 + (index % 12) * 60))
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        let snapshot = AnalyticsStore().snapshot(
            range: .month,
            tasks: tasks,
            segments: segments,
            sessions: sessions,
            taskPathByID: Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.title) }),
            taskParentPathByID: [:],
            now: now,
            calendar: calendar
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(snapshot.daily.isEmpty == false)
        #expect(snapshot.taskBreakdown.isEmpty == false)
        #expect(elapsed < 3.0)
    }

    @Test @MainActor
    func affectedRollupRefreshStaysWithinPerformanceBudget() throws {
        let parent = TaskNode(title: "Budget Parent", parentID: nil, deviceID: "test")
        let children = (0..<500).map { index in
            TaskNode(title: "Budget Child \(index)", parentID: parent.id, deviceID: "test")
        }
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let sessions = children.map { child in
            TimeSession(taskID: child.id, source: .timer, deviceID: "test", startedAt: startDate)
        }
        let segments = zip(children.indices, sessions).map { index, session in
            TimeSegment(
                sessionID: session.id,
                taskID: session.taskID,
                source: .timer,
                deviceID: "test",
                startedAt: startDate,
                endedAt: startDate.addingTimeInterval(600 + Double(index % 10) * 60)
            )
        }
        var store = RollupStore()
        let tasks = [parent] + children
        store.refresh(tasks: tasks, segments: segments, checklistItems: [], now: startDate.addingTimeInterval(7_200))

        let changedChild = try #require(children.first)
        let start = CFAbsoluteTimeGetCurrent()
        store.refreshAffected(
            taskIDs: [changedChild.id],
            tasks: tasks,
            segments: segments,
            checklistItems: [],
            now: startDate.addingTimeInterval(7_200)
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(store.rollup(for: parent.id)?.workedSeconds ?? 0 > 0)
        #expect(elapsed < 2.0)
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = TimeTrackerModelRegistry.currentSchema
        let configuration = ModelConfiguration(
            "CoreRefactorTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
        return ModelContext(container)
    }
}

private final class LedgerRefreshSpyRepository: TimeTrackingRepository {
    var activeSegmentsCallCount = 0
    var pausedSessionsCallCount = 0
    var rangeSegmentsCallCount = 0
    var allSegmentsCallCount = 0
    var sessionsCallCount = 0

    func activeSegments() throws -> [TimeSegment] {
        activeSegmentsCallCount += 1
        return []
    }

    func pausedSessions() throws -> [TimeSession] {
        pausedSessionsCallCount += 1
        return []
    }

    func sessions() throws -> [TimeSession] {
        sessionsCallCount += 1
        return []
    }

    func segments(from: Date, to: Date) throws -> [TimeSegment] {
        try segments(from: from, to: to, now: Date())
    }

    func segments(from: Date, to: Date, now: Date) throws -> [TimeSegment] {
        rangeSegmentsCallCount += 1
        return []
    }

    func allSegments() throws -> [TimeSegment] {
        allSegmentsCallCount += 1
        return []
    }

    func startTask(taskID: UUID, source: TimeSessionSource) throws -> TimeSegment {
        fatalError("Unused in LedgerRefreshSpyRepository")
    }

    func stopSegment(segmentID: UUID) throws {}

    func updateSegment(segmentID: UUID, taskID: UUID, startedAt: Date, endedAt: Date?, note: String?) throws {}

    func softDeleteSegment(segmentID: UUID) throws {}

    func stopSession(sessionID: UUID) throws {}

    func pauseSession(sessionID: UUID) throws {}

    func resumeSession(sessionID: UUID) throws -> TimeSegment? {
        nil
    }

    func addManualSegment(taskID: UUID, startedAt: Date, endedAt: Date, note: String?) throws -> TimeSegment {
        fatalError("Unused in LedgerRefreshSpyRepository")
    }
}
