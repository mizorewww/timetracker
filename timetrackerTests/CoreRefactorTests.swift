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
    func refreshPlannerMapsUserMutationsToDomainSizedScopes() {
        let planner = StoreRefreshPlanner()

        #expect(planner.scopes(after: [.checklist]) == [.checklist, .rollups, .analytics])
        #expect(planner.scopes(after: [.taskTree]) == [.tasks, .rollups, .analytics, .liveActivities])
        #expect(planner.scopes(after: [.timer]) == [.ledgerVisible, .pomodoro, .rollups, .analytics, .liveActivities])
        #expect(planner.scopes(after: [.pomodoro]) == [.ledgerVisible, .pomodoro, .rollups, .analytics, .liveActivities])
        #expect(planner.scopes(after: [.ledgerHistory]) == [.ledgerHistory, .rollups, .analytics, .liveActivities])
        #expect(planner.scopes(after: [.preferences]) == [.preferences])
        #expect(planner.scopes(after: [.allData]) == StoreRefreshScope.full)
    }

    @Test @MainActor
    func refreshPlannerCoalescesMultipleMutationsWithoutEscalatingToFullRefresh() {
        let scopes = StoreRefreshPlanner().scopes(after: [.taskTree, .checklist, .timer])

        #expect(scopes.contains(.tasks))
        #expect(scopes.contains(.checklist))
        #expect(scopes.contains(.ledgerVisible))
        #expect(scopes.contains(.rollups))
        #expect(scopes.contains(.analytics))
        #expect(scopes.contains(.preferences) == false)
        #expect(scopes != StoreRefreshScope.full)
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
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sidebarSource = try String(contentsOf: projectRoot.appending(path: "timetracker/SidebarInspectorViews.swift"), encoding: .utf8)

        #expect(sidebarSource.contains("store.taskTreeRows(expandedTaskIDs: expansionState.expandedTaskIDs)"))
        #expect(sidebarSource.contains("DisclosureGroup(") == false)
    }

    @Test
    func enumDisplayTextUsesLocalizationKeys() throws {
        #expect(AnalyticsRange.today.displayName == AppStrings.localized("analytics.range.today"))
        #expect(TimeSessionSource.importCalendar.displayName == AppStrings.localized("source.calendar"))

        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let analyticsSource = try String(contentsOf: projectRoot.appending(path: "timetracker/AnalyticsViews.swift"), encoding: .utf8)
        let storeSource = try String(contentsOf: projectRoot.appending(path: "timetracker/TimeTrackerStore.swift"), encoding: .utf8)

        #expect(analyticsSource.contains("Text(range.rawValue)") == false)
        #expect(storeSource.contains("return \"Ready\"") == false)
        #expect(storeSource.contains("return \"Focus\"") == false)
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
