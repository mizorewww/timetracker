import Foundation

struct SyncConflictPrompt: Identifiable, Equatable {
    let id: UUID
    let detectedAt: Date
    let localSummary: String
    let cloudSummary: String
}

enum SyncConflictResolution {
    case uploadLocal
    case downloadCloud
}

enum SyncConflictResolutionResult: Equatable {
    case appliedImmediately
    case queuedForNextLaunch
    case conflictChanged
}

enum SyncRecoveryResult: Equatable {
    case appliedImmediately
    case queuedForNextLaunch
}
