import Foundation

extension TaskDetailWorkspace {
    var editorSourceToken: TaskEditorSourceToken? {
        guard isPresentingRecovery == false,
              let task = store.task(for: taskID) else { return nil }
        return TaskEditorSourceToken(
            baseline: store.editorDraft(for: task).baseline,
            parentCandidateIDs: store.validParentTasks(for: taskID).map(\.id)
        )
    }

    var isSourceUnavailable: Bool {
        store.isTaskDetailRouteValid(taskID) == false
    }

    var activeDraftRecoveryReason: TaskDraftRecoveryReason? {
        if isSourceUnavailable {
            return unavailableDraftRecoveryReason
        }
        return draftRecoveryReason
    }

    var unavailableDraftRecoveryReason: TaskDraftRecoveryReason {
        store.task(for: taskID) == nil
            ? .sourceUnavailable
            : .sourceArchived
    }

    var isPresentingRecovery: Bool {
        TaskDraftRecoveryPresentation.isRequired(
            reason: activeDraftRecoveryReason,
            savedCopyTaskID: savedRecoveryCopyTaskID
        )
    }

    func save() {
        savePreservedDraftAsNew()
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

        guard clearPersistedDraftRecovery() else { return }
        session.discardChanges()
        if sourceIsUnavailable == false {
            draftRecoveryReason = nil
        }
        clearInputFocus()
        if sourceIsUnavailable {
            dismissDetail()
        }
    }

    func reloadLatestDraft() {
        guard clearPersistedDraftRecovery() else { return }
        session.reloadLatestDraft()
        if store.isTaskDetailRouteValid(taskID) {
            draftRecoveryReason = nil
        }
        clearInputFocus()
    }

    func clearInputFocus() {
        focusedTextField = nil
        focusedChecklistDraftID = nil
    }

    func registerNavigationGuard() {
        let draftRecoveryController = store.taskDraftRecoveryController
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
                do {
                    try draftRecoveryController.remove(for: taskID)
                } catch {
                    session.store.errorMessage =
                        TaskDraftRecoveryErrorPresentation
                            .removalFailureMessage(for: error)
                    return false
                }
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
        guard isCompletingRecoveryNavigation == false,
              oldValue != hasUnsavedChanges,
              hasUnsavedChanges == false else { return }
        if store.isTaskDetailRouteValid(taskID) {
            draftRecoveryReason = nil
        } else {
            dismissDetail()
        }
    }
}

struct TaskEditorSourceToken: Equatable {
    let baseline: TaskEditorDraftBaseline?
    let parentCandidateIDs: [UUID]
}
