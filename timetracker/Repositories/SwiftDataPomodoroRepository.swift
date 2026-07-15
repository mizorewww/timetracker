import Foundation
import SwiftData

@MainActor
final class SwiftDataPomodoroRepository: PomodoroRepository {
    private let context: ModelContext
    private let timeRepository: TimeTrackingRepository
    private let deviceID: String
    private let nowProvider: () -> Date

    init(
        context: ModelContext,
        timeRepository: TimeTrackingRepository,
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
            .sorted(by: runCreationOrder)
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
        let candidateIDs = Set(try context.fetch(descriptor).map(\.id))
        return try canonicalRuns(ids: candidateIDs)
            .filter {
                $0.endedAt == nil &&
                    $0.stateRaw != completed &&
                    $0.stateRaw != cancelled
            }
            .sorted(by: runCreationOrder)
    }

    @discardableResult
    func startPomodoro(taskID: UUID, focusSeconds: Int, breakSeconds: Int, longBreakSeconds: Int? = nil, targetRounds: Int) throws -> PomodoroRun {
        try context.performAtomicMutation {
            let now = nowProvider()
            for existingRun in try activeRuns() {
                if existingRun.phaseHasExpired(at: now),
                   existingRun.state == .focusing || existingRun.state == .interrupted,
                   let deadline = existingRun.phaseDeadline {
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
                  run.endedAt == nil else {
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
                  run.endedAt == nil else {
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
              deadline <= now else {
            return false
        }
        return try completeFocus(
            runID: run.id,
            expectedState: run.state,
            endedAt: deadline
        )
    }

    func cancel(runID: UUID, discardRecord: Bool = false) throws {
        guard var run = try run(id: runID) else { return }
        try context.performAtomicMutation {
            let now = nowProvider()
            if (run.state == .focusing || run.state == .interrupted),
               let deadline = run.phaseDeadline,
               deadline <= now {
                try completeFocusMutation(run, endedAt: deadline, mutationDate: now)
                guard let reconciledRun = try self.run(id: runID), reconciledRun.state != .completed else {
                    return
                }
                run = reconciledRun
            }
            if let sessionID = run.sessionID {
                if discardRecord {
                    try discardPomodoroSession(sessionID, now: now)
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
        let phaseEndDate = try clampedPhaseEndDate(
            for: run,
            requestedEndDate: requestedEndDate
        )
        if let sessionID = run.sessionID {
            try stopPomodoroSession(
                sessionID,
                endedAt: phaseEndDate,
                mutationDate: mutationDate
            )
        }
        run.completeFocusPhase(
            endedAt: phaseEndDate,
            mutationDate: mutationDate,
            deviceID: deviceID
        )
    }

    private func discardPomodoroSession(_ sessionID: UUID, now: Date) throws {
        let segments = try segments(in: sessionID)
        for segment in segments {
            segment.endedAt = max(segment.startedAt, segment.endedAt ?? now)
            segment.deletedAt = now
            segment.updatedAt = now
            segment.deviceID = deviceID
        }

        if let session = try session(id: sessionID) {
            let latestSegmentEnd = segments.compactMap(\.endedAt).max() ?? now
            session.endedAt = max(session.startedAt, session.endedAt ?? latestSegmentEnd)
            session.deletedAt = now
            session.markMutated(at: now, deviceID: deviceID)
        }
    }

    private func clampedPhaseEndDate(for run: PomodoroRun, requestedEndDate: Date) throws -> Date {
        var lowerBound = run.startedAt ?? run.updatedAt
        if let sessionID = run.sessionID {
            let activeStarts = try segments(in: sessionID)
                .filter { $0.deletedAt == nil && $0.endedAt == nil }
                .map(\.startedAt)
            if let latestActiveStart = activeStarts.max() {
                lowerBound = max(lowerBound, latestActiveStart)
            }
        }
        return max(lowerBound, requestedEndDate)
    }

    /// Stops the ledger at the business deadline. Calling the general timer
    /// repository here would stamp `Date()` and turn background suspension into
    /// fabricated focus time.
    private func stopPomodoroSession(
        _ sessionID: UUID,
        endedAt: Date,
        mutationDate: Date
    ) throws {
        let sessionSegments = try segments(in: sessionID)
        for segment in sessionSegments where segment.deletedAt == nil && segment.endedAt == nil {
            segment.endedAt = max(segment.startedAt, endedAt)
            segment.updatedAt = mutationDate
            segment.deviceID = deviceID
        }

        if let session = try session(id: sessionID), session.deletedAt == nil {
            let latestEnd = sessionSegments
                .filter { $0.deletedAt == nil }
                .compactMap(\.endedAt)
                .max() ?? max(session.startedAt, endedAt)
            session.endedAt = max(session.startedAt, latestEnd)
            session.markMutated(at: mutationDate, deviceID: deviceID)
        }
    }

    private func segments(in sessionID: UUID) throws -> [TimeSegment] {
        let targetSessionID = sessionID
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.sessionID == targetSessionID }
        )
        let candidateIDs = Set(try context.fetch(descriptor).map(\.id))
        guard candidateIDs.isEmpty == false else { return [] }
        let requestedIDs = Array(candidateIDs)
        let duplicateDescriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { requestedIDs.contains($0.id) }
        )
        return try context.fetch(duplicateDescriptor)
            .visibleDeduplicatedByID()
            .filter { $0.sessionID == targetSessionID }
            .sorted { lhs, rhs in
                if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func session(id: UUID) throws -> TimeSession? {
        let sessionID = id
        let descriptor = FetchDescriptor<TimeSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        return try context.fetch(descriptor).visibleDeduplicatedByID().first
    }

    private func canonicalRuns(ids: Set<UUID>) throws -> [PomodoroRun] {
        guard ids.isEmpty == false else { return [] }
        let requestedIDs = Array(ids)
        let descriptor = FetchDescriptor<PomodoroRun>(
            predicate: #Predicate { requestedIDs.contains($0.id) }
        )
        return try context.fetch(descriptor).visibleDeduplicatedByID()
    }

    private func runCreationOrder(_ lhs: PomodoroRun, _ rhs: PomodoroRun) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
