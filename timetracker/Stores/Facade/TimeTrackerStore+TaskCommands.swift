import Foundation
import SwiftData

extension TimeTrackerStore {
    func editorDraft(for task: TaskNode) -> TaskEditorDraft {
        var draft = TaskEditorDraft(
            task: task,
            categoryID: taskCategoryIDByRootTaskID[task.id],
            categoryAssignment: taskCategoryAssignmentByRootTaskID[task.id],
            checklistItems: checklistItems(for: task.id),
            visualByChecklistID: checklistVisualByItemID,
            quantityGoal: taskQuantityGoals.first {
                $0.taskID == task.id
            },
            recurrenceRule: taskRecurrenceRules.first {
                $0.templateTaskID == task.id
            },
            quantityEntries: taskQuantityEntries.filter {
                $0.taskID == task.id
            }
        )
        if let taskDefinition = AppleHealthTaskCatalog.taskDefinition(
            for: task.id
        ) {
            draft.parentID = nil
            draft.categoryID = taskDefinition.categoryID
        }
        return draft
    }

    @discardableResult
    func saveTaskDraft(
        _ draft: TaskEditorDraft,
        returnDestination: DesktopDestination? = nil
    ) -> Bool {
        let result = saveTaskDraftResult(
            draft,
            returnDestination: returnDestination
        )
        switch result {
        case .saved:
            return true
        case .stale:
            errorMessage = TaskLifecycleMutationError.staleDraft.localizedDescription
            return false
        case let .failed(message):
            errorMessage = message
            return false
        }
    }

    func saveTaskDraftResult(
        _ draft: TaskEditorDraft,
        returnDestination: DesktopDestination? = nil
    ) -> TaskDraftSaveResult {
        saveTaskDraftResult(
            draft,
            proposedTaskID: nil,
            returnDestination: returnDestination
        )
    }

    func saveRecoveredTaskDraftResult(
        _ draft: TaskEditorDraft,
        proposedTaskID: UUID,
        returnDestination: DesktopDestination? = nil
    ) -> TaskDraftSaveResult {
        guard draft.taskID == nil, draft.baseline == nil else {
            return .failed(
                message: AppStrings.localized(
                    "task.editor.recovery.invalidCopy"
                )
            )
        }
        return saveTaskDraftResult(
            draft,
            proposedTaskID: proposedTaskID,
            returnDestination: returnDestination
        )
    }

    private func saveTaskDraftResult(
        _ draft: TaskEditorDraft,
        proposedTaskID: UUID?,
        returnDestination: DesktopDestination?
    ) -> TaskDraftSaveResult {
        let sanitizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedTitle.isEmpty else {
            return .failed(message: AppStrings.localized("task.nameRequired"))
        }
        do {
            let outcome = try StoreScopedTaskLifecycleCommandCoordinator(
                container: requireStoreContainer(),
                writeAuthorization: writeAuthorization
            ).save(
                draft: draft,
                sanitizedTitle: sanitizedTitle,
                proposedTaskID: proposedTaskID
            )
            finishStoreScopedMutation(events: outcome.events)
            refreshStoreScopedTimerReadModels()
            selectedTaskID = outcome.savedTaskID
            if let returnDestination {
                desktopDestination = returnDestination
            }
            return .saved(taskID: outcome.savedTaskID)
        } catch {
            var refreshFailureMessage: String?
            if error is TaskLifecycleMutationError {
                refreshFailureMessage = refreshStoreScopedTaskLifecycleReadModels()
            }
            if let refreshFailureMessage {
                return .failed(message: refreshFailureMessage)
            }
            if error as? TaskLifecycleMutationError == .staleDraft {
                return .stale
            }
            return .failed(message: error.localizedDescription)
        }
    }

    @discardableResult
    func archiveSelectedTask(taskID: UUID? = nil) -> Bool {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return false }
        let wasSelected = selectedTaskID == targetID
        let didArchive = performStoreScopedTaskArchive(taskID: targetID)
        if didArchive, wasSelected {
            selectedTaskID = tasks.first(where: { $0.id != targetID && isTaskAvailableForTracking($0) })?.id
        }
        return didArchive
    }

    @discardableResult
    func unarchiveTask(taskID: UUID) -> Bool {
        performStoreCommand(
            onError: handleStoreScopedTaskLifecycleError,
            command: { container in
                try StoreScopedTaskLifecycleCommandCoordinator(
                    container: container,
                    writeAuthorization: writeAuthorization
                ).unarchive(taskID: taskID)
            },
            finish: { outcome in
                if outcome.didMutate {
                    finishStoreScopedMutation(events: outcome.events)
                } else {
                    try refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
                }
            }
        ) != nil
    }

    private func performStoreScopedTaskArchive(taskID: UUID) -> Bool {
        performStoreCommand(
            onError: handleStoreScopedTaskLifecycleError,
            command: { container in
                try StoreScopedTaskLifecycleCommandCoordinator(
                    container: container,
                    writeAuthorization: writeAuthorization
                ).archive(taskID: taskID)
            },
            finish: { outcome in
                if outcome.didMutate {
                    finishStoreScopedMutation(events: outcome.events)
                } else {
                    try refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
                }
                refreshStoreScopedTimerReadModels()
            }
        ) != nil
    }

    private func handleStoreScopedTaskLifecycleError(_ error: Error) {
        if error is TaskLifecycleMutationError {
            refreshStoreScopedTaskLifecycleReadModels()
        }
        errorMessage = error.localizedDescription
    }

    /// Converges every read model used by a task-lifecycle admission check
    /// after a fresh-context command rejects stale scene input.
    @discardableResult
    private func refreshStoreScopedTaskLifecycleReadModels() -> String? {
        do {
            try refresh(
                plan: StoreRefreshPlan(
                    scopes: [.tasks, .ledgerVisible, .pomodoro, .checklist]
                )
            )
            return nil
        } catch {
            let message = savedRefreshFailedMessage(error)
            errorMessage = message
            return message
        }
    }
}
