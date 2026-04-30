import Foundation

extension TimeTrackerStore {
    func presentNewTask(
        parentID: UUID? = nil,
        preservingDestination: DesktopDestination? = nil,
        categoryID: UUID? = nil
    ) {
        taskEditorReturnDestination = preservingDestination ?? desktopDestination
        taskEditorDraft = TaskEditorDraft(parentID: parentID, categoryID: categoryID)
    }

    func presentEditTask(_ task: TaskNode) {
        taskEditorReturnDestination = desktopDestination
        taskEditorDraft = TaskEditorDraft(
            task: task,
            categoryID: taskCategoryIDByRootTaskID[task.id],
            checklistItems: checklistItems(for: task.id)
        )
    }

    @discardableResult
    func saveTaskDraft(_ draft: TaskEditorDraft) -> Bool {
        let sanitizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedTitle.isEmpty else {
            errorMessage = AppStrings.localized("task.nameRequired")
            return false
        }

        let didSave = perform(events: [
            .taskChanged(taskID: draft.taskID, affectedAncestorIDs: affectedAncestorIDs(for: draft.taskID, parentID: draft.parentID)),
            .checklistChanged(taskID: draft.taskID, affectedAncestorIDs: affectedAncestorIDs(for: draft.taskID, parentID: draft.parentID))
        ]) {
            let returnDestination = taskEditorReturnDestination
            selectedTaskID = try taskDraftCommandHandler.save(
                draft: draft,
                sanitizedTitle: sanitizedTitle,
                taskRepository: requiredTaskRepository(),
                saveChecklistDrafts: saveChecklistDrafts
            )
            if let returnDestination {
                desktopDestination = returnDestination
            }
        }
        if didSave {
            taskEditorDraft = nil
            taskEditorReturnDestination = nil
        }
        return didSave
    }

    func archiveSelectedTask(taskID: UUID? = nil) {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return }
        perform(event: .taskChanged(taskID: targetID, affectedAncestorIDs: affectedAncestorIDs(for: targetID))) {
            try taskDraftCommandHandler.archive(taskID: targetID, repository: requiredTaskRepository())
            if self.selectedTaskID == targetID {
                self.selectedTaskID = tasks.first(where: { $0.id != targetID })?.id
            }
        }
    }

    func setTaskStatus(_ status: TaskStatus, taskID: UUID? = nil) {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return }
        perform(event: .taskChanged(taskID: targetID, affectedAncestorIDs: affectedAncestorIDs(for: targetID))) {
            try taskDraftCommandHandler.setStatus(status, taskID: targetID, repository: requiredTaskRepository())
        }
    }

    func deleteSelectedTask(
        taskID: UUID? = nil,
        preservingDestination: DesktopDestination? = nil
    ) {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return }
        let destinationBeforeDelete = preservingDestination ?? desktopDestination
        perform(event: .taskChanged(taskID: targetID, affectedAncestorIDs: affectedAncestorIDs(for: targetID))) {
            try taskDraftCommandHandler.softDelete(taskID: targetID, repository: requiredTaskRepository())
            if self.selectedTaskID == targetID {
                self.selectedTaskID = nil
            }
            self.desktopDestination = destinationBeforeDelete
        }
    }

    private func saveChecklistDrafts(_ drafts: [ChecklistEditorDraft], taskID: UUID) throws {
        guard let modelContext else { throw StoreError.notConfigured }
        try checklistDraftService.save(drafts: drafts, taskID: taskID, context: modelContext)
    }
}
