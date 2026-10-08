import Foundation

extension TaskDetailWorkspace {
    /// Restores the newest crash/termination recovery draft for this task into
    /// the editor session and surfaces a single inline notice.
    func loadPersistedDraftRecovery() async {
        let recoveredDraft = try? await store.taskDraftRecoveryController.load(
            for: taskID,
            currentDraft: session.sessionBaseline
        )
        await store.taskDraftRecoveryController.removeExpired()
        guard Task.isCancelled == false else { return }
        if let recoveredDraft {
            session.restoreRecoveredDraft(recoveredDraft)
        }
        isRecoveryLoaded = true
    }

    /// Removes the persisted recovery draft for this task so a discarded or
    /// reloaded draft is not offered again on reopen.
    func clearPersistedDraftRecovery() {
        Task { [store, taskID] in
            await store.taskDraftRecoveryController.remove(for: taskID)
        }
    }
}
