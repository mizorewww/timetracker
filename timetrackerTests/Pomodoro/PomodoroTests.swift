import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct PomodoroTests {
    @Test @MainActor
    func pomodoroCreatesLedgerSegmentAndCompletesFocus() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository, deviceID: "test")
        let task = try taskRepository.createTask(title: "Focus", parentID: nil, colorHex: nil, iconName: nil)

        let run = try pomodoroRepository.startPomodoro(taskID: task.id, focusSeconds: 25 * 60, breakSeconds: 5 * 60, targetRounds: 1)
        let sessionID = try #require(run.sessionID)

        #expect(run.state == .focusing)
        #expect(run.longBreakSecondsPlanned == nil)
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
        #expect(try timeRepository.sessions().first { $0.id == sessionID }?.endedAt != nil)
    }

    @Test @MainActor
    func pomodoroStoresLongBreakPlanWhenStarting() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository, deviceID: "test")
        let task = try taskRepository.createTask(title: "Focus", parentID: nil, colorHex: nil, iconName: nil)

        let run = try pomodoroRepository.startPomodoro(
            taskID: task.id,
            focusSeconds: 30 * 60,
            breakSeconds: 10 * 60,
            longBreakSeconds: 20 * 60,
            targetRounds: 4
        )

        #expect(run.focusSecondsPlanned == 30 * 60)
        #expect(run.breakSecondsPlanned == 10 * 60)
        #expect(run.longBreakSecondsPlanned == 20 * 60)
        #expect(run.targetRounds == 4)
    }

    @Test @MainActor
    func pomodoroIntermediateRoundStopsSessionForBreak() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository, deviceID: "test")
        let task = try taskRepository.createTask(title: "Focus", parentID: nil, colorHex: nil, iconName: nil)

        let run = try pomodoroRepository.startPomodoro(taskID: task.id, focusSeconds: 25 * 60, breakSeconds: 5 * 60, targetRounds: 2)
        let firstSessionID = try #require(run.sessionID)
        try pomodoroRepository.completeFocus(runID: run.id)

        let session = try #require(try timeRepository.sessions().first { $0.id == firstSessionID })
        let updatedRun = try #require(try pomodoroRepository.runs().first { $0.id == run.id })
        #expect(session.endedAt != nil)
        #expect(updatedRun.state == .shortBreak)
        #expect(updatedRun.sessionID == nil)
        #expect(updatedRun.endedAt == nil)
        #expect(updatedRun.startedAt != nil)
    }

    @Test @MainActor
    func completingBreakStartsNextFocusRound() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository, deviceID: "test")
        let task = try taskRepository.createTask(title: "Focus", parentID: nil, colorHex: nil, iconName: nil)

        let run = try pomodoroRepository.startPomodoro(taskID: task.id, focusSeconds: 25 * 60, breakSeconds: 5 * 60, targetRounds: 2)
        try pomodoroRepository.completeFocus(runID: run.id)
        let breakStartedAt = try #require(run.startedAt)

        try pomodoroRepository.completeBreak(runID: run.id)

        let updatedRun = try #require(try pomodoroRepository.runs().first { $0.id == run.id })
        let activeSegment = try #require(try timeRepository.activeSegments().first)
        let focusStartedAt = try #require(updatedRun.startedAt)
        #expect(updatedRun.state == .focusing)
        #expect(updatedRun.completedFocusRounds == 1)
        #expect(updatedRun.sessionID == activeSegment.sessionID)
        #expect(focusStartedAt >= breakStartedAt)
        #expect(activeSegment.source == .pomodoro)
    }

    @Test @MainActor
    func repeatedBreakActivationCannotCompleteTheNewFocusRound() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Double activation",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        store.selectedTaskID = task.id
        store.startPomodoroForSelectedTask(
            focusSeconds: 25 * 60,
            breakSeconds: 5 * 60,
            targetRounds: 2
        )
        #expect(store.completeActivePomodoroFocus())

        let breakRun = try #require(store.activePomodoroRun)
        let expectedState = breakRun.state
        #expect(expectedState == .shortBreak)
        #expect(store.resumeActivePomodoroAfterBreak(
            runID: breakRun.id,
            expectedState: expectedState
        ))
        let resumedSegmentID = try #require(store.activeSegments.first?.id)

        #expect(store.resumeActivePomodoroAfterBreak(
            runID: breakRun.id,
            expectedState: expectedState
        ) == false)
        #expect(store.activePomodoroRun?.state == .focusing)
        #expect(store.activePomodoroRun?.completedFocusRounds == 1)
        #expect(store.activeSegments.map(\.id) == [resumedSegmentID])
        #expect(try timeRepository.allSegments().count == 2)
    }

    @Test @MainActor
    func resumingBreakStopsOtherTaskWhenParallelTimersAreDisabled() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let pomodoroTask = try taskRepository.createTask(
            title: "Pomodoro",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let otherTask = try taskRepository.createTask(
            title: "Interruption",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        store.preferences.allowParallelTimers = false
        store.selectedTaskID = pomodoroTask.id
        store.startPomodoroForSelectedTask(
            focusSeconds: 25 * 60,
            breakSeconds: 5 * 60,
            targetRounds: 2
        )
        #expect(store.completeActivePomodoroFocus())
        let breakRun = try #require(store.activePomodoroRun)
        let expectedState = breakRun.state

        store.startTask(otherTask)
        let otherSegment = try #require(store.activeSegments.first { $0.taskID == otherTask.id })
        #expect(store.resumeActivePomodoroAfterBreak(
            runID: breakRun.id,
            expectedState: expectedState
        ))

        #expect(otherSegment.endedAt != nil)
        #expect(store.activeSegments.count == 1)
        #expect(store.activeSegments.first?.taskID == pomodoroTask.id)
        #expect(store.activeSegments.first?.source == .pomodoro)
        #expect(store.activePomodoroRun?.state == .focusing)
    }

    @Test @MainActor
    func resumingBreakUsesCanonicalSegmentsWhenStoreCacheIsStale() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "external")
        let pomodoroTask = try taskRepository.createTask(
            title: "Pomodoro",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let externalTask = try taskRepository.createTask(
            title: "External timer",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        store.preferences.allowParallelTimers = false
        store.selectedTaskID = pomodoroTask.id
        store.startPomodoroForSelectedTask(
            focusSeconds: 25 * 60,
            breakSeconds: 5 * 60,
            targetRounds: 2
        )
        #expect(store.completeActivePomodoroFocus())
        let breakRun = try #require(store.activePomodoroRun)
        let expectedState = breakRun.state

        let externalSegment = try timeRepository.startTask(
            taskID: externalTask.id,
            source: .timer
        )
        #expect(store.activeSegments.contains { $0.id == externalSegment.id } == false)
        #expect(try timeRepository.activeSegments().contains { $0.id == externalSegment.id })

        #expect(store.resumeActivePomodoroAfterBreak(
            runID: breakRun.id,
            expectedState: expectedState
        ))

        #expect(externalSegment.endedAt != nil)
        let canonicalActiveSegments = try timeRepository.activeSegments()
        #expect(canonicalActiveSegments.count == 1)
        #expect(canonicalActiveSegments.first?.taskID == pomodoroTask.id)
        #expect(canonicalActiveSegments.first?.source == .pomodoro)
        #expect(store.activeSegments.map(\.id) == canonicalActiveSegments.map(\.id))
    }

    @Test @MainActor
    func staleBreakCommandDoesNotStopTimersWhenCanonicalRunAlreadyAdvanced() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroTask = try taskRepository.createTask(
            title: "Pomodoro",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let otherTask = try taskRepository.createTask(
            title: "Keep running",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        store.preferences.allowParallelTimers = false
        store.selectedTaskID = pomodoroTask.id
        store.startPomodoroForSelectedTask(
            focusSeconds: 25 * 60,
            breakSeconds: 5 * 60,
            targetRounds: 2
        )
        #expect(store.completeActivePomodoroFocus())
        let staleBreakRun = try #require(store.activePomodoroRun)
        let expectedState = staleBreakRun.state
        store.startTask(otherTask)
        let otherSegment = try #require(store.activeSegment(for: otherTask.id))

        let canonicalRun = PomodoroRun(
            taskID: staleBreakRun.taskID,
            focus: staleBreakRun.focusSecondsPlanned,
            breakSeconds: staleBreakRun.breakSecondsPlanned,
            longBreakSeconds: staleBreakRun.longBreakSecondsPlanned,
            targetRounds: staleBreakRun.targetRounds,
            deviceID: "remote"
        )
        canonicalRun.id = staleBreakRun.id
        canonicalRun.state = .completed
        canonicalRun.completedFocusRounds = canonicalRun.targetRounds
        canonicalRun.startedAt = staleBreakRun.startedAt
        canonicalRun.endedAt = staleBreakRun.updatedAt.addingTimeInterval(30)
        canonicalRun.createdAt = staleBreakRun.createdAt
        canonicalRun.updatedAt = staleBreakRun.updatedAt.addingTimeInterval(60)
        context.insert(canonicalRun)
        try context.save()

        #expect(store.activePomodoroRun?.state == .shortBreak)
        #expect(try store.requiredPomodoroRepository().run(id: staleBreakRun.id)?.state == .completed)
        #expect(store.resumeActivePomodoroAfterBreak(
            runID: staleBreakRun.id,
            expectedState: expectedState
        ) == false)

        #expect(otherSegment.endedAt == nil)
        #expect(try timeRepository.activeSegments().map(\.id) == [otherSegment.id])
        #expect(try timeRepository.allSegments().filter { $0.source == .pomodoro }.count == 1)
    }

    @Test @MainActor
    func staleFocusCommandReportsCanonicalNoOpWithoutStoppingLedger() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Already advanced",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        store.selectedTaskID = task.id
        store.startPomodoroForSelectedTask(
            focusSeconds: 25 * 60,
            breakSeconds: 5 * 60,
            targetRounds: 1
        )
        let staleFocusRun = try #require(store.activePomodoroRun)
        let focusSegment = try #require(store.activeSegment(for: task.id))

        let canonicalRun = PomodoroRun(
            taskID: staleFocusRun.taskID,
            focus: staleFocusRun.focusSecondsPlanned,
            breakSeconds: staleFocusRun.breakSecondsPlanned,
            longBreakSeconds: staleFocusRun.longBreakSecondsPlanned,
            targetRounds: staleFocusRun.targetRounds,
            deviceID: "remote"
        )
        canonicalRun.id = staleFocusRun.id
        canonicalRun.state = .completed
        canonicalRun.completedFocusRounds = canonicalRun.targetRounds
        canonicalRun.startedAt = staleFocusRun.startedAt
        canonicalRun.endedAt = staleFocusRun.updatedAt.addingTimeInterval(30)
        canonicalRun.createdAt = staleFocusRun.createdAt
        canonicalRun.updatedAt = staleFocusRun.updatedAt.addingTimeInterval(60)
        context.insert(canonicalRun)
        try context.save()

        #expect(store.activePomodoroRun?.state == .focusing)
        #expect(try store.requiredPomodoroRepository().run(id: staleFocusRun.id)?.state == .completed)
        #expect(store.completeActivePomodoroFocus() == false)
        #expect(focusSegment.endedAt == nil)
        #expect(try timeRepository.activeSegments().map(\.id) == [focusSegment.id])
    }

    @Test @MainActor
    func resumingBreakReplacesAnExistingTimerForTheSameTask() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Shared task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        store.preferences.allowParallelTimers = true
        store.selectedTaskID = task.id
        store.startPomodoroForSelectedTask(
            focusSeconds: 25 * 60,
            breakSeconds: 5 * 60,
            targetRounds: 2
        )
        #expect(store.completeActivePomodoroFocus())
        let breakRun = try #require(store.activePomodoroRun)
        let expectedState = breakRun.state

        store.startTask(task)
        let regularSegment = try #require(store.activeSegments.first)
        #expect(regularSegment.source == .timer)
        #expect(store.resumeActivePomodoroAfterBreak(
            runID: breakRun.id,
            expectedState: expectedState
        ))

        #expect(regularSegment.endedAt != nil)
        #expect(store.activeSegments.count == 1)
        #expect(store.activeSegments.first?.id != regularSegment.id)
        #expect(store.activeSegments.first?.taskID == task.id)
        #expect(store.activeSegments.first?.source == .pomodoro)
        #expect(store.activePomodoroRun?.state == .focusing)
    }

    @Test @MainActor
    func cancellingDuringBreakPreservesCompletedFocusHistory() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Focus", parentID: nil, colorHex: nil, iconName: nil)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.selectedTaskID = task.id

        store.startPomodoroForSelectedTask(focusSeconds: 25 * 60, breakSeconds: 5 * 60, targetRounds: 2)
        let run = try #require(store.activePomodoroRun)
        let focusSessionID = try #require(run.sessionID)
        store.completeActivePomodoroFocus()
        #expect(store.activePomodoroRun?.state == .shortBreak)

        store.cancelActivePomodoro()

        let cancelledRun = try #require(store.pomodoroRuns.first { $0.id == run.id })
        #expect(cancelledRun.state == .cancelled)
        #expect(cancelledRun.deletedAt == nil)
        #expect(store.allSegments.contains { $0.sessionID == focusSessionID && $0.deletedAt == nil })
        #expect(try timeRepository.sessions().contains { $0.id == focusSessionID && $0.deletedAt == nil })
    }

    @Test @MainActor
    func startingPomodoroStopsExistingTimerForSameTask() throws {
        let context = try makeTestContext()
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

        let stoppedRegular = try #require(try timeRepository.allSegments().first { $0.id == regularSegment.id })
        #expect(stoppedRegular.endedAt != nil)
    }

    @Test @MainActor
    func storeStoppingPomodoroTimerCancelsRun() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Synced Focus", parentID: nil, colorHex: nil, iconName: nil)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.selectedTaskID = task.id

        store.startPomodoroForSelectedTask(focusSeconds: 25 * 60, breakSeconds: 5 * 60, targetRounds: 1)
        let activeSegment = try #require(store.activeSegment(for: task.id))
        #expect(activeSegment.source == .pomodoro)
        let startedAt = Date().addingTimeInterval(-5 * 60)
        let activeRun = try #require(store.activePomodoroRun(for: task.id))
        activeRun.startedAt = startedAt
        activeSegment.startedAt = startedAt
        try context.save()
        store.refreshQuietly()
        let focusingRun = try #require(store.activePomodoroRun(for: task.id))
        #expect(focusingRun.state == .focusing)
        #expect(store.pomodoroRemainingSeconds(for: focusingRun) <= 20 * 60)

        let currentSegment = try #require(store.activeSegment(for: task.id))
        store.stop(segment: currentSegment)
        #expect(store.activeSegment(for: task.id) == nil)
        #expect(store.activePomodoroRun(for: task.id) == nil)
        let cancelledRun = try #require(store.pomodoroRuns.first { $0.taskID == task.id })
        #expect(cancelledRun.state == .cancelled)
        #expect(cancelledRun.startedAt == startedAt)
    }

    @Test @MainActor
    func genericStopSettlesExpiredPomodoroAtItsDeadline() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Expired Focus", parentID: nil, colorHex: nil, iconName: nil)
        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        store.selectedTaskID = task.id
        store.startPomodoroForSelectedTask(focusSeconds: 60, breakSeconds: 30, targetRounds: 1)

        let run = try #require(store.activePomodoroRun)
        let segment = try #require(store.activeSegment(for: task.id))
        let session = try #require(try timeRepository.sessions().first { $0.id == segment.sessionID })
        let phaseStartedAt = Date().addingTimeInterval(-120)
        let deadline = phaseStartedAt.addingTimeInterval(60)
        let originalSessionMutationID = session.clientMutationID
        run.startedAt = phaseStartedAt
        segment.startedAt = phaseStartedAt
        session.startedAt = phaseStartedAt
        session.deviceID = "stale-command-device"
        try context.save()

        store.stop(segment: segment)

        let persistedRun = try #require(
            try context.fetch(FetchDescriptor<PomodoroRun>()).first { $0.id == run.id }
        )
        let persistedSegment = try #require(
            try context.fetch(FetchDescriptor<TimeSegment>()).first { $0.id == segment.id }
        )
        let persistedSession = try #require(
            try context.fetch(FetchDescriptor<TimeSession>()).first { $0.id == session.id }
        )
        #expect(persistedRun.state == .completed)
        #expect(persistedRun.completedFocusRounds == 1)
        #expect(persistedRun.endedAt == deadline)
        #expect(persistedSegment.endedAt == deadline)
        #expect(persistedSession.endedAt == deadline)
        #expect(persistedSession.clientMutationID != originalSessionMutationID)
        #expect(persistedSession.deviceID == DeviceIdentity.current)
    }

    @Test @MainActor
    func cancellingPomodoroBelowTwentyPercentDiscardsRecordAndLedger() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Tiny Focus", parentID: nil, colorHex: nil, iconName: nil)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.selectedTaskID = task.id

        store.startPomodoroForSelectedTask(focusSeconds: 25 * 60, breakSeconds: 5 * 60, targetRounds: 1)
        let run = try #require(store.activePomodoroRun(for: task.id))
        let sessionID = try #require(run.sessionID)
        let segment = try #require(store.activeSegment(for: task.id))
        let startedAt = Date().addingTimeInterval(-4 * 60)
        run.startedAt = startedAt
        segment.startedAt = startedAt
        try context.save()
        store.refreshQuietly()

        store.cancelActivePomodoro()

        #expect(store.pomodoroRuns.contains { $0.id == run.id } == false)
        #expect(store.allSegments.contains { $0.sessionID == sessionID } == false)
        #expect(try timeRepository.allSegments().contains { $0.sessionID == sessionID } == false)
        #expect(try timeRepository.sessions().contains { $0.id == sessionID } == false)
    }

    @Test @MainActor
    func cancellingPomodoroStopsLedgerSession() throws {
        let context = try makeTestContext()
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
    func discardingAfterAClockRollbackNeverPersistsNegativePomodoroRanges() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(
            context: context,
            timeRepository: timeRepository,
            deviceID: "discard-device"
        )
        let task = try taskRepository.createTask(
            title: "Clock rollback focus",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let run = try pomodoroRepository.startPomodoro(
            taskID: task.id,
            focusSeconds: 600,
            breakSeconds: 60,
            targetRounds: 1
        )
        let sessionID = try #require(run.sessionID)
        let segment = try #require(try timeRepository.activeSegments().first { $0.sessionID == sessionID })
        let session = try #require(try timeRepository.sessions().first { $0.id == sessionID })
        let futureStart = Date().addingTimeInterval(3_600)
        run.startedAt = futureStart
        segment.startedAt = futureStart
        session.startedAt = futureStart
        try context.save()

        try pomodoroRepository.cancel(runID: run.id, discardRecord: true)

        let discardedRun = try #require(
            try context.fetch(FetchDescriptor<PomodoroRun>()).first { $0.id == run.id }
        )
        let discardedSegment = try #require(
            try context.fetch(FetchDescriptor<TimeSegment>()).first { $0.id == segment.id }
        )
        let discardedSession = try #require(
            try context.fetch(FetchDescriptor<TimeSession>()).first { $0.id == sessionID }
        )
        #expect(discardedRun.endedAt == futureStart)
        #expect(discardedSegment.endedAt == futureStart)
        #expect(discardedSession.endedAt == futureStart)
        #expect(discardedSegment.deviceID == "discard-device")
        #expect(discardedSession.deviceID == "discard-device")
    }

    @Test @MainActor
    func expiredFocusReconciliationClipsLedgerAtPersistedDeadline() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(
            context: context,
            timeRepository: timeRepository,
            deviceID: "test"
        )
        let task = try taskRepository.createTask(title: "Bounded Focus", parentID: nil, colorHex: nil, iconName: nil)
        let run = try pomodoroRepository.startPomodoro(
            taskID: task.id,
            focusSeconds: 60,
            breakSeconds: 30,
            targetRounds: 2
        )
        let sessionID = try #require(run.sessionID)
        let segment = try #require(try timeRepository.activeSegments().first { $0.sessionID == sessionID })
        let session = try #require(try timeRepository.sessions().first { $0.id == sessionID })
        let observedAt = Date()
        let phaseStartedAt = observedAt.addingTimeInterval(-3_600)
        let deadline = phaseStartedAt.addingTimeInterval(60)
        let originalSessionMutationID = session.clientMutationID
        run.startedAt = phaseStartedAt
        segment.startedAt = phaseStartedAt
        session.startedAt = phaseStartedAt
        session.deviceID = "stale-repository-device"
        try context.save()

        #expect(run.phaseDeadline == deadline)
        #expect(try pomodoroRepository.reconcileExpiredPhase(runID: run.id, now: observedAt))

        let reconciledRun = try #require(try pomodoroRepository.runs().first { $0.id == run.id })
        let stoppedSegment = try #require(try timeRepository.allSegments().first { $0.id == segment.id })
        let stoppedSession = try #require(try timeRepository.sessions().first { $0.id == sessionID })
        #expect(reconciledRun.state == .shortBreak)
        #expect(reconciledRun.startedAt == deadline)
        #expect(reconciledRun.sessionID == nil)
        #expect(stoppedSegment.endedAt == deadline)
        #expect(stoppedSession.endedAt == deadline)
        #expect(stoppedSegment.endedAt?.timeIntervalSince(stoppedSegment.startedAt) == 60)
        #expect(stoppedSession.clientMutationID != originalSessionMutationID)
        #expect(stoppedSession.deviceID == "test")
        #expect(try timeRepository.activeSegments().isEmpty)
    }

    @Test @MainActor
    func expiredBreakWaitsForExplicitContinuationAndNeverBackdatesFocus() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(
            context: context,
            timeRepository: timeRepository,
            deviceID: "test"
        )
        let task = try taskRepository.createTask(title: "Break Boundary", parentID: nil, colorHex: nil, iconName: nil)
        let run = try pomodoroRepository.startPomodoro(
            taskID: task.id,
            focusSeconds: 60,
            breakSeconds: 30,
            targetRounds: 2
        )
        let sessionID = try #require(run.sessionID)
        let segment = try #require(try timeRepository.activeSegments().first { $0.sessionID == sessionID })
        let phaseStartedAt = Date().addingTimeInterval(-120)
        run.startedAt = phaseStartedAt
        segment.startedAt = phaseStartedAt
        try context.save()
        let focusDeadline = phaseStartedAt.addingTimeInterval(60)
        try pomodoroRepository.completeFocus(runID: run.id, endedAt: focusDeadline)
        let longAfterBreak = focusDeadline.addingTimeInterval(3_600)

        #expect(try pomodoroRepository.reconcileExpiredPhase(runID: run.id, now: longAfterBreak) == false)
        let waitingRun = try #require(try pomodoroRepository.runs().first { $0.id == run.id })
        #expect(waitingRun.state == .shortBreak)
        #expect(waitingRun.phaseHasExpired(at: longAfterBreak))
        #expect(waitingRun.sessionID == nil)
        #expect(try timeRepository.activeSegments().isEmpty)
    }

    @Test @MainActor
    func storeStartupReconcilesExpiredFocusWithoutOpeningPomodoroView() throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Startup Focus", parentID: nil, deviceID: "test")
        let phaseStartedAt = Date().addingTimeInterval(-3_600)
        let session = TimeSession(
            taskID: task.id,
            source: .pomodoro,
            deviceID: "test",
            startedAt: phaseStartedAt,
            titleSnapshot: task.title
        )
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .pomodoro,
            deviceID: "test",
            startedAt: phaseStartedAt
        )
        let run = PomodoroRun(
            taskID: task.id,
            focus: 60,
            breakSeconds: 30,
            targetRounds: 2,
            deviceID: "test"
        )
        run.sessionID = session.id
        run.startedAt = phaseStartedAt
        run.state = .focusing
        context.insert(task)
        context.insert(session)
        context.insert(segment)
        context.insert(run)
        try context.save()

        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)

        let deadline = phaseStartedAt.addingTimeInterval(60)
        #expect(store.activePomodoroRun?.state == .shortBreak)
        #expect(store.activePomodoroRun?.startedAt == deadline)
        #expect(store.activeSegments.isEmpty)
        #expect(store.allSegments.first { $0.id == segment.id }?.endedAt == deadline)
    }

    @Test @MainActor
    func storeForegroundReconcilesFocusThatExpiredWhileSuspended() async throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Suspended Focus",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        store.selectedTaskID = task.id
        store.startPomodoroForSelectedTask(focusSeconds: 60, breakSeconds: 30, targetRounds: 2)

        let run = try #require(store.activePomodoroRun)
        let sessionID = try #require(run.sessionID)
        let session = try #require(try timeRepository.sessions().first { $0.id == sessionID })
        let segment = try #require(try timeRepository.activeSegments().first { $0.sessionID == sessionID })
        let phaseStartedAt = Date().addingTimeInterval(-120)
        run.startedAt = phaseStartedAt
        session.startedAt = phaseStartedAt
        segment.startedAt = phaseStartedAt
        try context.save()

        await store.refreshForForeground()

        let deadline = phaseStartedAt.addingTimeInterval(60)
        let reconciledRun = try #require(try store.requiredPomodoroRepository().runs().first { $0.id == run.id })
        let stoppedSession = try #require(try timeRepository.sessions().first { $0.id == sessionID })
        let stoppedSegment = try #require(try timeRepository.allSegments().first { $0.id == segment.id })
        #expect(reconciledRun.state == .shortBreak)
        #expect(reconciledRun.startedAt == deadline)
        #expect(reconciledRun.sessionID == nil)
        #expect(stoppedSession.endedAt == deadline)
        #expect(stoppedSegment.endedAt == deadline)
        #expect(try timeRepository.activeSegments().isEmpty)
    }

    @Test @MainActor
    func storeStartupReconcilesEveryExpiredFocusFromCrossDeviceMerge() throws {
        let context = try makeTestContext()
        let now = Date()
        let phaseStarts = [
            now.addingTimeInterval(-180),
            now.addingTimeInterval(-120),
        ]
        var fixtures: [(runID: UUID, sessionID: UUID, segmentID: UUID, deadline: Date)] = []

        for (index, phaseStartedAt) in phaseStarts.enumerated() {
            let task = TaskNode(title: "Merged Focus \(index)", parentID: nil, deviceID: "remote")
            let session = TimeSession(
                taskID: task.id,
                source: .pomodoro,
                deviceID: "remote",
                startedAt: phaseStartedAt,
                titleSnapshot: task.title
            )
            let segment = TimeSegment(
                sessionID: session.id,
                taskID: task.id,
                source: .pomodoro,
                deviceID: "remote",
                startedAt: phaseStartedAt
            )
            let run = PomodoroRun(
                taskID: task.id,
                focus: 60,
                breakSeconds: 30,
                targetRounds: 2,
                deviceID: "remote"
            )
            run.sessionID = session.id
            run.startedAt = phaseStartedAt
            run.state = .focusing
            context.insert(task)
            context.insert(session)
            context.insert(segment)
            context.insert(run)
            fixtures.append((run.id, session.id, segment.id, phaseStartedAt.addingTimeInterval(60)))
        }
        try context.save()

        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)

        let persistedRuns = try store.requiredPomodoroRepository().runs()
        let timeRepository = try store.requiredTimeRepository()
        let persistedSessions = try timeRepository.sessions()
        let persistedSegments = try timeRepository.allSegments()
        for fixture in fixtures {
            let run = try #require(persistedRuns.first { $0.id == fixture.runID })
            let session = try #require(persistedSessions.first { $0.id == fixture.sessionID })
            let segment = try #require(persistedSegments.first { $0.id == fixture.segmentID })
            #expect(run.state == .shortBreak)
            #expect(run.startedAt == fixture.deadline)
            #expect(run.sessionID == nil)
            #expect(session.endedAt == fixture.deadline)
            #expect(segment.endedAt == fixture.deadline)
        }
        #expect(try timeRepository.activeSegments().isEmpty)
    }

    @Test @MainActor
    func activePomodoroSegmentEditRebindsRunAndSessionAtomically() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(title: "First", parentID: nil, colorHex: nil, iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Second", parentID: nil, colorHex: nil, iconName: nil)
        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        store.selectedTaskID = firstTask.id
        store.startPomodoroForSelectedTask(focusSeconds: 600, breakSeconds: 60, targetRounds: 1)
        let segment = try #require(store.activeSegment(for: firstTask.id))
        let activeRun = try #require(store.activePomodoroRun)
        let runID = activeRun.id
        activeRun.deviceID = "stale-device"
        try context.save()
        let revisedStart = Date().addingTimeInterval(-30)
        var draft = SegmentEditorDraft(segment: segment, note: "")
        draft.taskID = secondTask.id
        draft.startedAt = revisedStart

        #expect(store.saveSegmentDraft(draft))

        let run = try #require(store.pomodoroRuns.first { $0.id == runID })
        let editedSegment = try #require(store.activeSegments.first { $0.id == segment.id })
        let session = try #require(store.sessions.first { $0.id == segment.sessionID })
        #expect(run.taskID == secondTask.id)
        #expect(run.startedAt == revisedStart)
        #expect(run.deviceID == DeviceIdentity.current)
        #expect(editedSegment.taskID == secondTask.id)
        #expect(editedSegment.startedAt == revisedStart)
        #expect(session.taskID == secondTask.id)
        #expect(session.titleSnapshot == secondTask.title)
        #expect(session.startedAt == revisedStart)
    }

    @Test @MainActor
    func closingActivePomodoroSegmentRebindsItsHistoryBeforeCancelling() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(title: "Original", parentID: nil, colorHex: nil, iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Rebound", parentID: nil, colorHex: nil, iconName: nil)
        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        store.selectedTaskID = firstTask.id
        store.startPomodoroForSelectedTask(focusSeconds: 600, breakSeconds: 60, targetRounds: 1)
        let segment = try #require(store.activeSegment(for: firstTask.id))
        let runID = try #require(store.activePomodoroRun?.id)
        let revisedEnd = Date()
        let revisedStart = revisedEnd.addingTimeInterval(-180)
        var draft = SegmentEditorDraft(segment: segment, note: "")
        draft.taskID = secondTask.id
        draft.startedAt = revisedStart
        draft.endedAt = revisedEnd
        draft.isActive = false

        #expect(store.saveSegmentDraft(draft))

        let run = try #require(store.pomodoroRuns.first { $0.id == runID })
        let editedSegment = try #require(store.allSegments.first { $0.id == segment.id })
        let session = try #require(store.sessions.first { $0.id == segment.sessionID })
        #expect(run.state == .cancelled)
        #expect(run.taskID == secondTask.id)
        #expect(run.startedAt == revisedStart)
        #expect(run.deletedAt == nil)
        #expect(editedSegment.taskID == secondTask.id)
        #expect(editedSegment.startedAt == revisedStart)
        #expect(editedSegment.endedAt == revisedEnd)
        #expect(session.taskID == secondTask.id)
        #expect(session.titleSnapshot == secondTask.title)
        #expect(session.startedAt == revisedStart)
        #expect(session.endedAt == revisedEnd)
    }

    @Test @MainActor
    func deletingActivePomodoroSegmentAlsoTombstonesItsRun() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Delete Focus", parentID: nil, colorHex: nil, iconName: nil)
        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        store.selectedTaskID = task.id
        store.startPomodoroForSelectedTask(focusSeconds: 600, breakSeconds: 60, targetRounds: 1)
        let segment = try #require(store.activeSegment(for: task.id))
        let runID = try #require(store.activePomodoroRun?.id)

        #expect(store.deleteSegment(segment.id))

        let persistedRun = try #require(
            try context.fetch(FetchDescriptor<PomodoroRun>()).first { $0.id == runID }
        )
        let persistedSegment = try #require(
            try context.fetch(FetchDescriptor<TimeSegment>()).first { $0.id == segment.id }
        )
        #expect(persistedRun.state == .cancelled)
        #expect(persistedRun.deletedAt != nil)
        #expect(persistedSegment.deletedAt != nil)
        #expect(store.activePomodoroRun == nil)
        #expect(store.activeSegments.isEmpty)
    }

    @Test @MainActor
    func deletingExpiredActivePomodoroSegmentStillTombstonesRunInsteadOfCompletingIt() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Delete Expired", parentID: nil, colorHex: nil, iconName: nil)
        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        store.selectedTaskID = task.id
        store.startPomodoroForSelectedTask(focusSeconds: 60, breakSeconds: 30, targetRounds: 1)
        let segment = try #require(store.activeSegment(for: task.id))
        let run = try #require(store.activePomodoroRun)
        let phaseStartedAt = Date().addingTimeInterval(-120)
        run.startedAt = phaseStartedAt
        segment.startedAt = phaseStartedAt
        try context.save()

        #expect(store.deleteSegment(segment.id))

        let persistedRun = try #require(
            try context.fetch(FetchDescriptor<PomodoroRun>()).first { $0.id == run.id }
        )
        let persistedSegment = try #require(
            try context.fetch(FetchDescriptor<TimeSegment>()).first { $0.id == segment.id }
        )
        #expect(persistedRun.state == .cancelled)
        #expect(persistedRun.deletedAt != nil)
        #expect(persistedRun.completedFocusRounds == 0)
        #expect(persistedSegment.deletedAt != nil)
        #expect(store.activePomodoroRun == nil)
    }

    @Test @MainActor
    func deletingTaskTreeStopsAllTimersAndPreservesPomodoroHistory() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let parent = try taskRepository.createTask(title: "Parent", parentID: nil, colorHex: nil, iconName: nil)
        let child = try taskRepository.createTask(title: "Child", parentID: parent.id, colorHex: nil, iconName: nil)
        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        store.preferences.allowParallelTimers = true
        store.startTask(parent)
        let regularSegmentID = try #require(store.activeSegment(for: parent.id)?.id)
        store.selectedTaskID = child.id
        store.startPomodoroForSelectedTask(focusSeconds: 600, breakSeconds: 60, targetRounds: 1)
        let run = try #require(store.activePomodoroRun(for: child.id))
        let runID = run.id
        let pomodoroSessionID = try #require(run.sessionID)
        let pomodoroSegmentID = try #require(store.activeSegment(for: child.id)?.id)

        store.deleteSelectedTask(taskID: parent.id)

        let persistedRun = try #require(
            try context.fetch(FetchDescriptor<PomodoroRun>()).first { $0.id == runID }
        )
        let persistedSegments = try context.fetch(FetchDescriptor<TimeSegment>())
        let persistedSessions = try context.fetch(FetchDescriptor<TimeSession>())
        let deletedTasks = try context.fetch(FetchDescriptor<TaskNode>())
            .filter { $0.id == parent.id || $0.id == child.id }
        #expect(deletedTasks.allSatisfy { $0.deletedAt != nil })
        #expect(store.tasks.isEmpty)
        #expect(store.activeSegments.isEmpty)
        #expect(persistedSegments.first { $0.id == regularSegmentID }?.endedAt != nil)
        #expect(persistedSegments.first { $0.id == regularSegmentID }?.deletedAt == nil)
        #expect(persistedSegments.first { $0.id == pomodoroSegmentID }?.endedAt != nil)
        #expect(persistedSegments.first { $0.id == pomodoroSegmentID }?.deletedAt == nil)
        #expect(persistedSessions.first { $0.id == pomodoroSessionID }?.endedAt != nil)
        #expect(persistedSessions.first { $0.id == pomodoroSessionID }?.deletedAt == nil)
        #expect(persistedRun.state == .cancelled)
        #expect(persistedRun.deletedAt == nil)
        #expect(persistedRun.endedAt != nil)
    }

    @Test @MainActor
    func deletingTaskCancelsPomodoroThatIsWaitingInBreak() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Break Task", parentID: nil, colorHex: nil, iconName: nil)
        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        store.selectedTaskID = task.id
        store.startPomodoroForSelectedTask(focusSeconds: 600, breakSeconds: 60, targetRounds: 2)
        let runID = try #require(store.activePomodoroRun?.id)
        #expect(store.completeActivePomodoroFocus())
        #expect(store.activePomodoroRun?.state == .shortBreak)
        #expect(store.activeSegments.isEmpty)

        store.deleteSelectedTask(taskID: task.id)

        let persistedRun = try #require(
            try context.fetch(FetchDescriptor<PomodoroRun>()).first { $0.id == runID }
        )
        #expect(persistedRun.state == .cancelled)
        #expect(persistedRun.deletedAt == nil)
        #expect(persistedRun.completedFocusRounds == 1)
        #expect(persistedRun.endedAt != nil)
        #expect(store.activePomodoroRun == nil)
    }

    @Test @MainActor
    func legacyPlanSystemClockFieldIsIgnoredAndNotReencoded() throws {
        let legacyJSON = #"""
        {
          "name": "Legacy",
          "focusMinutes": 25,
          "shortBreakMinutes": 5,
          "longBreakMinutes": 15,
          "rounds": 4,
          "allowsSystemClock": true
        }
        """#

        let plan = try JSONDecoder().decode(PomodoroPlan.self, from: Data(legacyJSON.utf8))
        let encoded = try JSONEncoder().encode(plan)
        let encodedText = try #require(String(data: encoded, encoding: .utf8))
        #expect(plan.displayName == "Legacy")
        #expect(encodedText.contains("allowsSystemClock") == false)
    }
}
