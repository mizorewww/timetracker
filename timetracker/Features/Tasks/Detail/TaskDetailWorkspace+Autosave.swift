import Foundation

extension TaskDetailWorkspace {
    var autosaveRequest: TaskDetailAutosaveRequest {
        TaskDetailAutosaveRequest(
            isEnabled: isRecoveryLoaded &&
                store.isTaskDetailRouteValid(taskID),
            draft: session.draft,
            hasUnsavedChanges: session.hasUnsavedChanges,
            isValid: session.isPersistenceValid
        )
    }

    func handleAutosaveStatus(
        _ oldStatus: TaskDetailAutosaveController.Status,
        _ status: TaskDetailAutosaveController.Status
    ) {
        guard oldStatus != status, status == .conflicted else { return }
        clearInputFocus()
        session.presentStaleDraftReload()
    }
}
