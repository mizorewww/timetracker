import Foundation
import SwiftData

@MainActor
final class SwiftDataPomodoroRepository {
    private let context: ModelContext
    private let timeRepository: SwiftDataTimeTrackingRepository
    private let deviceID: String
    private let nowProvider: () -> Date

    init(
        context: ModelContext,
        timeRepository: SwiftDataTimeTrackingRepository,
        deviceID: String? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.timeRepository = timeRepository
        self.deviceID = deviceID ?? DeviceIdentity.current
        self.nowProvider = nowProvider
    }

    func run(id: UUID) throws -> PomodoroRun? {
        try canonicalRuns(ids: [id]).first
    }

    func runs() throws -> [PomodoroRun] {
        try context.fetch(FetchDescriptor<PomodoroRun>())
            .visibleDeduplicatedByID()
            .sorted(byKey: \.creationOrderKey, by: DatedIdentityOrder.newestFirst)
    }

    func runs(ids: Set<UUID>) throws -> [PomodoroRun] {
        try canonicalRuns(ids: ids).sorted(byKey: \.creationOrderKey, by: DatedIdentityOrder.newestFirst)
    }

    /// Timer stop commands only need open runs attached to the sessions they
    /// are actually closing. Fetching the open working set once avoids both a
    /// user's entire Pomodoro history and one query per stopped session.
    func openRuns(sessionIDs: Set<UUID>) throws -> [PomodoroRun] {
        guard sessionIDs.isEmpty == false else { return [] }
        let descriptor = FetchDescriptor<PomodoroRun>(
            predicate: #Predicate {
                $0.endedAt == nil && $0.deletedAt == nil
            }
        )
        let candidateIDs = try Set(context.fetch(descriptor).map(\.id))
        return try canonicalRuns(ids: candidateIDs)
            .filter {
                $0.endedAt == nil &&
                    $0.sessionID.map(sessionIDs.contains) == true
            }
            .sorted(byKey: \.creationOrderKey, by: DatedIdentityOrder.newestFirst)
    }

    func activeRuns() throws -> [PomodoroRun] {
        let completed = PomodoroState.completed.rawValue
        let cancelled = PomodoroState.cancelled.rawValue
        let descriptor = FetchDescriptor<PomodoroRun>(
            predicate: #Predicate {
                $0.endedAt == nil &&
                    $0.stateRaw != completed &&
                    $0.stateRaw != cancelled
            }
        )
        let candidateIDs = try Set(context.fetch(descriptor).map(\.id))
        return try canonicalRuns(ids: candidateIDs)
            .filter {
                $0.endedAt == nil &&
                    $0.stateRaw != completed &&
                    $0.stateRaw != cancelled
            }
            .sorted(byKey: \.creationOrderKey, by: DatedIdentityOrder.newestFirst)
    }

    @discardableResult
    func startPomodoro(taskID: UUID, focusSeconds: Int, breakSeconds: Int, longBreakSeconds: Int? = nil, targetRounds: Int) throws -> PomodoroRun {
        try context.performAtomicMutation {
            let now = nowProvider()
            for existingRun in try activeRuns() {
                if existingRun.phaseHasExpired(at: now),
                   existingRun.state == .focusing || existingRun.state == .interrupted,
                   let deadline = existingRun.phaseDeadline
                {
                    try completeFocusMutation(
                        existingRun,
                        endedAt: deadline,
                        mutationDate: now
                    )
                }
                if existingRun.state == .completed {
                    continue
                }
                if let sessionID = existingRun.sessionID {
                    try timeRepository.stopSession(sessionID: sessionID)
                }
                existingRun.state = .cancelled
                existingRun.endedAt = existingRun.startedAt.map { max(now, $0) } ?? now
                existingRun.markMutated(at: now, deviceID: deviceID)
            }
            for segment in try timeRepository.activeSegments().filter({ $0.taskID == taskID }) {
                try timeRepository.stopSession(sessionID: segment.sessionID)
            }

            let run = PomodoroRun(
                taskID: taskID,
                focus: max(1, focusSeconds),
                breakSeconds: max(1, breakSeconds),
                longBreakSeconds: longBreakSeconds.map { max(1, $0) },
                targetRounds: max(1, targetRounds),
                deviceID: deviceID
            )
            let segment = try timeRepository.startTask(taskID: taskID, source: .pomodoro)
            run.sessionID = segment.sessionID
            run.startedAt = segment.startedAt
            run.state = .focusing
            run.createdAt = now
            run.updatedAt = now
            context.insert(run)
            return run
        }
    }

    @discardableResult
    func completeFocus(
        runID: UUID,
        expectedState: PomodoroState,
        endedAt requestedEndDate: Date
    ) throws -> Bool {
        guard expectedState == .focusing || expectedState == .interrupted else {
            return false
        }
        return try context.performAtomicMutation {
            guard let run = try run(id: runID),
                  run.state == expectedState,
                  run.deletedAt == nil,
                  run.endedAt == nil
            else {
                return false
            }
            try completeFocusMutation(
                run,
                endedAt: requestedEndDate,
                mutationDate: nowProvider()
            )
            return true
        }
    }

    @discardableResult
    func completeBreak(
        runID: UUID,
        expectedState: PomodoroState
    ) throws -> Bool {
        guard expectedState == .shortBreak || expectedState == .longBreak else {
            return false
        }
        return try context.performAtomicMutation {
            guard let run = try run(id: runID),
                  run.state == expectedState,
                  run.deletedAt == nil,
                  run.endedAt == nil
            else {
                return false
            }
            let now = nowProvider()
            let segment = try timeRepository.startTask(taskID: run.taskID, source: .pomodoro)
            run.sessionID = segment.sessionID
            run.startedAt = segment.startedAt
            run.state = .focusing
            run.endedAt = nil
            run.markMutated(at: now, deviceID: deviceID)
            return true
        }
    }

    @discardableResult
    func reconcileExpiredPhase(runID: UUID, now: Date) throws -> Bool {
        guard let run = try run(id: runID),
              run.state == .focusing || run.state == .interrupted,
              let deadline = run.phaseDeadline,
              deadline <= now
        else {
            return false
        }
        return try completeFocus(
            runID: run.id,
            expectedState: run.state,
            endedAt: deadline
        )
    }

    func cancel(runID: UUID, discardRecord: Bool = false) throws {
        guard var run = try run(id: runID),
              run.deletedAt == nil,
              run.endedAt == nil,
              run.state != .completed,
              run.state != .cancelled
        else {
            return
        }
        try context.performAtomicMutation {
            let now = nowProvider()
            if run.state == .focusing || run.state == .interrupted,
               let deadline = run.phaseDeadline,
               deadline <= now
            {
                try completeFocusMutation(run, endedAt: deadline, mutationDate: now)
                guard let reconciledRun = try self.run(id: runID), reconciledRun.state != .completed else {
                    return
                }
                run = reconciledRun
            }
            if let sessionID = run.sessionID {
                if discardRecord {
                    try timeRepository.discardPomodoroSession(sessionID, endedAt: now, mutationDate: now)
                } else {
                    try timeRepository.stopSession(sessionID: sessionID)
                }
            }
            run.state = .cancelled
            run.endedAt = run.startedAt.map { max(now, $0) } ?? now
            run.deletedAt = discardRecord ? now : nil
            run.markMutated(at: now, deviceID: deviceID)
        }
    }

    private func completeFocusMutation(
        _ run: PomodoroRun,
        endedAt requestedEndDate: Date,
        mutationDate: Date
    ) throws {
        var phaseEndDate = max(run.startedAt ?? run.updatedAt, requestedEndDate)
        if let sessionID = run.sessionID {
            phaseEndDate = try timeRepository.pomodoroPhaseEndDate(
                sessionID: sessionID,
                deadline: phaseEndDate
            )
            try timeRepository.endPomodoroSession(
                sessionID,
                at: phaseEndDate,
                mutationDate: mutationDate
            )
        }
        run.completeFocusPhase(
            endedAt: phaseEndDate,
            mutationDate: mutationDate,
            deviceID: deviceID
        )
    }

    private func canonicalRuns(ids: Set<UUID>) throws -> [PomodoroRun] {
        guard ids.isEmpty == false else { return [] }
        let requestedIDs = Array(ids)
        let descriptor = FetchDescriptor<PomodoroRun>(
            predicate: #Predicate { requestedIDs.contains($0.id) }
        )
        return try context.fetch(descriptor).visibleDeduplicatedByID()
    }
}
