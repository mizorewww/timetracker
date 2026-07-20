import Foundation

extension TaskDetailAutosaveController {
    static func workspaceController(
        store: TimeTrackerStore,
        session: TaskEditorSession,
        taskID: UUID,
        returnDestination: TimeTrackerStore.DesktopDestination
    ) -> TaskDetailAutosaveController {
        TaskDetailAutosaveController(
            delay: workspaceDelay
        ) { [weak store, weak session] draft in
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
                guard session.acceptAutosavedDraft(
                    draft,
                    for: savedTaskID
                ) else {
                    return .conflicted
                }
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

    private static var workspaceDelay: Duration {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if CommandLine.arguments.contains("--uitesting"),
           let rawValue = environment[
               "TIMETRACKER_UI_AUTOSAVE_DELAY_MILLISECONDS"
           ],
           let milliseconds = Int(rawValue),
           milliseconds >= 0,
           milliseconds <= 60_000 {
            return .milliseconds(milliseconds)
        }
        #endif
        return .milliseconds(450)
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
