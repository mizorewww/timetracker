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
    func startPomodoro(taskID: UUID, focusSeconds: Int, breakSeconds: Int, targetRounds: Int) throws -> PomodoroRun {
        for existingRun in try activeRuns().filter({ $0.state == .focusing }) {
            if let sessionID = existingRun.sessionID {
                try timeRepository.pauseSession(sessionID: sessionID)
            }
            existingRun.state = .interrupted
            existingRun.updatedAt = Date()
        }
        for segment in try timeRepository.activeSegments().filter({ $0.taskID == taskID }) {
            try timeRepository.pauseSession(sessionID: segment.sessionID)
        }

        let run = PomodoroRun(taskID: taskID, focus: focusSeconds, breakSeconds: breakSeconds, targetRounds: targetRounds, deviceID: deviceID)
        let segment = try timeRepository.startTask(taskID: taskID, source: .pomodoro)
        run.sessionID = segment.sessionID
        run.startedAt = Date()
        run.state = .focusing
        run.updatedAt = Date()
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
            if willComplete {
                try timeRepository.stopSession(sessionID: sessionID)
            } else {
                try timeRepository.pauseSession(sessionID: sessionID)
            }
        }
        run.completedFocusRounds += 1
        run.state = willComplete ? .completed : .shortBreak
        run.endedAt = willComplete ? now : nil
        run.updatedAt = now
        try context.save()
    }

    func cancel(runID: UUID) throws {
        let descriptor = FetchDescriptor<PomodoroRun>()
        guard let run = try context.fetch(descriptor).first(where: { $0.id == runID && $0.deletedAt == nil }) else { return }
        if let sessionID = run.sessionID {
            try timeRepository.stopSession(sessionID: sessionID)
        }
        run.state = .cancelled
        run.endedAt = Date()
        run.updatedAt = Date()
        run.clientMutationID = UUID()
        try context.save()
    }
}
