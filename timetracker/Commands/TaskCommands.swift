import Foundation

@MainActor
struct TaskDraftCommandHandler {
    /// Updates the draft's task, or creates it with `newTaskID` (an identity
    /// an enclosing idempotent command may choose) when the draft is new.
    @discardableResult
    func save(
        draft: TaskEditorDraft,
        newTaskID: UUID = UUID(),
        sanitizedTitle: String,
        taskRepository: SwiftDataTaskRepository,
        saveChecklistDrafts: ([ChecklistEditorDraft], UUID) throws -> Void
    ) throws -> UUID {
        let taskID = try draft.taskID ?? taskRepository.createTask(
            proposedID: newTaskID,
            title: sanitizedTitle,
            parentID: draft.parentID,
            categoryID: draft.categoryID,
            colorHex: draft.colorHex,
            iconName: draft.iconName
        ).id
        try update(taskID: taskID, draft: draft, title: sanitizedTitle, repository: taskRepository)
        try saveChecklistDrafts(draft.checklistItems, taskID)
        return taskID
    }

    private func update(taskID: UUID, draft: TaskEditorDraft, title: String, repository: SwiftDataTaskRepository) throws {
        try repository.updateTask(
            taskID: taskID,
            title: title,
            parentID: draft.parentID,
            categoryID: draft.categoryID,
            colorHex: draft.colorHex,
            iconName: draft.iconName,
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            estimatedSeconds: TaskEstimatePolicy.seconds(fromMinutes: draft.estimatedMinutes),
            dueAt: draft.hasDueDate ? draft.dueAt : nil
        )
    }
}
