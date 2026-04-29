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
        let context = try makeTestContext()
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

        let pausedRegular = try #require(try timeRepository.allSegments().first { $0.id == regularSegment.id })
        #expect(pausedRegular.endedAt != nil)
    }

    @Test @MainActor
    func storeTimerActionsKeepPomodoroRunInSync() throws {
        let context = try makeTestContext()
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
}
