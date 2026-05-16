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
