import Foundation
import SwiftData

@MainActor
final class SwiftDataPomodoroRepository: PomodoroRepository {
    private let context: ModelContext
    private let timeRepository: TimeTrackingRepository
    private let deviceID: String

    init(context: ModelContext, timeRepository: TimeTrackingRepository, deviceID: String? = nil) {
        self.context = context
        self.timeRepository = timeRepository
        self.deviceID = deviceID ?? DeviceIdentity.current
    }

    func runs() throws -> [PomodoroRun] {
        let descriptor = FetchDescriptor<PomodoroRun>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).filter { $0.deletedAt == nil }
    }

    func activeRuns() throws -> [PomodoroRun] {
        try runs().filter { run in
            switch run.state {
            case .planned, .focusing, .shortBreak, .longBreak, .interrupted:
                return run.endedAt == nil
            case .completed, .cancelled:
                return false
            }
        }
    }

    @discardableResult
    func startPomodoro(taskID: UUID, focusSeconds: Int, breakSeconds: Int, longBreakSeconds: Int? = nil, targetRounds: Int) throws -> PomodoroRun {
        let now = Date()
        for existingRun in try activeRuns().filter({ $0.state == .focusing }) {
            if let sessionID = existingRun.sessionID {
                try timeRepository.stopSession(sessionID: sessionID)
            }
            existingRun.state = .cancelled
            existingRun.endedAt = now
            existingRun.updatedAt = now
            existingRun.clientMutationID = UUID()
        }
        for segment in try timeRepository.activeSegments().filter({ $0.taskID == taskID }) {
            try timeRepository.stopSession(sessionID: segment.sessionID)
        }

        let run = PomodoroRun(
            taskID: taskID,
            focus: focusSeconds,
            breakSeconds: breakSeconds,
            longBreakSeconds: longBreakSeconds,
            targetRounds: targetRounds,
            deviceID: deviceID
        )
        let segment = try timeRepository.startTask(taskID: taskID, source: .pomodoro)
        run.sessionID = segment.sessionID
        run.startedAt = now
        run.state = .focusing
        run.updatedAt = now
        context.insert(run)
        try context.save()
        return run
    }

    func completeFocus(runID: UUID) throws {
        let descriptor = FetchDescriptor<PomodoroRun>()
        guard let run = try context.fetch(descriptor).first(where: { $0.id == runID && $0.deletedAt == nil }) else { return }
        guard run.state == .focusing || run.state == .interrupted else { return }
        let now = Date()
        let willComplete = run.completedFocusRounds + 1 >= run.targetRounds
        if let sessionID = run.sessionID {
            try timeRepository.stopSession(sessionID: sessionID)
        }
        run.completedFocusRounds += 1
        let nextBreakState: PomodoroState = run.completedFocusRounds.isMultiple(of: 4) ? .longBreak : .shortBreak
        run.state = willComplete ? .completed : nextBreakState
        run.endedAt = willComplete ? now : nil
        run.updatedAt = now
        try context.save()
    }

    func cancel(runID: UUID, discardRecord: Bool = false) throws {
        let descriptor = FetchDescriptor<PomodoroRun>()
        guard let run = try context.fetch(descriptor).first(where: { $0.id == runID && $0.deletedAt == nil }) else { return }
        let now = Date()
        if let sessionID = run.sessionID {
            if discardRecord {
                try discardPomodoroSession(sessionID, now: now)
            } else {
                try timeRepository.stopSession(sessionID: sessionID)
            }
        }
        run.state = .cancelled
        run.endedAt = now
        run.deletedAt = discardRecord ? now : nil
        run.updatedAt = now
        run.clientMutationID = UUID()
        try context.save()
    }

    private func discardPomodoroSession(_ sessionID: UUID, now: Date) throws {
        let segments = try segments(in: sessionID)
        for segment in segments {
            segment.endedAt = segment.endedAt ?? now
            segment.deletedAt = now
            segment.updatedAt = now
        }

        if let session = try session(id: sessionID) {
            session.endedAt = session.endedAt ?? now
            session.deletedAt = now
            session.updatedAt = now
        }
    }

    private func segments(in sessionID: UUID) throws -> [TimeSegment] {
        let targetSessionID = sessionID
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.sessionID == targetSessionID },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try context.fetch(descriptor)
    }

    private func session(id: UUID) throws -> TimeSession? {
        let sessionID = id
        var descriptor = FetchDescriptor<TimeSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
