import Foundation

nonisolated enum SyncActivityKind: Equatable, Sendable {
    case importData
    case exportData
    case setup
    case remoteRefresh

    var recentMessageKey: String {
        switch self {
        case .importData:
            "sync.activity.import.completed"
        case .exportData:
            "sync.activity.export.completed"
        case .setup:
            "sync.activity.setup.completed"
        case .remoteRefresh:
            "sync.activity.remote.completed"
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
