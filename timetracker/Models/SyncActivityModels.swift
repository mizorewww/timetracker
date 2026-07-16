import Foundation

nonisolated enum SyncActivityKind: Equatable, Sendable {
    case importData
    case exportData
    case setup
    case remoteRefresh

    var recentMessageKey: String {
        switch self {
        case .importData:
            return "sync.activity.import.completed"
        case .exportData:
            return "sync.activity.export.completed"
        case .setup:
            return "sync.activity.setup.completed"
        case .remoteRefresh:
            return "sync.activity.remote.completed"
        }
    }
}

nonisolated enum SyncActivityResult: Equatable, Sendable {
    case succeeded
    case failed(message: String)
}

nonisolated struct SyncActivityOutcome: Equatable, Sendable {
    let kind: SyncActivityKind
    let completedAt: Date
    let result: SyncActivityResult
}
