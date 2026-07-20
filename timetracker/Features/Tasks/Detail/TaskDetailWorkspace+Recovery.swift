import Foundation

extension TaskDetailWorkspace {
    func prepareRecoveryIfNeeded() {
        guard store.isTaskDetailRouteValid(taskID) == false,
              session.hasUnsavedChanges,
              draftRecoveryReason == nil else { return }
        draftRecoveryReason = unavailableDraftRecoveryReason
    }

    func loadPersistedDraftRecovery() async {
        do {
            let recoveredDraft = try await store.taskDraftRecoveryController.load(
                for: taskID,
                currentDraft: session.sessionBaseline
            )
            guard Task.isCancelled == false else { return }
            if let recoveredDraft {
                let sourceChanged =
                    recoveredDraft.baseline != session.sessionBaseline.baseline
                session.restoreRecoveredDraft(recoveredDraft)
                if store.task(for: recoveredDraft.id) != nil {
                    savedRecoveryCopyTaskID = recoveredDraft.id
                }
                if store.isTaskDetailRouteValid(taskID) == false {
                    draftRecoveryReason = unavailableDraftRecoveryReason
                } else if sourceChanged {
                    draftRecoveryReason = .sourceChanged
                }
            }
            draftRecoveryLoadState = .ready
        } catch is CancellationError {
            return
        } catch {
            draftRecoveryLoadState = .failed
        }
    }

    func retryDraftRecoveryLoad() {
        draftRecoveryLoadState = .loading
        draftRecoveryLoadRequestID = UUID()
    }

    func savePreservedDraftAsNew() {
        if savedRecoveryCopyTaskID != nil {
            finishSavedRecoveryCopy()
            return
        }
        let draft = session.draft.taskID == nil
            ? session.draft
            : recoveredTaskDraft
        let result = store.saveRecoveredTaskDraftResult(
            draft,
            proposedTaskID: session.draft.id,
            returnDestination: returnDestination
        )
        switch result {
        case .saved(let savedTaskID):
            savedRecoveryCopyTaskID = savedTaskID
            finishSavedRecoveryCopy()
        case .stale:
            store.errorMessage = TaskLifecycleMutationError
                .staleDraft
                .localizedDescription
        case .failed(let message):
            store.errorMessage = message
        }
    }

    func finishSavedRecoveryCopy() {
        guard let savedTaskID = savedRecoveryCopyTaskID,
              isFinishingRecoveryCleanup == false else { return }
        isFinishingRecoveryCleanup = true
        Task {
            defer { isFinishingRecoveryCleanup = false }
            do {
                try await store.taskDraftRecoveryController
                    .removeInBackground(for: taskID)
            } catch {
                store.errorMessage = TaskDraftRecoveryErrorPresentation
                    .removalFailureMessage(for: error)
                return
            }
            guard savedRecoveryCopyTaskID == savedTaskID else { return }
            isCompletingRecoveryNavigation = true
            savedRecoveryCopyTaskID = nil
            clearInputFocus()
            navigationGuardRegistration.unregister()
            session.discardChanges()
            dismissDetail()
            replaceDetail(savedTaskID)
        }
    }

    func leaveRecoveryCleanup() {
        clearInputFocus()
        navigationGuardRegistration.unregister()
        dismissDetail()
    }

    func restoreArchivedSource() {
        guard store.restoreArchivedHierarchyForRecovery(taskID: taskID) else {
            return
        }
        draftRecoveryReason = .sourceChanged
    }

    @discardableResult
    func clearPersistedDraftRecovery() -> Bool {
        do {
            try store.taskDraftRecoveryController.remove(for: taskID)
            return true
        } catch {
            store.errorMessage = TaskDraftRecoveryErrorPresentation
                .removalFailureMessage(for: error)
            return false
        }
    }

    private var recoveredTaskDraft: TaskEditorDraft {
        let parentID = session.draft.parentID.flatMap {
            store.isTaskDetailRouteValid($0) ? $0 : nil
        }
        let categoryID = parentID == nil && session.draft.parentID == nil
            ? session.draft.categoryID.flatMap {
                store.taskCategory(for: $0) == nil ? nil : $0
            }
            : nil
        return session.draft.copyAsNew(
            parentID: parentID,
            categoryID: categoryID
        )
    }
}

enum TaskDraftRecoveryErrorPresentation {
    static func removalFailureMessage(for error: Error) -> String {
        if error as? TaskDraftRecoveryControllerError == .removalSuperseded {
            return AppStrings.localized(
                "task.editor.recovery.removeSuperseded"
            )
        }
        return String(
            format: AppStrings.localized(
                "task.editor.recovery.removeFailed"
            ),
            error.localizedDescription
        )
    }
}
