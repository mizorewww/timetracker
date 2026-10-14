import Foundation

extension TaskDetailWorkspace {
    /// Removes the persisted recovery draft for this task so a discarded or
    /// reloaded draft is not offered again on reopen.
    func clearPersistedDraftRecovery() {
        Task { [store, taskID] in
            await store.taskDraftRecoveryController.remove(for: taskID)
        }
    }
}
