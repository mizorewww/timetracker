import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreRefactorTests {
    @Test @MainActor
    func deletingSelectedTaskPreservesCurrentDestination() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Delete in Tasks", parentID: nil, colorHex: nil, iconName: nil)
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        store.desktopDestination = .tasks
        store.selectTask(task.id, revealInToday: false)

        store.deleteSelectedTask(taskID: task.id)

        #expect(store.desktopDestination == .tasks)
        #expect(store.selectedTaskID == nil)
    }

    @Test @MainActor
    func taskPageDeleteCanPreserveTasksDestinationEvenAfterSelectionRevealedToday() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Delete from row", parentID: nil, colorHex: nil, iconName: nil)
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        store.desktopDestination = .today
        store.selectTask(task.id)

        store.deleteSelectedTask(taskID: task.id, preservingDestination: .tasks)

        #expect(store.desktopDestination == .tasks)
        #expect(store.selectedTaskID == nil)
    }

    @Test @MainActor
    func taskPageCreatePreservesTasksDestinationAfterSelectingNewTask() throws {
        let context = try makeTestContext()
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        store.desktopDestination = .tasks
        store.presentNewTask(preservingDestination: .tasks)
        var draft = try #require(store.taskEditorDraft)
        draft.title = "Created from Tasks"

        store.saveTaskDraft(draft)

        #expect(store.desktopDestination == .tasks)
        #expect(store.selectedTask?.title == "Created from Tasks")
        #expect(store.taskEditorDraft == nil)
        #expect(store.taskEditorReturnDestination == nil)
    }

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
    func ledgerBucketCacheSplitsLongSegmentsAcrossDayBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let taskID = UUID()
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 4, hour: 23)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 6, hour: 1)))
        let interval = DateInterval(
            start: calendar.startOfDay(for: start),
            end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        )
        let session = TimeSession(taskID: taskID, source: .timer, deviceID: "test", startedAt: start)
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: end
        )
        var cache = LedgerBucketCache()

        let summaries = cache.summaries(
            segments: [segment],
            interval: interval,
            now: end,
            calendar: calendar
        )

        #expect(summaries.map(\.grossSeconds) == [3_600, 86_400, 3_600])
        #expect(summaries.map(\.wallClockSeconds) == [3_600, 86_400, 3_600])
        #expect(cache.bucketCount == 3)
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
        let storeSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore.swift")

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

}
