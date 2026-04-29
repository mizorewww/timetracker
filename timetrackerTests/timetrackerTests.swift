import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct TimeTrackerTests {
    @Test @MainActor
    func grossAndWallClockAggregationHandleOverlaps() {
        let taskID = UUID()
        let sessionA = UUID()
        let sessionB = UUID()
        let start = Date(timeIntervalSince1970: 1000)

        let first = TimeSegment(
            sessionID: sessionA,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(60 * 60)
        )

        let second = TimeSegment(
            sessionID: sessionB,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: start.addingTimeInterval(30 * 60),
            endedAt: start.addingTimeInterval(90 * 60)
        )

        let service = TimeAggregationService()

        #expect(service.totalSeconds(segments: [first, second], mode: .gross) == 7_200)
        #expect(service.totalSeconds(segments: [first, second], mode: .wallClock) == 5_400)
    }

    @Test
    func durationFormattingUsesCompactClockText() {
        #expect(DurationFormatter.compact(4 * 3600 + 35 * 60) == "4h 35m")
        #expect(DurationFormatter.clock(84) == "01:24")
    }

    @Test @MainActor
    func countdownEventsAreSwiftDataBackedAndAllowEmptyList() throws {
        let context = try makeContext()
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        #expect(store.countdownEvents.isEmpty)

        store.addCountdownEvent()
        #expect(store.countdownEvents.count == 1)

        let event = try #require(store.countdownEvents.first)
        store.updateCountdownEvent(event, title: "Launch", date: Date(timeIntervalSince1970: 200))
        #expect(store.countdownEvents.first?.title == "Launch")

        store.deleteCountdownEvent(event)
        #expect(store.countdownEvents.isEmpty)
    }

    @Test @MainActor
    func taskMovePreventsCyclesAndUpdatesHierarchy() throws {
        let context = try makeContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")

        let root = try repository.createTask(title: "Root", parentID: nil, colorHex: nil, iconName: nil)
        let child = try repository.createTask(title: "Child", parentID: root.id, colorHex: nil, iconName: nil)

        do {
            try repository.moveTask(taskID: root.id, newParentID: child.id, sortOrder: 10)
            Issue.record("Expected invalid move to throw")
        } catch TaskRepositoryError.invalidMove {
        } catch {
            Issue.record("Unexpected move error: \(error)")
        }
        #expect((try repository.task(id: root.id))?.parentID == nil)

        try repository.moveTask(taskID: child.id, newParentID: nil, sortOrder: 20)
        let movedTask = try repository.task(id: child.id)
        let moved = try #require(movedTask)
        #expect(moved.parentID == nil)
        #expect(moved.depth == 0)
    }

    @Test @MainActor
    func softDeletingParentRecursivelySoftDeletesDescendantsButKeepsLedger() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")

        let parent = try taskRepository.createTask(title: "Parent", parentID: nil, colorHex: nil, iconName: nil)
        let child = try taskRepository.createTask(title: "Child", parentID: parent.id, colorHex: nil, iconName: nil)
        let grandchild = try taskRepository.createTask(title: "Grandchild", parentID: child.id, colorHex: nil, iconName: nil)
        let segment = try timeRepository.addManualSegment(
            taskID: grandchild.id,
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            note: nil
        )

        try taskRepository.softDeleteTask(taskID: parent.id)

        #expect(try taskRepository.allNodes().isEmpty)
        let rawNodes = try context.fetch(FetchDescriptor<TaskNode>())
        #expect(rawNodes.count == 3)
        #expect(rawNodes.allSatisfy { $0.deletedAt != nil })
        #expect(try timeRepository.allSegments().contains { $0.id == segment.id })
    }

    @Test @MainActor
    func taskTreeServiceFiltersInvalidParentsAndFlattensVisibleRows() throws {
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let child = TaskNode(title: "Child", parentID: parent.id, deviceID: "test")
        let grandchild = TaskNode(title: "Grandchild", parentID: child.id, deviceID: "test")
        let sibling = TaskNode(title: "Sibling", parentID: nil, deviceID: "test")
        let service = TaskTreeService()
        let indexes = service.indexes(tasks: [parent, child, grandchild, sibling])

        let validParents = service.validParentTasks(for: parent.id, tasks: [parent, child, grandchild, sibling])
        #expect(validParents.map(\.id) == [sibling.id])

        let rows = TaskTreeFlattener.visibleRows(
            rootTasks: indexes.childrenByParentID[nil] ?? [],
            children: { indexes.childrenByParentID[$0.id] ?? [] },
            expandedTaskIDs: [parent.id]
        )

        #expect(rows.map(\.taskID) == [parent.id, child.id, sibling.id])
        #expect(rows.map(\.depth) == [0, 1, 0])
        #expect(rows.first?.hasChildren == true)
        #expect(rows.first?.isExpanded == true)
    }

    @Test @MainActor
    func timerPauseResumeStopUsesSegmentsAsLedger() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Design", parentID: nil, colorHex: nil, iconName: nil)

        let first = try timeRepository.startTask(taskID: task.id, source: .timer)
        #expect(try timeRepository.activeSegments().count == 1)

        try timeRepository.pauseSession(sessionID: first.sessionID)
        #expect(try timeRepository.activeSegments().isEmpty)

        let resumedSegment = try timeRepository.resumeSession(sessionID: first.sessionID)
        let second = try #require(resumedSegment)
        #expect(second.sessionID == first.sessionID)
        #expect(try timeRepository.activeSegments().count == 1)

        try timeRepository.stopSession(sessionID: first.sessionID)
        #expect(try timeRepository.activeSegments().isEmpty)

        let sessions = try timeRepository.sessions()
        #expect(sessions.first?.endedAt != nil)
    }

    @Test @MainActor
    func segmentEditAndSoftDeleteKeepLedgerConsistent() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(title: "Design", parentID: nil, colorHex: nil, iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Writing", parentID: nil, colorHex: nil, iconName: nil)

        let start = Date(timeIntervalSince1970: 2_000)
        let segment = try timeRepository.addManualSegment(
            taskID: firstTask.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(1_800),
            note: "Original"
        )

        try timeRepository.updateSegment(
            segmentID: segment.id,
            taskID: secondTask.id,
            startedAt: start.addingTimeInterval(300),
            endedAt: start.addingTimeInterval(2_100),
            note: "Corrected"
        )

        let editedSegments = try timeRepository.segments(from: start, to: start.addingTimeInterval(3_000))
        let updated = try #require(editedSegments.first { $0.id == segment.id })
        #expect(updated.taskID == secondTask.id)
        #expect(updated.startedAt == start.addingTimeInterval(300))
        #expect(updated.endedAt == start.addingTimeInterval(2_100))

        try timeRepository.softDeleteSegment(segmentID: segment.id)
        #expect(try timeRepository.segments(from: start, to: start.addingTimeInterval(3_000)).isEmpty)
    }

    @Test @MainActor
    func segmentRangeQueryUsesExplicitSnapshotDateForActiveSegments() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Active", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date(timeIntervalSince1970: 10_000)
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: start, titleSnapshot: task.title)
        let segment = TimeSegment(sessionID: session.id, taskID: task.id, source: .timer, deviceID: "test", startedAt: start, endedAt: nil)
        context.insert(session)
        context.insert(segment)
        try context.save()

        let beforeRange = try timeRepository.segments(
            from: start.addingTimeInterval(600),
            to: start.addingTimeInterval(1_200),
            now: start.addingTimeInterval(300)
        )
        let insideRange = try timeRepository.segments(
            from: start.addingTimeInterval(600),
            to: start.addingTimeInterval(1_200),
            now: start.addingTimeInterval(900)
        )

        #expect(beforeRange.isEmpty)
        #expect(insideRange.map(\.id) == [segment.id])
    }

    @Test @MainActor
    func analyticsOverviewBreakdownAndOverlapUseSegments() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(title: "Coding", parentID: nil, colorHex: "1677FF", iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Meeting", parentID: nil, colorHex: "EF4444", iconName: nil)
        secondTask.status = .planned
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        _ = try timeRepository.addManualSegment(
            taskID: firstTask.id,
            startedAt: startOfDay.addingTimeInterval(9 * 3600),
            endedAt: startOfDay.addingTimeInterval(10 * 3600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: secondTask.id,
            startedAt: startOfDay.addingTimeInterval(9 * 3600 + 30 * 60),
            endedAt: startOfDay.addingTimeInterval(10 * 3600 + 30 * 60),
            note: nil
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        let overview = store.analyticsOverview(for: .week, now: now)
        #expect(overview.grossSeconds == 7_200)
        #expect(overview.wallSeconds == 5_400)
        #expect(overview.overlapSeconds == 1_800)

        let tasks = store.taskBreakdown(range: .week, now: now)
        #expect(tasks.count == 2)
        #expect(tasks.first?.grossSeconds == 3_600)
        #expect(tasks.first { $0.taskID == secondTask.id }?.status == .planned)

        let overlaps = store.overlapSegments(range: .week, now: now)
        #expect(overlaps.first?.durationSeconds == 1_800)
    }

    @Test @MainActor
    func quickStartRecentTasksRankByFrequencyAndSkipPinnedTasks() throws {
        let context = try makeContext()
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
    func todayHourlyBreakdownClipsSegmentsIntoHourBuckets() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Design", parentID: nil, colorHex: nil, iconName: nil)
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: startOfDay.addingTimeInterval(9 * 3_600 + 30 * 60),
            endedAt: startOfDay.addingTimeInterval(10 * 3_600 + 15 * 60),
            note: nil
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        let hourly = store.hourlyBreakdown(for: now, now: now)

        #expect(hourly.count == 24)
        #expect(hourly[9].grossSeconds == 30 * 60)
        #expect(hourly[10].grossSeconds == 15 * 60)
        #expect(hourly[9].wallSeconds == 30 * 60)
    }

    @Test @MainActor
    func todayHourlyBreakdownSeparatesGrossAndWallForOverlap() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(title: "Coding", parentID: nil, colorHex: nil, iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Meeting", parentID: nil, colorHex: nil, iconName: nil)
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        _ = try timeRepository.addManualSegment(
            taskID: firstTask.id,
            startedAt: startOfDay.addingTimeInterval(9 * 3_600),
            endedAt: startOfDay.addingTimeInterval(10 * 3_600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: secondTask.id,
            startedAt: startOfDay.addingTimeInterval(9 * 3_600 + 30 * 60),
            endedAt: startOfDay.addingTimeInterval(10 * 3_600),
            note: nil
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        let nine = store.hourlyBreakdown(for: now, now: now)[9]

        #expect(nine.grossSeconds == 90 * 60)
        #expect(nine.wallSeconds == 60 * 60)
    }

    @Test @MainActor
    func taskBreakdownKeepsLedgerVisibleAfterTaskSoftDelete() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Client Research", parentID: nil, colorHex: "1677FF", iconName: nil)
        let now = Date()

        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: now.addingTimeInterval(-3_600),
            endedAt: now.addingTimeInterval(-1_800),
            note: "Billable"
        )
        try taskRepository.softDeleteTask(taskID: task.id)

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        let breakdown = store.taskBreakdown(range: .today, now: now)

        #expect(breakdown.count == 1)
        #expect(breakdown.first?.title == "Client Research")
        #expect(breakdown.first?.path == AppStrings.localized("task.deleted.path"))
        #expect(breakdown.first?.grossSeconds == 1_800)
    }

    @Test @MainActor
    func optimizeDatabasePreservesLedgerRowsForSoftDeletedTasks() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Temporary Client", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date().addingTimeInterval(-1_800)
        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(900),
            note: nil
        )
        try taskRepository.softDeleteTask(taskID: task.id)

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        #expect(store.allSegments.count == 1)

        let removedCount = store.optimizeDatabase()

        #expect(removedCount == 0)
        #expect(try timeRepository.allSegments().count == 1)
        #expect(try timeRepository.sessions().count == 1)
    }

    @Test @MainActor
    func optimizeDatabaseRemovesOnlyTrulyOrphanedLedgerRows() throws {
        let context = try makeContext()
        let missingTaskID = UUID()
        let session = TimeSession(taskID: missingTaskID, source: .manual, deviceID: "test")
        session.endedAt = Date()
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: missingTaskID,
            source: .manual,
            deviceID: "test",
            startedAt: Date().addingTimeInterval(-900),
            endedAt: Date()
        )
        context.insert(session)
        context.insert(segment)
        try context.save()

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        let removedCount = store.optimizeDatabase()

        #expect(removedCount == 2)
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).contains { $0.id == segment.id } == false)
        #expect(try context.fetch(FetchDescriptor<TimeSession>()).contains { $0.id == session.id } == false)
    }

    @Test @MainActor
    func manualSegmentStoresAndUpdatesSessionNote() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Writing", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date(timeIntervalSince1970: 10_000)
        let segment = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(1_200),
            note: "Initial note"
        )

        var session = try #require(try timeRepository.sessions().first { $0.id == segment.sessionID })
        #expect(session.note == "Initial note")
        #expect(session.titleSnapshot == "Writing")

        try timeRepository.updateSegment(
            segmentID: segment.id,
            taskID: task.id,
            startedAt: start.addingTimeInterval(60),
            endedAt: start.addingTimeInterval(1_500),
            note: "Corrected note"
        )

        session = try #require(try timeRepository.sessions().first { $0.id == segment.sessionID })
        #expect(session.note == "Corrected note")
        #expect(session.startedAt == start.addingTimeInterval(60))
        #expect(session.endedAt == start.addingTimeInterval(1_500))
    }

    @Test @MainActor
    func pomodoroCreatesLedgerSegmentAndCompletesFocus() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository, deviceID: "test")
        let task = try taskRepository.createTask(title: "Focus", parentID: nil, colorHex: nil, iconName: nil)

        let run = try pomodoroRepository.startPomodoro(taskID: task.id, focusSeconds: 25 * 60, breakSeconds: 5 * 60, targetRounds: 1)

        #expect(run.state == .focusing)
        let active = try timeRepository.activeSegments()
        #expect(active.count == 1)
        #expect(active.first?.source == .pomodoro)
        #expect(active.first?.sessionID == run.sessionID)

        try pomodoroRepository.completeFocus(runID: run.id)

        #expect(try timeRepository.activeSegments().isEmpty)
        let completedRun = try #require(try pomodoroRepository.runs().first { $0.id == run.id })
        #expect(completedRun.state == .completed)
        #expect(completedRun.completedFocusRounds == 1)
        #expect(completedRun.endedAt != nil)
        #expect(try timeRepository.sessions().first { $0.id == run.sessionID }?.endedAt != nil)
    }

    @Test @MainActor
    func pomodoroIntermediateRoundKeepsSessionPausedForResume() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository, deviceID: "test")
        let task = try taskRepository.createTask(title: "Focus", parentID: nil, colorHex: nil, iconName: nil)

        let run = try pomodoroRepository.startPomodoro(taskID: task.id, focusSeconds: 25 * 60, breakSeconds: 5 * 60, targetRounds: 2)
        try pomodoroRepository.completeFocus(runID: run.id)

        let pausedSession = try #require(try timeRepository.pausedSessions().first { $0.id == run.sessionID })
        let updatedRun = try #require(try pomodoroRepository.runs().first { $0.id == run.id })
        #expect(pausedSession.endedAt == nil)
        #expect(updatedRun.state == .shortBreak)
        #expect(updatedRun.endedAt == nil)
    }

    @Test @MainActor
    func startingPomodoroPausesExistingTimerForSameTask() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository, deviceID: "test")
        let task = try taskRepository.createTask(title: "Shared Task", parentID: nil, colorHex: nil, iconName: nil)

        let regularSegment = try timeRepository.startTask(taskID: task.id, source: .timer)
        let run = try pomodoroRepository.startPomodoro(taskID: task.id, focusSeconds: 25 * 60, breakSeconds: 5 * 60, targetRounds: 1)

        let active = try timeRepository.activeSegments()
        #expect(active.count == 1)
        #expect(active.first?.source == .pomodoro)
        #expect(active.first?.sessionID == run.sessionID)

        let pausedRegular = try #require(try timeRepository.allSegments().first { $0.id == regularSegment.id })
        #expect(pausedRegular.endedAt != nil)
    }

    @Test @MainActor
    func storeTimerActionsKeepPomodoroRunInSync() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Synced Focus", parentID: nil, colorHex: nil, iconName: nil)
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        store.selectedTaskID = task.id

        store.startPomodoroForSelectedTask(focusSeconds: 25 * 60, breakSeconds: 5 * 60, targetRounds: 1)
        let activeSegment = try #require(store.activeSegment(for: task.id))
        #expect(activeSegment.source == .pomodoro)
        let startedAt = try #require(store.activePomodoroRun(for: task.id)?.startedAt)
        activeSegment.startedAt = Date().addingTimeInterval(-5 * 60)
        try context.save()
        store.refreshQuietly()
        let focusingRun = try #require(store.activePomodoroRun(for: task.id))
        #expect(focusingRun.state == .focusing)
        #expect(store.pomodoroRemainingSeconds(for: focusingRun) <= 20 * 60)

        let currentSegment = try #require(store.activeSegment(for: task.id))
        store.pause(segment: currentSegment)
        #expect(store.activeSegment(for: task.id) == nil)
        #expect(store.pausedSession(for: task.id) != nil)
        #expect(store.activePomodoroRun(for: task.id)?.state == .interrupted)
        #expect(store.activePomodoroRun(for: task.id)?.startedAt == startedAt)

        let pausedSession = try #require(store.pausedSession(for: task.id))
        store.resume(session: pausedSession)
        #expect(store.activeSegment(for: task.id)?.source == .pomodoro)
        #expect(store.activePomodoroRun(for: task.id)?.state == .focusing)
        #expect(store.activePomodoroRun(for: task.id)?.startedAt == startedAt)

        let resumedSegment = try #require(store.activeSegment(for: task.id))
        store.stop(segment: resumedSegment)
        #expect(store.activeSegment(for: task.id) == nil)
        #expect(store.activePomodoroRun(for: task.id) == nil)
    }

    @Test @MainActor
    func cancellingPomodoroStopsLedgerSession() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository, deviceID: "test")
        let task = try taskRepository.createTask(title: "Focus", parentID: nil, colorHex: nil, iconName: nil)

        let run = try pomodoroRepository.startPomodoro(taskID: task.id, focusSeconds: 25 * 60, breakSeconds: 5 * 60, targetRounds: 2)
        try pomodoroRepository.cancel(runID: run.id)

        #expect(try timeRepository.activeSegments().isEmpty)
        let cancelledRun = try #require(try pomodoroRepository.runs().first { $0.id == run.id })
        #expect(cancelledRun.state == .cancelled)
        #expect(cancelledRun.endedAt != nil)
    }

    @Test @MainActor
    func demoDataContainsMultiDayAnalyticsAndActiveTimers() throws {
        let context = try makeContext()
        try SeedData.replaceWithDemoData(context: context)

        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository, deviceID: "test")

        #expect(try taskRepository.allNodes().count >= 10)
        #expect(try timeRepository.allSegments().count >= 40)
        #expect(try timeRepository.activeSegments().count == 2)
        #expect(try pomodoroRepository.runs().contains { $0.state == .completed })

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        let overview = store.analyticsOverview(for: .week)
        #expect(overview.grossSeconds > overview.wallSeconds)
        #expect(store.taskBreakdown(range: .week).isEmpty == false)
    }

    @Test @MainActor
    func replacingDemoDataClearsExistingLedgerBeforeSeeding() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let oldTask = try taskRepository.createTask(title: "Temporary Task", parentID: nil, colorHex: nil, iconName: nil)
        _ = try timeRepository.addManualSegment(
            taskID: oldTask.id,
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            note: nil
        )

        try SeedData.replaceWithDemoData(context: context)

        #expect(try taskRepository.allNodes().contains { $0.title == "Temporary Task" } == false)
        #expect(try timeRepository.allSegments().contains { $0.taskID == oldTask.id } == false)
        #expect(try timeRepository.activeSegments().count == 2)
    }

    @Test @MainActor
    func clearingDemoDataKeepsUserCreatedRecords() throws {
        let context = try makeContext()
        try SeedData.replaceWithDemoData(context: context)

        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let userTask = try taskRepository.createTask(title: "Real Work", parentID: nil, colorHex: nil, iconName: nil)
        _ = try timeRepository.addManualSegment(
            taskID: userTask.id,
            startedAt: Date().addingTimeInterval(-900),
            endedAt: Date(),
            note: nil
        )

        try SeedData.clearDemoData(context: context)

        #expect(try taskRepository.allNodes().map(\.title) == ["Real Work"])
        #expect(try timeRepository.allSegments().count == 1)
        #expect(try timeRepository.activeSegments().isEmpty)
    }

    @Test @MainActor
    func modelDefaultsSupportCloudKitCompatibleConstruction() throws {
        let context = try makeContext()
        let task = TaskNode(title: "Defaults", parentID: nil, deviceID: "test")
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test")
        let segment = TimeSegment(sessionID: session.id, taskID: task.id, source: .timer, deviceID: "test")
        let run = PomodoroRun(taskID: task.id, deviceID: "test")
        let summary = DailySummary(date: Date(), taskID: task.id, grossSeconds: 0, wallClockSeconds: 0, pomodoroCount: 0, interruptionCount: 0)
        let countdown = CountdownEvent(title: "Launch", date: Date(), deviceID: "test")
        let preference = SyncedPreference(key: AppPreferenceKey.defaultFocusMinutes.rawValue, valueJSON: "25", deviceID: "test")
        let checklistItem = ChecklistItem(taskID: task.id, title: "Checklist", deviceID: "test")

        context.insert(task)
        context.insert(session)
        context.insert(segment)
        context.insert(run)
        context.insert(summary)
        context.insert(countdown)
        context.insert(preference)
        context.insert(checklistItem)
        try context.save()

        #expect(task.id.uuidString.isEmpty == false)
        #expect(task.status == .active)
        #expect(segment.source == .timer)
        #expect(run.state == .planned)
        #expect(summary.version == 1)
        #expect(countdown.deletedAt == nil)
        #expect(preference.deletedAt == nil)
        #expect(checklistItem.deletedAt == nil)
    }

    @Test @MainActor
    func cloudSyncedSchemaIncludesChecklistAndAllUserDataModels() throws {
        let requiredModelNames: Set<String> = [
            "TaskNode",
            "TimeSession",
            "TimeSegment",
            "PomodoroRun",
            "CountdownEvent",
            "SyncedPreference",
            "ChecklistItem"
        ]

        #expect(requiredModelNames.isSubset(of: TimeTrackerModelRegistry.cloudSyncedUserModelNames))

        let schema = TimeTrackerModelRegistry.currentSchema
        let configuration = ModelConfiguration(
            "TimeTrackerCloudSyncContract",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let task = TaskNode(title: "Cloud task", parentID: nil, deviceID: "test")
        let checklist = ChecklistItem(taskID: task.id, title: "Cloud checklist", deviceID: "test")
        let preference = SyncedPreference(key: AppPreferenceKey.showGrossAndWallTogether.rawValue, valueJSON: "true", deviceID: "test")

        context.insert(task)
        context.insert(checklist)
        context.insert(preference)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ChecklistItem>()).map(\.title) == ["Cloud checklist"])
        #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).map(\.key) == [AppPreferenceKey.showGrossAndWallTogether.rawValue])
    }

    @Test @MainActor
    func taskStatusCanBePlannedAndCompleted() throws {
        let context = try makeContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try repository.createTask(title: "Plan draft", parentID: nil, colorHex: nil, iconName: nil)

        try repository.setTaskStatus(taskID: task.id, status: .planned)
        #expect(try repository.task(id: task.id)?.status == .planned)

        try repository.setTaskStatus(taskID: task.id, status: .completed)
        #expect(try repository.task(id: task.id)?.status == .completed)
        #expect(TaskStatus.completed.displayName == AppStrings.localized("status.completed"))
    }

    @Test @MainActor
    func csvExportIncludesLedgerRows() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "CSV Task", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date(timeIntervalSince1970: 2_000)
        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(900),
            note: "Export note"
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        let csv = store.csvExport()

        #expect(csv.contains("Task,Path,Start,End,Duration Seconds,Source,Note"))
        #expect(csv.contains("CSV Task"))
        #expect(csv.contains("900"))
        #expect(csv.contains("Export note"))
    }

    @Test
    func timelineLayoutUsesMinimumNumberOfLanes() {
        let day = Date(timeIntervalSince1970: 0)
        let dayInterval = DateInterval(start: day, duration: 24 * 60 * 60)
        let first = TimelineLayoutItem(id: UUID(), startedAt: day.addingTimeInterval(12 * 60), endedAt: day.addingTimeInterval(34 * 60))
        let second = TimelineLayoutItem(id: UUID(), startedAt: day.addingTimeInterval(20 * 60), endedAt: day.addingTimeInterval(50 * 60))
        let third = TimelineLayoutItem(id: UUID(), startedAt: day.addingTimeInterval(40 * 60), endedAt: day.addingTimeInterval(55 * 60))

        let result = TimelineLayoutEngine.layout(items: [first, second, third], dayInterval: dayInterval)

        #expect(result.laneCount == 2)
        #expect(result.entries.map(\.lane) == [0, 1, 0])
    }

    @Test
    func timelineLayoutKeepsBackToBackSegmentsVisuallySeparated() {
        let day = Date(timeIntervalSince1970: 0)
        let dayInterval = DateInterval(start: day, duration: 24 * 60 * 60)
        let first = TimelineLayoutItem(id: UUID(), startedAt: day.addingTimeInterval(9 * 3600), endedAt: day.addingTimeInterval(10 * 3600))
        let second = TimelineLayoutItem(id: UUID(), startedAt: day.addingTimeInterval(10 * 3600), endedAt: day.addingTimeInterval(11 * 3600))

        let result = TimelineLayoutEngine.layout(items: [first, second], dayInterval: dayInterval)

        #expect(result.laneCount == 2)
        #expect(result.entries.map(\.lane) == [0, 1])
    }

    @Test
    func timelineLayoutClipsCrossDaySegmentsAndUsesVisibleRange() {
        let day = Date(timeIntervalSince1970: 24 * 60 * 60)
        let dayInterval = DateInterval(start: day, duration: 24 * 60 * 60)
        let crossDay = TimelineLayoutItem(
            id: UUID(),
            startedAt: day.addingTimeInterval(-45 * 60),
            endedAt: day.addingTimeInterval(20 * 60)
        )
        let evening = TimelineLayoutItem(
            id: UUID(),
            startedAt: day.addingTimeInterval(20 * 3600),
            endedAt: day.addingTimeInterval(21 * 3600)
        )

        let result = TimelineLayoutEngine.layout(items: [crossDay, evening], dayInterval: dayInterval)

        #expect(result.entries.first?.item.startedAt == day)
        #expect(result.displayInterval.start == day)
        #expect(result.displayInterval.end == evening.endedAt)
    }

    @Test
    func timelineLayoutUsesFirstAndLastVisibleSegmentBounds() {
        let day = Date(timeIntervalSince1970: 48 * 60 * 60)
        let dayInterval = DateInterval(start: day, duration: 24 * 60 * 60)
        let morning = TimelineLayoutItem(
            id: UUID(),
            startedAt: day.addingTimeInterval(9 * 3600),
            endedAt: day.addingTimeInterval(10 * 3600)
        )
        let afternoon = TimelineLayoutItem(
            id: UUID(),
            startedAt: day.addingTimeInterval(14 * 3600),
            endedAt: day.addingTimeInterval(16 * 3600)
        )

        let result = TimelineLayoutEngine.layout(items: [afternoon, morning], dayInterval: dayInterval)

        #expect(result.displayInterval.start == morning.startedAt)
        #expect(result.displayInterval.end == afternoon.endedAt)
    }

    @Test
    func timelineAxisCompressionFoldsLongIdleGaps() {
        let day = Date(timeIntervalSince1970: 72 * 60 * 60)
        let display = DateInterval(start: day.addingTimeInterval(9 * 3600), end: day.addingTimeInterval(16 * 3600))
        let morning = DateInterval(start: day.addingTimeInterval(9 * 3600), end: day.addingTimeInterval(10 * 3600))
        let afternoon = DateInterval(start: day.addingTimeInterval(14 * 3600), end: day.addingTimeInterval(16 * 3600))

        let compression = TimelineAxisCompression(displayInterval: display, busyIntervals: [morning, afternoon])

        #expect(compression.omittedGaps.count == 1)
        #expect(abs((compression.omittedGaps.first?.duration ?? 0) - 14_400) < 0.001)
        #expect(compression.compressedDuration < display.duration)
        #expect(compression.ratio(for: afternoon.start) < afternoon.start.timeIntervalSince(display.start) / display.duration)
    }

    @Test
    func timelineAxisCompressionKeepsShortGapsLinear() {
        let day = Date(timeIntervalSince1970: 96 * 60 * 60)
        let display = DateInterval(start: day.addingTimeInterval(9 * 3600), end: day.addingTimeInterval(11 * 3600))
        let first = DateInterval(start: day.addingTimeInterval(9 * 3600), end: day.addingTimeInterval(10 * 3600))
        let second = DateInterval(start: day.addingTimeInterval(10 * 3600 + 20 * 60), end: day.addingTimeInterval(11 * 3600))

        let compression = TimelineAxisCompression(displayInterval: display, busyIntervals: [first, second])

        #expect(compression.omittedGaps.isEmpty)
        #expect(compression.compressedDuration == display.duration)
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
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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

    @Test
    func regularWidthIOSUsesVisibleSystemSplitView() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: projectRoot.appending(path: "timetracker/ContentView.swift"), encoding: .utf8)

        #expect(source.contains("iPadRootView(store: store)"))
        #expect(source.contains("struct iPadRootView"))
        #expect(source.contains("ipad.splitNavigation"))
        #expect(source.contains(".navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)"))
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
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: projectRoot.appending(path: "timetracker/HomeViews.swift"), encoding: .utf8)

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
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let homeSource = try String(contentsOf: projectRoot.appending(path: "timetracker/HomeViews.swift"), encoding: .utf8)
        let storeSource = try String(contentsOf: projectRoot.appending(path: "timetracker/TimeTrackerStore.swift"), encoding: .utf8)

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
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: projectRoot.appending(path: "timetracker/HomeViews.swift"), encoding: .utf8)

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
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: projectRoot.appending(path: "timetracker/HomeViews.swift"), encoding: .utf8)

        #expect(source.contains(".presentationBackground(Color(uiColor: .systemGroupedBackground))"))
        #expect(source.contains(".scrollContentBackground(.hidden)"))
    }

    @Test
    func taskTreeUsesFlatVisibleRowsSoEachTaskOwnsItsListRow() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: projectRoot.appending(path: "timetracker/TasksViews.swift"), encoding: .utf8)
        let serviceSource = try String(contentsOf: projectRoot.appending(path: "timetracker/TaskTreeServices.swift"), encoding: .utf8)

        #expect(source.contains("ForEach(store.taskTreeRows(expandedTaskIDs: expansionState.expandedTaskIDs))"))
        #expect(source.contains("TaskManagementTreeRow") == false)
        #expect(source.contains("DisclosureGroup(") == false)
        #expect(serviceSource.contains("struct TaskTreeFlattener"))
        #expect(serviceSource.contains("TaskTreeRowModel"))
        #expect(source.contains("rotationEffect") == false)
    }

    @Test
    func todayMetricsUseSemanticTrendColorsAndEqualCompactActions() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: projectRoot.appending(path: "timetracker/HomeViews.swift"), encoding: .utf8)

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
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: projectRoot.appending(path: "timetracker/TasksViews.swift"), encoding: .utf8)

        #expect(source.contains("CompactChecklistProgressLine("))
        #expect(source.contains("ProgressView(value: progress.fraction)"))
        #expect(source.contains("checklist.progressFormat"))
        #expect(source.contains("if progress.totalCount > 0 {\n                    CompactChecklistProgressLine"))
    }

    @Test
    func taskRowsUseLifetimeRollupDurationInsteadOfTodayOnlyDuration() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let tasksSource = try String(contentsOf: projectRoot.appending(path: "timetracker/TasksViews.swift"), encoding: .utf8)
        let inspectorSource = try String(contentsOf: projectRoot.appending(path: "timetracker/SidebarInspectorViews.swift"), encoding: .utf8)

        #expect(tasksSource.contains("rollup?.workedSeconds ?? store.secondsForTaskTotalRollup(task)"))
        #expect(tasksSource.contains("secondsForTaskTodayRollup(task)") == false)
        #expect(inspectorSource.contains("task.field.total"))
        #expect(inspectorSource.contains("forecast.worked"))
    }

    @Test
    func taskEditorUsesInlineStatusPickerAndRemovesTaskKindClassification() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editorSource = try String(contentsOf: projectRoot.appending(path: "timetracker/EditorViews.swift"), encoding: .utf8)
        let modelsSource = try String(contentsOf: projectRoot.appending(path: "timetracker/TimeTrackerModels.swift"), encoding: .utf8)
        let englishStrings = try String(contentsOf: projectRoot.appending(path: "timetracker/en.lproj/Localizable.strings"), encoding: .utf8)

        #expect(editorSource.contains("TaskStatusPicker(selection: $draft.status)"))
        #expect(editorSource.contains(".pickerStyle(.inline)"))
        #expect(editorSource.contains("TaskStatusPickerOption(status: status)"))
        #expect(editorSource.contains("TaskKindPicker") == false)
        #expect(modelsSource.contains("enum TaskNodeKind") == false)
        #expect(englishStrings.contains("editor.task.kind") == false)
    }

    @Test
    func taskListShowsStatusBadgesInsteadOfTaskKindBadges() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let tasksSource = try String(contentsOf: projectRoot.appending(path: "timetracker/TasksViews.swift"), encoding: .utf8)
        let sharedSource = try String(contentsOf: projectRoot.appending(path: "timetracker/SharedUI.swift"), encoding: .utf8)

        #expect(tasksSource.contains("TaskStatusBadge(status: task.status)"))
        #expect(tasksSource.contains("TaskKindBadge") == false)
        #expect(sharedSource.contains("struct TaskKindBadge") == false)
    }

    @Test
    func analyticsTaskDistributionUsesTaskBucketsAndTaskColors() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let analyticsSource = try String(contentsOf: projectRoot.appending(path: "timetracker/AnalyticsViews.swift"), encoding: .utf8)
        let englishStrings = try String(contentsOf: projectRoot.appending(path: "timetracker/en.lproj/Localizable.strings"), encoding: .utf8)

        #expect(analyticsSource.contains("id: task.taskID.uuidString"))
        #expect(analyticsSource.contains("colorHex: task.colorHex"))
        #expect(analyticsSource.contains("point.status?.rawValue") == false)
        #expect(englishStrings.contains("Task Status Distribution") == false)
        #expect(englishStrings.contains("\"analytics.taskUsage.title\" = \"Task Distribution\";"))
    }

    @Test
    func todayActivityDistributionUsesTaskColorBuckets() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let analyticsSource = try String(contentsOf: projectRoot.appending(path: "timetracker/AnalyticsViews.swift"), encoding: .utf8)
        let englishStrings = try String(contentsOf: projectRoot.appending(path: "timetracker/en.lproj/Localizable.strings"), encoding: .utf8)

        #expect(analyticsSource.contains("TodayActivityCard(store: store, segments: todaySegments, now: now)"))
        #expect(analyticsSource.contains("struct HourTaskSlice"))
        #expect(analyticsSource.contains("Color(hex: colorHex)"))
        #expect(analyticsSource.contains("AnalyticsLegendSwatch(color: .blue, title: AppStrings.wallTime)") == false)
        #expect(analyticsSource.contains("HourStackLayoutEngine.layout"))
        #expect(analyticsSource.contains("RoundedRectangle(cornerRadius: cornerRadius"))
        #expect(analyticsSource.contains("availableHeight * CGFloat(point.totalSeconds)") == false)
        #expect(analyticsSource.contains(".clipShape(Capsule())") == false)
        #expect(englishStrings.contains("\"analytics.hourDistribution.taskColorHint\""))
    }

    @Test
    func hourStackLayoutPreservesTinyTasksByBorrowingFromLargestSlice() throws {
        let largeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let tinyID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let smallerID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

        let layout = HourStackLayoutEngine.layout(
            inputs: [
                HourStackLayoutInput(id: largeID, seconds: 3_500),
                HourStackLayoutInput(id: tinyID, seconds: 10),
                HourStackLayoutInput(id: smallerID, seconds: 10)
            ],
            availableHeight: 100,
            minSliceHeight: 8
        )

        let large = try #require(layout.first { $0.id == largeID })
        let tiny = try #require(layout.first { $0.id == tinyID })
        let smaller = try #require(layout.first { $0.id == smallerID })

        #expect(layout.count == 3)
        #expect(tiny.height == 8)
        #expect(smaller.height == 8)
        #expect(large.height > 80)
        #expect(abs(layout.reduce(0) { $0 + $1.height } - 100) < 0.001)
    }

    @Test
    func hourStackLayoutDropsShortestTasksWhenMinimumHeightsWouldOverflow() {
        let ids = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000016")!
        ]

        let layout = HourStackLayoutEngine.layout(
            inputs: zip(ids, [100, 90, 80, 70, 60, 50]).map { id, seconds in
                HourStackLayoutInput(id: id, seconds: seconds)
            },
            availableHeight: 50,
            minSliceHeight: 10
        )

        #expect(layout.count == 4)
        #expect(layout.map(\.id) == Array(ids.prefix(4)))
        #expect(layout.contains { $0.id == ids[4] } == false)
        #expect(layout.contains { $0.id == ids[5] } == false)
        #expect(abs(layout.reduce(0) { $0 + $1.height } - 50) < 0.001)
    }

    @Test
    func checklistUsesTodoStyleAndKeepsCompletedHistoryHint() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editorSource = try String(contentsOf: projectRoot.appending(path: "timetracker/EditorViews.swift"), encoding: .utf8)
        let inspectorSource = try String(contentsOf: projectRoot.appending(path: "timetracker/SidebarInspectorViews.swift"), encoding: .utf8)
        let sharedSource = try String(contentsOf: projectRoot.appending(path: "timetracker/SharedUI.swift"), encoding: .utf8)
        let englishStrings = try String(contentsOf: projectRoot.appending(path: "timetracker/en.lproj/Localizable.strings"), encoding: .utf8)

        #expect(sharedSource.contains("\"checkmark.circle.fill\""))
        #expect(editorSource.contains("ChecklistCompletionButton"))
        #expect(editorSource.contains(".strikethrough(item.isCompleted)"))
        #expect(inspectorSource.contains("store.toggleChecklistItem(item)"))
        #expect(inspectorSource.contains("visibleItems.prefix(5)"))
        #expect(englishStrings.contains("\"checklist.keepCompletedHint\""))
    }

    @Test @MainActor
    func syncedPreferenceMigrationImportsLegacyUserDefaults() throws {
        let defaults = UserDefaults.standard
        let keys = AppPreferenceKey.allCases.map(\.rawValue) + [SyncedPreferenceService.migrationKey]
        let previousValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for (key, value) in previousValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        let pinnedID = UUID()
        defaults.removeObject(forKey: SyncedPreferenceService.migrationKey)
        defaults.set("dark", forKey: AppPreferenceKey.preferredColorScheme.rawValue)
        defaults.set("deep", forKey: AppPreferenceKey.pomodoroDefaultMode.rawValue)
        defaults.set(50, forKey: AppPreferenceKey.defaultFocusMinutes.rawValue)
        defaults.set(10, forKey: AppPreferenceKey.defaultBreakMinutes.rawValue)
        defaults.set(4, forKey: AppPreferenceKey.defaultPomodoroRounds.rawValue)
        defaults.set(false, forKey: AppPreferenceKey.allowParallelTimers.rawValue)
        defaults.set(false, forKey: AppPreferenceKey.showGrossAndWallTogether.rawValue)
        defaults.set(false, forKey: AppPreferenceKey.cloudSyncEnabled.rawValue)
        defaults.set(pinnedID.uuidString, forKey: AppPreferenceKey.quickStartTaskIDs.rawValue)

        let context = try makeContext()
        try SyncedPreferenceService.migrateLegacyPreferencesIfNeeded(context: context, deviceID: "test")
        let stored = try context.fetch(FetchDescriptor<SyncedPreference>())
        let preferences = AppPreferences(syncedPreferences: stored)

        #expect(stored.count == AppPreferenceKey.allCases.count)
        #expect(preferences.preferredColorScheme == "dark")
        #expect(preferences.pomodoroDefaultMode == "deep")
        #expect(preferences.defaultFocusMinutes == 50)
        #expect(preferences.defaultBreakMinutes == 10)
        #expect(preferences.defaultPomodoroRounds == 4)
        #expect(preferences.allowParallelTimers == false)
        #expect(preferences.showGrossAndWallTogether == false)
        #expect(preferences.cloudSyncEnabled == false)
        #expect(preferences.quickStartTaskIDs == [pinnedID])
    }

    @Test @MainActor
    func settingsWriteSyncedPreferencesAndCloudMirror() throws {
        let defaults = UserDefaults.standard
        let previousMigration = defaults.object(forKey: SyncedPreferenceService.migrationKey)
        let previousCloud = defaults.object(forKey: AppCloudSync.enabledKey)
        defer {
            if let previousMigration {
                defaults.set(previousMigration, forKey: SyncedPreferenceService.migrationKey)
            } else {
                defaults.removeObject(forKey: SyncedPreferenceService.migrationKey)
            }
            if let previousCloud {
                defaults.set(previousCloud, forKey: AppCloudSync.enabledKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.enabledKey)
            }
        }

        defaults.set(true, forKey: SyncedPreferenceService.migrationKey)
        let context = try makeContext()
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        let pinnedID = UUID()

        store.setDefaultFocusMinutes(45)
        store.setDefaultBreakMinutes(12)
        store.setDefaultPomodoroRounds(3)
        store.setAllowParallelTimers(false)
        store.setShowGrossAndWallTogether(false)
        store.setCloudSyncEnabled(false)
        store.setQuickStartTaskIDs([pinnedID])

        let preferences = AppPreferences(syncedPreferences: try context.fetch(FetchDescriptor<SyncedPreference>()))
        #expect(preferences.defaultFocusMinutes == 45)
        #expect(preferences.defaultBreakMinutes == 12)
        #expect(preferences.defaultPomodoroRounds == 3)
        #expect(preferences.allowParallelTimers == false)
        #expect(preferences.showGrossAndWallTogether == false)
        #expect(preferences.cloudSyncEnabled == false)
        #expect(preferences.quickStartTaskIDs == [pinnedID])
        #expect(defaults.bool(forKey: AppCloudSync.enabledKey) == false)
    }

    @Test @MainActor
    func checklistDraftsPersistCompletionSortingAndSoftDelete() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Launch", parentID: nil, colorHex: nil, iconName: nil)
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        var firstDraft = TaskEditorDraft(task: task, checklistItems: [])
        firstDraft.checklistItems = [
            ChecklistEditorDraft(title: "Write copy"),
            ChecklistEditorDraft(title: "Ship build")
        ]
        store.saveTaskDraft(firstDraft)
        #expect(store.checklistItems(for: task.id).map(\.title) == ["Write copy", "Ship build"])

        let existing = store.checklistItems(for: task.id)
        var secondDraft = TaskEditorDraft(task: task, checklistItems: existing)
        secondDraft.checklistItems = [
            ChecklistEditorDraft(item: existing[1]),
            ChecklistEditorDraft(item: existing[0])
        ]
        secondDraft.checklistItems[0].isCompleted = true
        secondDraft.checklistItems.removeLast()
        store.saveTaskDraft(secondDraft)

        let activeItems = store.checklistItems(for: task.id)
        let allItems = try context.fetch(FetchDescriptor<ChecklistItem>()).filter { $0.taskID == task.id }
        #expect(activeItems.map(\.title) == ["Ship build"])
        #expect(activeItems.first?.isCompleted == true)
        #expect(activeItems.first?.completedAt != nil)
        #expect(allItems.filter { $0.deletedAt != nil }.count == 1)

        let keptItem = try #require(activeItems.first)
        store.toggleChecklistItem(keptItem)
        #expect(store.checklistItems(for: task.id).first?.isCompleted == false)
        #expect(store.checklistItems(for: task.id).first?.completedAt == nil)
    }

    @Test @MainActor
    func checklistChangesImmediatelyRecalculateForecastEstimates() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Forecast Task", parentID: nil, colorHex: nil, iconName: nil)
        let end = Date().addingTimeInterval(-60)

        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: end.addingTimeInterval(-3_600),
            endedAt: end,
            note: nil
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        var firstDraft = TaskEditorDraft(task: task, checklistItems: [])
        firstDraft.checklistItems = [
            ChecklistEditorDraft(title: "Done", isCompleted: true),
            ChecklistEditorDraft(title: "Todo", isCompleted: false)
        ]
        store.saveTaskDraft(firstDraft)

        let firstRollup = try #require(store.rollup(for: task.id))
        #expect(firstRollup.checklistProgress.label == "1/2")
        #expect(firstRollup.estimatedTotalSeconds == 7_200)
        #expect(firstRollup.remainingSeconds == 3_600)
        #expect(firstRollup.historicalDailyAverageSeconds == 3_600)
        #expect(firstRollup.historicalActiveDayCount == 1)
        #expect(abs((firstRollup.projectedDays ?? 0) - 1.0) < 0.05)

        var secondDraft = TaskEditorDraft(task: task, checklistItems: store.checklistItems(for: task.id))
        secondDraft.checklistItems.append(ChecklistEditorDraft(title: "Also done", isCompleted: true))
        store.saveTaskDraft(secondDraft)

        let secondRollup = try #require(store.rollup(for: task.id))
        #expect(secondRollup.checklistProgress.label == "2/3")
        #expect(secondRollup.estimatedTotalSeconds == 5_400)
        #expect(secondRollup.remainingSeconds == 1_800)
        #expect(secondRollup.historicalDailyAverageSeconds == 3_600)
        #expect(secondRollup.historicalActiveDayCount == 1)
        #expect(abs((secondRollup.projectedDays ?? 0) - 0.5) < 0.05)
    }

    @Test @MainActor
    func checklistToggleImmediatelyRecalculatesForecastEstimates() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Toggle Forecast Task", parentID: nil, colorHex: nil, iconName: nil)
        let end = Date().addingTimeInterval(-60)

        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: end.addingTimeInterval(-3_600),
            endedAt: end,
            note: nil
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        var draft = TaskEditorDraft(task: task, checklistItems: [])
        draft.checklistItems = [
            ChecklistEditorDraft(title: "Already done", isCompleted: true),
            ChecklistEditorDraft(title: "Tap me", isCompleted: false)
        ]
        store.saveTaskDraft(draft)

        let firstRollup = try #require(store.rollup(for: task.id))
        #expect(firstRollup.checklistProgress.label == "1/2")
        #expect(firstRollup.estimatedTotalSeconds == 7_200)
        #expect(firstRollup.remainingSeconds == 3_600)

        let itemToToggle = try #require(store.checklistItems(for: task.id).first { $0.title == "Tap me" })
        store.toggleChecklistItem(itemToToggle)

        let secondRollup = try #require(store.rollup(for: task.id))
        #expect(secondRollup.checklistProgress.label == "2/2")
        #expect(secondRollup.estimatedTotalSeconds == 3_600)
        #expect(secondRollup.remainingSeconds == 0)
        #expect(secondRollup.projectedDays == 0)
        #expect(secondRollup.forecastState == .completed)
    }

    @Test @MainActor
    func checklistForecastRequiresCompletedItemAndTrackedTime() throws {
        let taskWithNoCompletedItem = TaskNode(title: "No completed item", parentID: nil, deviceID: "test")
        let taskWithNoTime = TaskNode(title: "No tracked time", parentID: nil, deviceID: "test")
        let start = Date(timeIntervalSince1970: 10_000)
        let segments = [
            TimeSegment(sessionID: UUID(), taskID: taskWithNoCompletedItem.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(1_800))
        ]
        let checklist = [
            ChecklistItem(taskID: taskWithNoCompletedItem.id, title: "First", isCompleted: false, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: taskWithNoCompletedItem.id, title: "Second", isCompleted: false, sortOrder: 20, deviceID: "test"),
            ChecklistItem(taskID: taskWithNoTime.id, title: "Done", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: taskWithNoTime.id, title: "Todo", isCompleted: false, sortOrder: 20, deviceID: "test")
        ]

        let rollups = TaskRollupService().rollups(
            tasks: [taskWithNoCompletedItem, taskWithNoTime],
            segments: segments,
            checklistItems: checklist,
            now: start.addingTimeInterval(2_000)
        )

        #expect(rollups[taskWithNoCompletedItem.id]?.estimatedTotalSeconds == nil)
        #expect(rollups[taskWithNoCompletedItem.id]?.remainingSeconds == nil)
        #expect(rollups[taskWithNoCompletedItem.id]?.forecastState == .needsCompletedItem)
        #expect(rollups[taskWithNoCompletedItem.id]?.isDisplayableForecast == false)
        #expect(rollups[taskWithNoTime.id]?.estimatedTotalSeconds == nil)
        #expect(rollups[taskWithNoTime.id]?.remainingSeconds == nil)
        #expect(rollups[taskWithNoTime.id]?.forecastState == .needsTrackedTime)
        #expect(rollups[taskWithNoTime.id]?.isDisplayableForecast == false)
    }

    @Test @MainActor
    func forecastDaysUseOnlyThisTasksHistoricalTrackedDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayOne = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 9)))
        let dayTwo = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 22, hour: 9)))
        let task = TaskNode(title: "Forecast Task", parentID: nil, deviceID: "test")
        let unrelated = TaskNode(title: "Unrelated", parentID: nil, deviceID: "test")
        let segments = [
            TimeSegment(sessionID: UUID(), taskID: task.id, source: .timer, deviceID: "test", startedAt: dayOne, endedAt: dayOne.addingTimeInterval(3_600)),
            TimeSegment(sessionID: UUID(), taskID: task.id, source: .timer, deviceID: "test", startedAt: dayTwo, endedAt: dayTwo.addingTimeInterval(7_200)),
            TimeSegment(sessionID: UUID(), taskID: unrelated.id, source: .timer, deviceID: "test", startedAt: dayOne, endedAt: dayOne.addingTimeInterval(36_000))
        ]
        let checklist = [
            ChecklistItem(taskID: task.id, title: "Done", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: task.id, title: "Todo 1", isCompleted: false, sortOrder: 20, deviceID: "test"),
            ChecklistItem(taskID: task.id, title: "Todo 2", isCompleted: false, sortOrder: 30, deviceID: "test"),
            ChecklistItem(taskID: task.id, title: "Todo 3", isCompleted: false, sortOrder: 40, deviceID: "test")
        ]

        let rollups = TaskRollupService().rollups(
            tasks: [task, unrelated],
            segments: segments,
            checklistItems: checklist,
            now: dayTwo.addingTimeInterval(10_000)
        )
        let rollup = try #require(rollups[task.id])

        #expect(rollup.workedSeconds == 10_800)
        #expect(rollup.estimatedTotalSeconds == 43_200)
        #expect(rollup.remainingSeconds == 32_400)
        #expect(rollup.historicalDailyAverageSeconds == 5_400)
        #expect(rollup.historicalActiveDayCount == 2)
        #expect(abs((rollup.projectedDays ?? 0) - 6.0) < 0.05)
    }

    @Test @MainActor
    func taskListRollupDurationsIncludeHistoricalDescendantTaskTime() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let parent = try taskRepository.createTask(title: "Parent", parentID: nil, colorHex: nil, iconName: nil)
        let child = try taskRepository.createTask(title: "Child", parentID: parent.id, colorHex: nil, iconName: nil)
        let grandchild = try taskRepository.createTask(title: "Grandchild", parentID: child.id, colorHex: nil, iconName: nil)
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        _ = try timeRepository.addManualSegment(
            taskID: parent.id,
            startedAt: startOfDay.addingTimeInterval(9 * 3_600),
            endedAt: startOfDay.addingTimeInterval(9 * 3_600 + 600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: child.id,
            startedAt: startOfDay.addingTimeInterval(10 * 3_600),
            endedAt: startOfDay.addingTimeInterval(10 * 3_600 + 900),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: grandchild.id,
            startedAt: startOfDay.addingTimeInterval(11 * 3_600),
            endedAt: startOfDay.addingTimeInterval(11 * 3_600 + 300),
            note: nil
        )
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay.addingTimeInterval(-86_400)
        _ = try timeRepository.addManualSegment(
            taskID: child.id,
            startedAt: yesterday.addingTimeInterval(14 * 3_600),
            endedAt: yesterday.addingTimeInterval(14 * 3_600 + 2_400),
            note: nil
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        #expect(store.secondsForTaskToday(parent) == 600)
        #expect(store.secondsForTaskTodayRollup(parent, now: now) == 1_800)
        #expect(store.secondsForTaskTodayRollup(child, now: now) == 1_200)
        #expect(store.secondsForTaskTotal(parent) == 600)
        #expect(store.secondsForTaskTotalRollup(parent, now: now) == 4_200)
        #expect(store.secondsForTaskTotalRollup(child, now: now) == 3_600)
        #expect(store.rollup(for: parent.id)?.workedSeconds == 4_200)
    }

    @Test @MainActor
    func taskRollupRecursivelyCombinesChecklistAndChildEstimates() throws {
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let child = TaskNode(title: "Child", parentID: parent.id, deviceID: "test")
        let grandchild = TaskNode(title: "Grandchild", parentID: child.id, deviceID: "test")
        grandchild.estimatedSeconds = 1_200
        let start = Date(timeIntervalSince1970: 10_000)
        let segments = [
            TimeSegment(sessionID: UUID(), taskID: parent.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(1_000)),
            TimeSegment(sessionID: UUID(), taskID: child.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(600)),
            TimeSegment(sessionID: UUID(), taskID: grandchild.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(300))
        ]
        let checklist = [
            ChecklistItem(taskID: parent.id, title: "One", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: parent.id, title: "Two", isCompleted: false, sortOrder: 20, deviceID: "test"),
            ChecklistItem(taskID: child.id, title: "A", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: child.id, title: "B", isCompleted: true, sortOrder: 20, deviceID: "test")
        ]

        let rollups = TaskRollupService().rollups(tasks: [parent, child, grandchild], segments: segments, checklistItems: checklist, now: start.addingTimeInterval(2_000))
        let parentRollup = try #require(rollups[parent.id])

        #expect(parentRollup.workedSeconds == 1_900)
        #expect(parentRollup.estimatedTotalSeconds == 2_900)
        #expect(parentRollup.remainingSeconds == 1_000)
        #expect(parentRollup.historicalDailyAverageSeconds == 1_900)
        #expect(parentRollup.historicalActiveDayCount == 1)
        #expect(abs((parentRollup.projectedDays ?? 0) - 0.53) < 0.05)
        #expect(parentRollup.checklistProgress.label == "1/2")
        #expect(parentRollup.confidence == .medium)
        #expect(parentRollup.forecastState == .ready)
    }

    @Test @MainActor
    func taskRollupHandlesMissingDataDeletedChecklistAndCompletedTasks() throws {
        let empty = TaskNode(title: "Empty", parentID: nil, deviceID: "test")
        let planned = TaskNode(title: "Planned", parentID: nil, deviceID: "test")
        planned.estimatedSeconds = 900
        let completed = TaskNode(title: "Done", parentID: nil, deviceID: "test")
        completed.status = .completed
        completed.estimatedSeconds = 3_600
        let deletedChecklist = ChecklistItem(taskID: planned.id, title: "Removed", isCompleted: true, sortOrder: 10, deviceID: "test")
        deletedChecklist.deletedAt = Date()

        let rollups = TaskRollupService().rollups(tasks: [empty, planned, completed], segments: [], checklistItems: [deletedChecklist])

        #expect(rollups[empty.id]?.estimatedTotalSeconds == nil)
        #expect(rollups[empty.id]?.confidence == ForecastConfidence.none)
        #expect(rollups[empty.id]?.forecastState == .needsChecklist)
        #expect(rollups[planned.id]?.checklistProgress.totalCount == 0)
        #expect(rollups[planned.id]?.estimatedTotalSeconds == nil)
        #expect(rollups[planned.id]?.forecastState == .needsChecklist)
        #expect(rollups[completed.id]?.remainingSeconds == 0)
        #expect(rollups[completed.id]?.forecastState == .completed)
    }

    @Test @MainActor
    func onlyChecklistBackedForecastsAreDisplayable() throws {
        let historyOnly = TaskNode(title: "History Only", parentID: nil, deviceID: "test")
        let manual = TaskNode(title: "Manual", parentID: nil, deviceID: "test")
        manual.estimatedSeconds = 1_800
        let checklistTask = TaskNode(title: "Checklist", parentID: nil, deviceID: "test")
        let start = Date(timeIntervalSince1970: 10_000)
        let segments = [
            TimeSegment(sessionID: UUID(), taskID: historyOnly.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(600)),
            TimeSegment(sessionID: UUID(), taskID: checklistTask.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(900))
        ]
        let checklist = [
            ChecklistItem(taskID: checklistTask.id, title: "Done", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: checklistTask.id, title: "Todo", isCompleted: false, sortOrder: 20, deviceID: "test")
        ]

        let rollups = TaskRollupService().rollups(
            tasks: [historyOnly, manual, checklistTask],
            segments: segments,
            checklistItems: checklist,
            now: start.addingTimeInterval(2_000)
        )

        #expect(rollups[historyOnly.id]?.forecastState == .needsChecklist)
        #expect(rollups[historyOnly.id]?.isDisplayableForecast == false)
        #expect(rollups[manual.id]?.forecastState == .needsChecklist)
        #expect(rollups[manual.id]?.isDisplayableForecast == false)
        #expect(rollups[checklistTask.id]?.isDisplayableForecast == true)
    }

    @Test @MainActor
    func forecastDisplayServiceDrillsIntoSingleChildButAggregatesMultipleChildren() throws {
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let firstChild = TaskNode(title: "First", parentID: parent.id, deviceID: "test")
        let secondChild = TaskNode(title: "Second", parentID: parent.id, deviceID: "test")
        let start = Date(timeIntervalSince1970: 20_000)
        let firstSegment = TimeSegment(sessionID: UUID(), taskID: firstChild.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(1_200))
        let secondSegment = TimeSegment(sessionID: UUID(), taskID: secondChild.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(600))
        let firstChecklist = [
            ChecklistItem(taskID: firstChild.id, title: "Done", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: firstChild.id, title: "Todo", isCompleted: false, sortOrder: 20, deviceID: "test")
        ]
        let firstOnlyRollups = TaskRollupService().rollups(
            tasks: [parent, firstChild, secondChild],
            segments: [firstSegment],
            checklistItems: firstChecklist,
            now: start.addingTimeInterval(2_000)
        )

        let firstOnlyDisplay = ForecastDisplayService().displayItems(
            tasks: [parent, firstChild, secondChild],
            rollups: firstOnlyRollups
        )
        #expect(firstOnlyDisplay.map(\.taskID) == [firstChild.id])

        let secondChecklist = [
            ChecklistItem(taskID: secondChild.id, title: "Done", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: secondChild.id, title: "Todo", isCompleted: false, sortOrder: 20, deviceID: "test")
        ]
        let multiRollups = TaskRollupService().rollups(
            tasks: [parent, firstChild, secondChild],
            segments: [firstSegment, secondSegment],
            checklistItems: firstChecklist + secondChecklist,
            now: start.addingTimeInterval(2_000)
        )

        let multiDisplay = ForecastDisplayService().displayItems(
            tasks: [parent, firstChild, secondChild],
            rollups: multiRollups
        )
        #expect(multiDisplay.map(\.taskID) == [parent.id])
        #expect(multiRollups[parent.id]?.forecastState == .aggregate)
        #expect(multiRollups[parent.id]?.forecastSourceTaskIDs.count == 2)
    }

    @Test @MainActor
    func parentForecastIncludesChildForecastsWhenOwnChecklistIsIncomplete() throws {
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let child = TaskNode(title: "Child", parentID: parent.id, deviceID: "test")
        let start = Date(timeIntervalSince1970: 30_000)
        let childSegment = TimeSegment(sessionID: UUID(), taskID: child.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(1_200))
        let checklist = [
            ChecklistItem(taskID: parent.id, title: "Parent todo", isCompleted: false, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: child.id, title: "Child done", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: child.id, title: "Child todo", isCompleted: false, sortOrder: 20, deviceID: "test")
        ]
        let rollups = TaskRollupService().rollups(
            tasks: [parent, child],
            segments: [childSegment],
            checklistItems: checklist,
            now: start.addingTimeInterval(2_000)
        )
        let parentRollup = try #require(rollups[parent.id])

        #expect(parentRollup.forecastState == .aggregate)
        #expect(parentRollup.remainingSeconds == 1_200)
        #expect(parentRollup.estimatedTotalSeconds == 2_400)
        #expect(parentRollup.forecastSourceTaskIDs == [child.id])
        #expect(parentRollup.forecastSourceLabel == String(format: AppStrings.localized("forecast.source.aggregate"), 1))
        #expect(ForecastDisplayService().displayItem(for: parent.id, tasks: [parent, child], rollups: rollups)?.taskID == parent.id)
        #expect(ForecastDisplayService().displayItems(tasks: [parent, child], rollups: rollups).map(\.taskID) == [parent.id])
    }

    @Test
    func monthAnalyticsUsesUniqueDayNumberLabels() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 28, hour: 12)))
        let points = AnalyticsEngine().dailyBreakdown(segments: [], range: .month, now: now, calendar: calendar)

        #expect(points.count == 30)
        #expect(Set(points.map(\.label)).count == points.count)
        #expect(points.first?.label == "1")
        #expect(points.last?.label == "30")
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = TimeTrackerModelRegistry.currentSchema
        let configuration = ModelConfiguration(
            "TimeTrackerTests",
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
