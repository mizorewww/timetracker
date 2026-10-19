import Foundation
import SwiftData

extension TimeTrackerStore {
    func editorDraft(for task: TaskNode) -> TaskEditorDraft {
        TaskEditorDraft(
            task: task,
            categoryID: taskCategoryIDByRootTaskID[task.id],
            categoryAssignment: taskCategoryAssignmentByRootTaskID[task.id],
            checklistItems: checklistItems(for: task.id),
            visualByChecklistID: checklistDomainStore.visualByChecklistItemID,
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
                session: requireMutationSession()
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
            if error is TaskLifecycleMutationError {
                refreshStoreScopedTaskLifecycleReadModels()
            }
            if error as? TaskLifecycleMutationError == .staleDraft {
                return .stale
            }
            return .failed(message: error.localizedDescription)
        }
    }

    func archiveSelectedTask(taskID: UUID? = nil) throws {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return }
        let wasSelected = selectedTaskID == targetID
        try performStoreScopedTaskArchive(taskID: targetID)
        if wasSelected {
            selectedTaskID = tasks.first(where: { $0.id != targetID && isTaskAvailableForTracking($0) })?.id
        }
    }

    func unarchiveTask(taskID: UUID) throws {
        try performStoreCommand(
            onError: handleStoreScopedTaskLifecycleError,
            command: { session in
                try StoreScopedTaskLifecycleCommandCoordinator(
                    session: session
                ).unarchive(taskID: taskID)
            },
            finish: { outcome in
                if outcome.didMutate {
                    finishStoreScopedMutation(events: outcome.events)
                } else {
                    try refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
                }
            }
        )
    }

    private func performStoreScopedTaskArchive(taskID: UUID) throws {
        try performStoreCommand(
            onError: handleStoreScopedTaskLifecycleError,
            command: { session in
                try StoreScopedTaskLifecycleCommandCoordinator(
                    session: session
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
        )
    }

    private func handleStoreScopedTaskLifecycleError(_ error: Error) {
        if error is TaskLifecycleMutationError {
            refreshStoreScopedTaskLifecycleReadModels()
        }
    }

    /// Converges every read model used by a task-lifecycle admission check
    /// after a fresh-context command rejects stale scene input.
    private func refreshStoreScopedTaskLifecycleReadModels() {
        refreshLoggingFailure(
            plan: StoreRefreshPlan(
                scopes: [.tasks, .ledgerVisible, .pomodoro, .checklist]
            )
        )
    }
}
