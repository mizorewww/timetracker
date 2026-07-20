import Foundation

extension TaskDetailWorkspace {
    var autosaveRequest: TaskDetailAutosaveRequest {
        TaskDetailAutosaveRequest(
            isEnabled: draftRecoveryLoadState == .ready &&
                isPresentingRecovery == false,
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
        draftRecoveryReason = isSourceUnavailable
            ? unavailableDraftRecoveryReason
            : .sourceChanged
        clearInputFocus()
    }
}
