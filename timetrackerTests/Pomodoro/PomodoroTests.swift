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
        #expect(try timeRepository.sessions().first { $0.id == run.sessionID }?.endedAt != nil)
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
        try pomodoroRepository.completeFocus(runID: run.id)

        let session = try #require(try timeRepository.sessions().first { $0.id == run.sessionID })
        let updatedRun = try #require(try pomodoroRepository.runs().first { $0.id == run.id })
        #expect(session.endedAt != nil)
        #expect(updatedRun.state == .shortBreak)
        #expect(updatedRun.endedAt == nil)
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
        store.stop(segment: currentSegment)
        #expect(store.activeSegment(for: task.id) == nil)
        #expect(store.activePomodoroRun(for: task.id) == nil)
        let cancelledRun = try #require(store.pomodoroRuns.first { $0.taskID == task.id })
        #expect(cancelledRun.state == .cancelled)
        #expect(cancelledRun.startedAt == startedAt)
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
