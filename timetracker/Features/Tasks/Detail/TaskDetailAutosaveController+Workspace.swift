import Foundation

extension TaskDetailAutosaveController {
    static func workspaceController(
        store: TimeTrackerStore,
        session: TaskEditorSession,
        taskID: UUID,
        returnDestination: TimeTrackerStore.DesktopDestination
    ) -> TaskDetailAutosaveController {
        TaskDetailAutosaveController { [weak store, weak session] draft in
            guard let store, let session else {
                return .failed(
                    message: AppStrings.localized(
                        "systemAction.error.taskNotFound"
                    )
                )
            }
            switch store.saveTaskDraftResult(
                draft,
                returnDestination: returnDestination
            ) {
            case .saved(let savedTaskID):
                session.acceptAutosavedDraft(
                    draft,
                    for: savedTaskID
                )
                removeRecoveryAfterSave(
                    store: store,
                    taskID: taskID
                )
                return .saved
            case .stale:
                return .conflicted
            case .failed(let message):
                return .failed(message: message)
            }
        }
    }

    @discardableResult
    func flush(
        session: TaskEditorSession,
        isEnabled: Bool
    ) -> Bool {
        flush(
            TaskDetailAutosaveRequest(
                isEnabled: isEnabled,
                draft: session.draft,
                hasUnsavedChanges: session.hasUnsavedChanges,
                isValid: session.isPersistenceValid
            )
        )
    }

    private static func removeRecoveryAfterSave(
        store: TimeTrackerStore,
        taskID: UUID
    ) {
        do {
            try store.taskDraftRecoveryController.remove(for: taskID)
        } catch {
            store.errorMessage = TaskDraftRecoveryErrorPresentation
                .removalFailureMessage(for: error)
        }
    }
}
