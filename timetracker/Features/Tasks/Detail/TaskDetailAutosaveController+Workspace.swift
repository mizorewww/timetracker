import Foundation

extension TaskDetailAutosaveController {
    static func workspaceController(
        store: TimeTrackerStore,
        session: TaskEditorSession
    ) -> TaskDetailAutosaveController {
        TaskDetailAutosaveController(
            delay: .milliseconds(450)
        ) { [weak store, weak session] draft in
            guard let store, let session else {
                return .failed(
                    message: AppStrings.localized(
                        "systemAction.error.taskNotFound"
                    )
                )
            }
            switch store.saveTaskDraftResult(draft, selectsSavedTask: false) {
            case let .saved(savedTaskID):
                guard session.acceptAutosavedDraft(
                    draft,
                    for: savedTaskID
                ) else {
                    return .conflicted
                }
                return .saved
            case .stale:
                return .conflicted
            case let .failed(message):
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
}
