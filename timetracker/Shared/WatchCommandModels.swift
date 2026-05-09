import Foundation

struct WatchTimerCommand: Codable, Equatable, Identifiable {
    var id: UUID
    var type: WatchTimerCommandType
    var taskID: UUID?
    var segmentID: UUID?
    var issuedAt: Date
    var deviceID: String
}

enum WatchTimerCommandType: String, Codable, Equatable {
    case startTask
    case stopSegment
}

enum WatchCommandProcessingResult: Equatable {
    case started(UUID)
    case stopped(UUID)
    case duplicate(UUID)
    case missingTask(UUID)
    case missingSegment(UUID)
    case invalid

    var isProcessed: Bool {
        switch self {
        case .started, .stopped:
            return true
        case .duplicate, .missingTask, .missingSegment, .invalid:
            return false
        }
    }
}
