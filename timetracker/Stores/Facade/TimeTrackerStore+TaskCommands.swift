import Foundation
import SwiftData

extension TimeTrackerStore {
    func editorDraft(for task: TaskNode) -> TaskEditorDraft {
        TaskEditorDraft(
            task: task,
            categoryID: taskCategoryIDByRootTaskID[task.id],
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
        if let taskID = draft.taskID,
           let currentTask = task(for: taskID),
           currentTask.status != draft.status,
           draft.status == .archived || draft.status == .completed,
           hasActiveTimer(inTaskSubtree: taskID) {
            errorMessage = AppStrings.localized(
                draft.status == .completed
                    ? "task.action.complete.stopFirst"
                    : "task.action.archive.stopFirst"
            )
            return false
        }
        if let taskID = draft.taskID,
           let currentTask = task(for: taskID),
           currentTask.parentID != draft.parentID,
           let blocker = parentChangeBlocker(for: currentTask) {
            let messageKey = switch blocker {
            case .completed: "task.parent.completedLocked"
            case .archived: "task.parent.archivedLocked"
            case .deleted: "task.parent.deletedLocked"
            }
            errorMessage = AppStrings.localized(messageKey)
            return false
        }
        if let parentID = draft.parentID,
           trackableTaskIDs.contains(parentID) == false,
           draft.taskID.flatMap({ task(for: $0) })?.parentID != parentID {
            errorMessage = AppStrings.localized("task.parentUnavailable")
            return false
        }

        let affectedHierarchyIDs = affectedTaskIDsForHierarchyChange(taskID: draft.taskID, parentID: draft.parentID)
        let primaryDraftTaskIDs = draft.taskID.map { Set([$0]) } ?? []
        var savedTaskID: UUID?
        let didSave = perform(events: [
            .taskChanged(taskID: draft.taskID, affectedAncestorIDs: affectedHierarchyIDs.subtracting(primaryDraftTaskIDs)),
            .checklistChanged(taskID: draft.taskID, affectedAncestorIDs: affectedAncestorIDs(for: draft.taskID, parentID: draft.parentID))
        ]) {
            savedTaskID = try taskDraftCommandHandler.save(
                draft: draft,
                sanitizedTitle: sanitizedTitle,
                taskRepository: requiredTaskRepository(),
                saveChecklistDrafts: saveChecklistDrafts
            )
        }
        if didSave {
            selectedTaskID = savedTaskID
            if let returnDestination {
                desktopDestination = returnDestination
            }
        }
        return didSave
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

    func reopenTaskForWork(_ taskID: UUID) {
        guard let task = task(for: taskID) else { return }
        let blockers = completedWorkBlockers(for: task)
        guard blockers.isEmpty == false else { return }
        let events = Set(blockers.map { blocker in
            StoreDomainEvent.taskChanged(
                taskID: blocker.id,
                affectedAncestorIDs: affectedAncestorIDs(for: blocker.id)
            )
        })
        perform(events: events) {
            for blocker in blockers {
                try taskDraftCommandHandler.setStatus(
                    .active,
                    taskID: blocker.id,
                    repository: requiredTaskRepository()
                )
            }
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
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func saveChecklistDrafts(_ drafts: [ChecklistEditorDraft], taskID: UUID) throws {
        guard let modelContext else { throw StoreError.notConfigured }
        try checklistDraftService.save(drafts: drafts, taskID: taskID, context: modelContext)
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
            errorMessage = error.localizedDescription
            return false
        }
    }
}
