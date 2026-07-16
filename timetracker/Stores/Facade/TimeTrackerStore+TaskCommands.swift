import Foundation
import SwiftData

extension TimeTrackerStore {
    func editorDraft(for task: TaskNode) -> TaskEditorDraft {
        TaskEditorDraft(
            task: task,
            categoryID: taskCategoryIDByRootTaskID[task.id],
            categoryAssignment: taskCategoryAssignmentByRootTaskID[task.id],
            checklistItems: checklistItems(for: task.id),
            visualByChecklistID: checklistVisualByItemID
        )
    }

    @discardableResult
    func saveTaskDraft(
        _ draft: TaskEditorDraft,
        returnDestination: DesktopDestination? = nil
    ) -> Bool {
        let sanitizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedTitle.isEmpty else {
            errorMessage = AppStrings.localized("task.nameRequired")
            return false
        }
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try StoreScopedTaskLifecycleCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).save(draft: draft, sanitizedTitle: sanitizedTitle)
            finishStoreScopedMutation(events: outcome.events)
            refreshStoreScopedTimerReadModels()
            selectedTaskID = outcome.savedTaskID
            if let returnDestination {
                desktopDestination = returnDestination
            }
            return true
        } catch {
            if error is TaskLifecycleMutationError {
                refreshStoreScopedTaskLifecycleReadModels()
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func archiveSelectedTask(taskID: UUID? = nil) -> Bool {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return false }
        let wasSelected = selectedTaskID == targetID
        let didArchive = performStoreScopedTaskStatusTransition(
            .archived,
            taskID: targetID
        )
        if didArchive, wasSelected {
            selectedTaskID = tasks.first(where: { $0.id != targetID && isTaskAvailableForTracking($0) })?.id
        }
        return didArchive
    }

    @discardableResult
    func setTaskStatus(_ status: TaskStatus, taskID: UUID? = nil) -> Bool {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return false }
        return performStoreScopedTaskStatusTransition(status, taskID: targetID)
    }

    @discardableResult
    func reopenTaskForWork(_ taskID: UUID) -> Bool {
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try StoreScopedTaskLifecycleCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).reopenForWork(taskID: taskID)
            if outcome.didMutate {
                finishStoreScopedMutation(events: outcome.events)
            } else {
                try refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
            }
            return outcome.didMutate
        } catch {
            if error is TaskLifecycleMutationError {
                refreshStoreScopedTaskLifecycleReadModels()
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteSelectedTask(
        taskID: UUID? = nil,
        preservingDestination: DesktopDestination? = nil
    ) -> Bool {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return false }
        let destinationBeforeDelete = preservingDestination ?? desktopDestination
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try StoreScopedTaskLifecycleCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).delete(taskID: targetID)
            let wasSelected = selectedTaskID.map {
                outcome.deletedTaskIDs.contains($0)
            } ?? false
            let wasShowingDeletedDetail = tasksRoute.map {
                outcome.deletedTaskIDs.contains($0.taskID)
            } ?? false
            finishStoreScopedMutation(events: outcome.events)
            if outcome.stoppedSegments.isEmpty,
               outcome.terminatedPomodoros.isEmpty {
                refreshStoreScopedTimerReadModels()
            }
            if wasSelected {
                selectedTaskID = activeSegments.first(where: {
                    outcome.deletedTaskIDs.contains($0.taskID) == false &&
                        taskByID[$0.taskID] != nil
                })?.taskID ?? tasks.first(where: {
                    outcome.deletedTaskIDs.contains($0.id) == false &&
                        isTaskAvailableForTracking($0)
                })?.id
            }
            if wasShowingDeletedDetail {
                tasksRoute = nil
            }
            desktopDestination = destinationBeforeDelete
            return true
        } catch {
            if error is TaskLifecycleMutationError {
                refreshStoreScopedTaskLifecycleReadModels()
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func performStoreScopedTaskStatusTransition(
        _ status: TaskStatus,
        taskID: UUID
    ) -> Bool {
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try StoreScopedTaskLifecycleCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).setStatus(status, taskID: taskID)
            if outcome.didMutate {
                finishStoreScopedMutation(events: outcome.events)
            } else {
                try refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
            }
            refreshStoreScopedTimerReadModels()
            return true
        } catch {
            if error is TaskLifecycleMutationError {
                refreshStoreScopedTaskLifecycleReadModels()
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Converges every read model used by a task-lifecycle admission check
    /// after a fresh-context command rejects stale scene input.
    private func refreshStoreScopedTaskLifecycleReadModels() {
        do {
            try refresh(
                plan: StoreRefreshPlan(
                    scopes: [.tasks, .ledgerVisible, .pomodoro, .checklist]
                )
            )
        } catch {
            errorMessage = String(
                format: AppStrings.localized("error.savedRefreshFailed"),
                error.localizedDescription
            )
        }
    }
}
