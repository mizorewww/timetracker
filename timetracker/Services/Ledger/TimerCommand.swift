import Foundation

struct TimerCommand: Codable, Hashable, Identifiable {
    enum CommandType: String, Codable {
        case startTask
        case stopSegment
        case startPomodoro
    }

    let id: UUID
    let type: CommandType
    let taskID: UUID?
    let segmentID: UUID?
    let issuedAt: Date
    let deviceID: String
}
