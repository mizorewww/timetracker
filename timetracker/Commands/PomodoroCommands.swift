import Foundation
import SwiftData

@MainActor
struct PomodoroCommandHandler {
    func start(
        taskID: UUID,
        focusSeconds: Int,
        breakSeconds: Int,
        longBreakSeconds: Int?,
        targetRounds: Int,
        allowParallelTimers: Bool,
        activeSegments: [TimeSegment],
        pomodoroRuns: [PomodoroRun],
        timeRepository: TimeTrackingRepository,
        pomodoroRepository: PomodoroRepository,
        context: ModelContext?
    ) throws -> PomodoroRun {
        if allowParallelTimers == false {
            try TimerCommandHandler().stopOtherActiveSegments(
                excluding: taskID,
                activeSegments: activeSegments,
                pomodoroRuns: pomodoroRuns,
                timeRepository: timeRepository,
                context: context
            )
        }
        return try StartPomodoroUseCase(repository: pomodoroRepository).execute(
            taskID: taskID,
            focusSeconds: focusSeconds,
            breakSeconds: breakSeconds,
            longBreakSeconds: longBreakSeconds,
            targetRounds: targetRounds
        )
    }

    func advance(run: PomodoroRun, repository: PomodoroRepository) throws {
        switch run.state {
        case .focusing, .interrupted:
            try CompletePomodoroFocusUseCase(repository: repository).execute(runID: run.id)
        case .shortBreak, .longBreak:
            try CompletePomodoroBreakUseCase(repository: repository).execute(runID: run.id)
        case .planned, .completed, .cancelled:
            return
        }
    }

    @discardableResult
    func reconcile(run: PomodoroRun, now: Date, repository: PomodoroRepository) throws -> Bool {
        try repository.reconcileExpiredPhase(runID: run.id, now: now)
    }

    func cancel(run: PomodoroRun, discardRecord: Bool = false, repository: PomodoroRepository) throws {
        try CancelPomodoroUseCase(repository: repository).execute(runID: run.id, discardRecord: discardRecord)
    }

    func cancelIfNeeded(sessionID: UUID, runs: [PomodoroRun], context: ModelContext?, now: Date = Date()) throws {
        guard let run = runs.first(where: { $0.sessionID == sessionID && $0.deletedAt == nil && $0.endedAt == nil }) else {
            return
        }
        if try settleExpiredFocusIfNeeded(run, sessionID: sessionID, context: context, now: now) {
            return
        }
        let shouldDiscard = try shouldDiscardCancelledRun(run, sessionID: sessionID, context: context, now: now)
        if shouldDiscard {
            try discardRunAndSession(run, sessionID: sessionID, context: context, now: now)
            return
        }
        run.state = .cancelled
        run.endedAt = run.startedAt.map { max(now, $0) } ?? now
        run.updatedAt = now
        run.clientMutationID = UUID()
        try context?.saveAfterMutationStep()
    }

    /// Deleting a ledger record is distinct from stopping it. Tombstone the
    /// corresponding Pomodoro regardless of elapsed time or phase deadline so
    /// the run cannot outlive the record the user explicitly removed.
    func discardIfNeeded(sessionID: UUID, runs: [PomodoroRun], context: ModelContext?, now: Date = Date()) throws {
        guard let run = runs.first(where: {
            $0.sessionID == sessionID &&
                $0.deletedAt == nil &&
                $0.endedAt == nil
        }) else {
            return
        }
        try discardRunAndSession(run, sessionID: sessionID, context: context, now: now)
    }

    /// General timer commands can close a Pomodoro session without going
    /// through `PomodoroRepository`. Preserve the same deadline semantics here
    /// so a stop from a widget, Watch, deep link, or ledger edit cannot record
    /// suspension time as focus time or incorrectly cancel a completed round.
    private func settleExpiredFocusIfNeeded(
        _ run: PomodoroRun,
        sessionID: UUID,
        context: ModelContext?,
        now: Date
    ) throws -> Bool {
        guard (run.state == .focusing || run.state == .interrupted),
              let deadline = run.phaseDeadline,
              deadline <= now else {
            return false
        }

        let mutationDate = Date()
        let sessionSegments = try context.map { try segments(in: sessionID, context: $0) } ?? []
        let phaseEndDate = max(
            deadline,
            sessionSegments
                .filter { $0.deletedAt == nil }
                .map(\.startedAt)
                .max() ?? deadline
        )
        for segment in sessionSegments where segment.deletedAt == nil {
            if segment.endedAt.map({ $0 > phaseEndDate }) ?? true {
                segment.endedAt = max(segment.startedAt, phaseEndDate)
                segment.updatedAt = mutationDate
                segment.deviceID = DeviceIdentity.current
            }
        }

        if let context,
           let session = try session(id: sessionID, context: context),
           session.deletedAt == nil {
            let latestEnd = sessionSegments
                .filter { $0.deletedAt == nil }
                .compactMap(\.endedAt)
                .max() ?? phaseEndDate
            session.endedAt = max(session.startedAt, latestEnd)
            session.markMutated(at: mutationDate, deviceID: DeviceIdentity.current)
        }

        run.completeFocusPhase(endedAt: phaseEndDate, mutationDate: mutationDate)
        try context?.saveAfterMutationStep()
        return true
    }

    private func shouldDiscardCancelledRun(
        _ run: PomodoroRun,
        sessionID: UUID,
        context: ModelContext?,
        now: Date
    ) throws -> Bool {
        guard context != nil else { return false }
        let effectiveSeconds = try pomodoroEffectiveSeconds(sessionID: sessionID, context: context, now: now)
        return effectiveSeconds < Int(Double(max(1, run.focusSecondsPlanned)) * 0.2)
    }

    private func pomodoroEffectiveSeconds(sessionID: UUID, context: ModelContext?, now: Date) throws -> Int {
        guard let context else { return 0 }
        let segments = try segments(in: sessionID, context: context)
        return segments.reduce(0) { total, segment in
            guard segment.deletedAt == nil else { return total }
            return total + max(0, Int((segment.endedAt ?? now).timeIntervalSince(segment.startedAt)))
        }
    }

    private func discardRunAndSession(
        _ run: PomodoroRun,
        sessionID: UUID,
        context: ModelContext?,
        now: Date
    ) throws {
        run.state = .cancelled
        run.endedAt = run.startedAt.map { max(now, $0) } ?? now
        run.deletedAt = now
        run.updatedAt = now
        run.clientMutationID = UUID()

        guard let context else { return }
        let sessionSegments = try segments(in: sessionID, context: context)
        for segment in sessionSegments {
            segment.endedAt = max(segment.startedAt, segment.endedAt ?? now)
            segment.deletedAt = now
            segment.updatedAt = now
            segment.deviceID = DeviceIdentity.current
        }
        if let session = try session(id: sessionID, context: context) {
            let latestSegmentEnd = sessionSegments.compactMap(\.endedAt).max() ?? now
            session.endedAt = max(session.startedAt, session.endedAt ?? latestSegmentEnd)
            session.deletedAt = now
            session.markMutated(at: now, deviceID: DeviceIdentity.current)
        }
        try context.saveAfterMutationStep()
    }

    private func segments(in sessionID: UUID, context: ModelContext) throws -> [TimeSegment] {
        let targetSessionID = sessionID
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.sessionID == targetSessionID },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try context.fetch(descriptor)
            .visibleDeduplicatedByID()
            .filter { $0.sessionID == targetSessionID }
    }

    private func session(id: UUID, context: ModelContext) throws -> TimeSession? {
        let sessionID = id
        let descriptor = FetchDescriptor<TimeSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        return try context.fetch(descriptor).visibleDeduplicatedByID().first
    }
}
