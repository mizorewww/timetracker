import Foundation

/// Serializes the synchronous sidecar read away from MainActor.
///
/// `SyncConflictService.prompt()` intentionally stays synchronous because its
/// state-file lock protects a multi-file snapshot. Crossing this actor is
/// enough to keep that lock wait off the interaction actor; no detached task
/// is needed for every notification.
actor SyncConflictPromptReader {
    private let service: SyncConflictService

    init(service: SyncConflictService) {
        self.service = service
    }

    func load() throws -> SyncConflictPrompt? {
        try Task.checkCancellation()
        let prompt = try service.prompt()
        try Task.checkCancellation()
        return prompt
    }
}

/// Signals that the durable sync sidecar changed after an asynchronous
/// projection. Scenes re-read the current prompt instead of trusting a value
/// captured before a later conflict resolution or import.
@MainActor
enum SyncConflictPromptChangeBroadcaster {
    static let notification = Notification.Name(
        "TimeTrackerSyncConflictPromptChanged"
    )

    static func publish() {
        NotificationCenter.default.post(
            name: notification,
            object: nil
        )
    }
}
