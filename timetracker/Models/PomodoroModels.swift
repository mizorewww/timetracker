import Foundation
import SwiftData

enum PomodoroState: String, Codable, CaseIterable {
    case planned
    case focusing
    case shortBreak
    case longBreak
    case completed
    case cancelled
    case interrupted
}

@Model
final class PomodoroRun {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var sessionID: UUID?
    var focusSecondsPlanned: Int = 25 * 60
    var breakSecondsPlanned: Int = 5 * 60
    var longBreakSecondsPlanned: Int?
    var stateRaw: String = PomodoroState.planned.rawValue
    var startedAt: Date?
    var endedAt: Date?
    var completedFocusRounds: Int = 0
    var targetRounds: Int = 1
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(
        taskID: UUID,
        focus: Int = 25 * 60,
        breakSeconds: Int = 5 * 60,
        targetRounds: Int = 1,
        deviceID: String
    ) {
        self.id = UUID()
        self.taskID = taskID
        self.focusSecondsPlanned = focus
        self.breakSecondsPlanned = breakSeconds
        self.stateRaw = PomodoroState.planned.rawValue
        self.completedFocusRounds = 0
        self.targetRounds = targetRounds
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deviceID = deviceID
        self.clientMutationID = UUID()
    }
}

extension PomodoroRun {
    var state: PomodoroState {
        get { PomodoroState(rawValue: stateRaw) ?? .planned }
        set { stateRaw = newValue.rawValue }
    }
}
