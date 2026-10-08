import Foundation

extension TaskDetailWorkspace {
    var editorSourceToken: TaskEditorSourceToken? {
        guard let task = store.task(for: taskID) else { return nil }
        return TaskEditorSourceToken(
            baseline: store.editorDraft(for: task).baseline,
            parentCandidateIDs: store.validParentTasks(for: taskID).map(\.id)
        )
    }

    func cancelPendingNavigationIfNeeded(isDiscardConfirmationPresented: Bool) {
        guard isDiscardConfirmationPresented == false,
              let requestID = session.navigationConfirmationRequestID
        else {
            return
        }
        Task { @MainActor in
            await Task.yield()
            defer {
                session.clearNavigationConfirmationRequest(requestID)
            }
            guard session.isDiscardConfirmationPresented == false,
                  session.hasUnsavedChanges,
                  store.taskDetailNavigationGuard.pendingNavigationID
                  == requestID else { return }
            store.taskDetailNavigationGuard.cancelPendingNavigation(
                requestID: requestID
            )
        }
    }

    func requestDiscard() {
        store.taskDetailNavigationGuard.cancelPendingNavigation(
            id: navigationGuardRegistration.id
        )
        clearInputFocus()
        session.requestCancel(whenClean: {})
    }

    func discardChanges() {
        let sourceIsUnavailable = store.isTaskDetailRouteValid(taskID) == false
        let navigationRequestID = session.navigationConfirmationRequestID
        if let navigationRequestID {
            let completed = store.taskDetailNavigationGuard
                .discardChangesAndCompletePendingNavigation(requestID: navigationRequestID)
            if completed {
                clearInputFocus()
            }
            return
        }

        clearPersistedDraftRecovery()
        session.discardChanges()
        clearInputFocus()
        if sourceIsUnavailable {
            dismissDetail()
        }
    }

    func reloadLatestDraft() {
        clearPersistedDraftRecovery()
        session.reloadLatestDraft()
        clearInputFocus()
    }

    func clearInputFocus() {
        focusedTextField = nil
        focusedChecklistDraftID = nil
    }

    func registerNavigationGuard() {
        navigationGuardRegistration.attach(
            to: store.taskDetailNavigationGuard
        )
        store.taskDetailNavigationGuard.register(
            id: navigationGuardRegistration.id,
            taskID: taskID,
            prepareForNavigation: {
                [weak autosaveController, weak session, weak store] in
                guard let autosaveController, let session else { return }
                autosaveController.flush(
                    session: session,
                    isEnabled: store?.isTaskDetailRouteValid(taskID) == true &&
                        autosaveController.status != .conflicted
                )
            },
            hasUnsavedChanges: { [weak session] in
                session?.hasUnsavedChanges == true
            },
            discardChanges: { [weak session] in
                guard let session else { return false }
                session.discardChanges()
                return true
            },
            requestDiscardConfirmation: { [weak session] requestID in
                session?.requestDiscardConfirmation(for: requestID)
            },
            dismissDiscardConfirmation: { [weak session] requestID in
                session?.dismissDiscardConfirmation(for: requestID)
            },
            dismissDetail: dismissDetail
        )
    }

    func updateNavigationGuardForDraftChanges(
        _ oldValue: Bool,
        _ hasUnsavedChanges: Bool
    ) {
        guard oldValue != hasUnsavedChanges,
              hasUnsavedChanges == false else { return }
        if store.isTaskDetailRouteValid(taskID) == false {
            dismissDetail()
        }
    }
}

struct TaskEditorSourceToken: Equatable {
    let baseline: TaskEditorDraftBaseline?
    let parentCandidateIDs: [UUID]
}
