import Foundation

/// Local-only crash/termination recovery for an existing task draft.
///
/// Persisted task facts are written by autosave; this controller only mirrors
/// the current unsaved draft so a relaunch can restore it into the editor. One
/// actor serializes file access, so writes and removals cannot interleave.
actor TaskDraftRecoveryController {
    private let store: TaskDraftRecoveryStore

    init(store: TaskDraftRecoveryStore = TaskDraftRecoveryStore()) {
        self.store = store
    }

    func load(
        for sourceTaskID: UUID,
        currentDraft: TaskEditorDraft
    ) throws -> TaskEditorDraft? {
        try store.load(for: sourceTaskID, currentDraft: currentDraft)
    }

    /// Mirrors `draft` for `sourceTaskID`, or drops the entry when the draft no
    /// longer differs from what is persisted.
    func persist(
        _ draft: TaskEditorDraft,
        for sourceTaskID: UUID,
        hasUnsavedChanges: Bool
    ) {
        guard draft.taskID == sourceTaskID else { return }
        if hasUnsavedChanges {
            try? store.save(draft, for: sourceTaskID)
        } else {
            try? store.remove(for: sourceTaskID)
        }
    }

    func remove(for sourceTaskID: UUID) {
        try? store.remove(for: sourceTaskID)
    }

    func removeExpired() {
        _ = try? store.removeExpired()
    }
}
