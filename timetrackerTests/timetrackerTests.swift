import Foundation
import SwiftData
import Testing
@testable import timetracker

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

        let root = try repository.createTask(title: "Root", kind: .project, parentID: nil, colorHex: nil, iconName: nil)
        let child = try repository.createTask(title: "Child", kind: .task, parentID: root.id, colorHex: nil, iconName: nil)

        try repository.moveTask(taskID: root.id, newParentID: child.id, sortOrder: 10)
        #expect((try repository.task(id: root.id))?.parentID == nil)

        try repository.moveTask(taskID: child.id, newParentID: nil, sortOrder: 20)
        let movedTask = try repository.task(id: child.id)
        let moved = try #require(movedTask)
        #expect(moved.parentID == nil)
        #expect(moved.depth == 0)
    }

    @Test @MainActor
    func timerPauseResumeStopUsesSegmentsAsLedger() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Design", kind: .task, parentID: nil, colorHex: nil, iconName: nil)

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
        let firstTask = try taskRepository.createTask(title: "Design", kind: .task, parentID: nil, colorHex: nil, iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Writing", kind: .task, parentID: nil, colorHex: nil, iconName: nil)

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
    func analyticsOverviewBreakdownAndOverlapUseSegments() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(title: "Coding", kind: .task, parentID: nil, colorHex: "1677FF", iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Meeting", kind: .task, parentID: nil, colorHex: "EF4444", iconName: nil)
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

        let overlaps = store.overlapSegments(range: .week, now: now)
        #expect(overlaps.first?.durationSeconds == 1_800)
    }

    @Test @MainActor
    func quickStartRecentTasksRankByFrequencyAndSkipPinnedTasks() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pinnedTask = try taskRepository.createTask(title: "Pinned", kind: .task, parentID: nil, colorHex: nil, iconName: nil)
        let frequentTask = try taskRepository.createTask(title: "Frequent", kind: .task, parentID: nil, colorHex: nil, iconName: nil)
        let occasionalTask = try taskRepository.createTask(title: "Occasional", kind: .task, parentID: nil, colorHex: nil, iconName: nil)
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
        let task = try taskRepository.createTask(title: "Design", kind: .task, parentID: nil, colorHex: nil, iconName: nil)
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
        let firstTask = try taskRepository.createTask(title: "Coding", kind: .task, parentID: nil, colorHex: nil, iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Meeting", kind: .task, parentID: nil, colorHex: nil, iconName: nil)
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
        let task = try taskRepository.createTask(title: "Client Research", kind: .task, parentID: nil, colorHex: "1677FF", iconName: nil)
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
    func optimizeDatabaseDeletesLedgerRowsForSoftDeletedTasks() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Temporary Client", kind: .task, parentID: nil, colorHex: nil, iconName: nil)
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

        #expect(removedCount == 2)
        #expect(try timeRepository.allSegments().isEmpty)
        #expect(try timeRepository.sessions().isEmpty)
    }

    @Test @MainActor
    func manualSegmentStoresAndUpdatesSessionNote() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Writing", kind: .task, parentID: nil, colorHex: nil, iconName: nil)
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
        let task = try taskRepository.createTask(title: "Focus", kind: .task, parentID: nil, colorHex: nil, iconName: nil)

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
    }

    @Test @MainActor
    func startingPomodoroPausesExistingTimerForSameTask() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository, deviceID: "test")
        let task = try taskRepository.createTask(title: "Shared Task", kind: .task, parentID: nil, colorHex: nil, iconName: nil)

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
        let task = try taskRepository.createTask(title: "Synced Focus", kind: .task, parentID: nil, colorHex: nil, iconName: nil)
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        store.selectedTaskID = task.id

        store.startPomodoroForSelectedTask(focusSeconds: 25 * 60, breakSeconds: 5 * 60, targetRounds: 1)
        let activeSegment = try #require(store.activeSegment(for: task.id))
        #expect(activeSegment.source == .pomodoro)
        #expect(store.activePomodoroRun(for: task.id)?.state == .focusing)

        store.pause(segment: activeSegment)
        #expect(store.activeSegment(for: task.id) == nil)
        #expect(store.pausedSession(for: task.id) != nil)
        #expect(store.activePomodoroRun(for: task.id)?.state == .interrupted)

        let pausedSession = try #require(store.pausedSession(for: task.id))
        store.resume(session: pausedSession)
        #expect(store.activeSegment(for: task.id)?.source == .pomodoro)
        #expect(store.activePomodoroRun(for: task.id)?.state == .focusing)

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
        let task = try taskRepository.createTask(title: "Focus", kind: .task, parentID: nil, colorHex: nil, iconName: nil)

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
        let oldTask = try taskRepository.createTask(title: "Temporary Task", kind: .task, parentID: nil, colorHex: nil, iconName: nil)
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
        let userTask = try taskRepository.createTask(title: "Real Work", kind: .task, parentID: nil, colorHex: nil, iconName: nil)
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
        let task = TaskNode(title: "Defaults", kind: .task, parentID: nil, deviceID: "test")
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test")
        let segment = TimeSegment(sessionID: session.id, taskID: task.id, source: .timer, deviceID: "test")
        let run = PomodoroRun(taskID: task.id, deviceID: "test")
        let summary = DailySummary(date: Date(), taskID: task.id, grossSeconds: 0, wallClockSeconds: 0, pomodoroCount: 0, interruptionCount: 0)
        let countdown = CountdownEvent(title: "Launch", date: Date(), deviceID: "test")

        context.insert(task)
        context.insert(session)
        context.insert(segment)
        context.insert(run)
        context.insert(summary)
        context.insert(countdown)
        try context.save()

        #expect(task.id.uuidString.isEmpty == false)
        #expect(task.status == .active)
        #expect(segment.source == .timer)
        #expect(run.state == .planned)
        #expect(summary.version == 1)
        #expect(countdown.deletedAt == nil)
    }

    @Test @MainActor
    func taskStatusCanBePlannedAndCompleted() throws {
        let context = try makeContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try repository.createTask(title: "Plan draft", kind: .task, parentID: nil, colorHex: nil, iconName: nil)

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
        let task = try taskRepository.createTask(title: "CSV Task", kind: .task, parentID: nil, colorHex: nil, iconName: nil)
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
    func swiftSourcesDoNotContainHardCodedChineseText() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = projectRoot.appending(path: "timetracker")
        let enumerator = try #require(FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil))
        let swiftFiles = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
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
        #expect(homeSource.contains("limit: max(0, 3 - pinnedTasks.count)"))
        #expect(homeSource.contains("QuickStartTaskButton"))
        #expect(storeSource.contains("func frequentRecentTasks(excluding excludedIDs: Set<UUID> = [], limit: Int = 3)"))
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
    func taskTreeUsesNativeDisclosureRowsInsteadOfCustomChevronLayout() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: projectRoot.appending(path: "timetracker/TasksViews.swift"), encoding: .utf8)

        #expect(source.contains("DisclosureGroup(isExpanded:"))
        #expect(source.contains("TaskManagementVisibleRow") == false)
        #expect(source.contains("TaskTreeDisplayRow") == false)
        #expect(source.contains("rotationEffect") == false)
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            TaskNode.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self,
            CountdownEvent.self
        ])
        let configuration = ModelConfiguration(
            "TimeTrackerTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
