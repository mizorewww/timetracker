import Foundation

@MainActor
struct TaskDraftCommandHandler {
    @discardableResult
    func save(
        draft: TaskEditorDraft,
        sanitizedTitle: String,
        taskRepository: SwiftDataTaskRepository,
        saveChecklistDrafts: ([ChecklistEditorDraft], UUID) throws -> Void
    ) throws -> UUID {
        if let taskID = draft.taskID {
            try update(taskID: taskID, draft: draft, title: sanitizedTitle, repository: taskRepository)
            try saveChecklistDrafts(draft.checklistItems, taskID)
            return taskID
        }

        let task = try taskRepository.createTask(
            title: sanitizedTitle,
            parentID: draft.parentID,
            categoryID: draft.categoryID,
            colorHex: draft.colorHex,
            iconName: draft.iconName
        )
        try update(taskID: task.id, draft: draft, title: sanitizedTitle, repository: taskRepository)
        try saveChecklistDrafts(draft.checklistItems, task.id)
        return task.id
    }

    /// Persists a new task with an identity owned by an enclosing idempotent
    /// transaction. Ordinary task creation continues to use `save`, where the
    /// repository owns identity generation.
    @discardableResult
    func saveNew(
        draft: TaskEditorDraft,
        proposedTaskID: UUID,
        sanitizedTitle: String,
        taskRepository: SwiftDataTaskRepository,
        saveChecklistDrafts: ([ChecklistEditorDraft], UUID) throws -> Void
    ) throws -> UUID {
        let task = try taskRepository.createTask(
            proposedID: proposedTaskID,
            title: sanitizedTitle,
            parentID: draft.parentID,
            categoryID: draft.categoryID,
            colorHex: draft.colorHex,
            iconName: draft.iconName
        )
        try update(
            taskID: task.id,
            draft: draft,
            title: sanitizedTitle,
            repository: taskRepository
        )
        try saveChecklistDrafts(draft.checklistItems, task.id)
        return task.id
    }

    func archive(taskID: UUID, repository: SwiftDataTaskRepository) throws {
        try repository.archiveTask(taskID: taskID)
    }

    func unarchive(taskID: UUID, repository: SwiftDataTaskRepository) throws {
        try repository.unarchiveTask(taskID: taskID)
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
