import Foundation

@MainActor
struct TaskDraftCommandHandler {
    @discardableResult
    func save(
        draft: TaskEditorDraft,
        sanitizedTitle: String,
        taskRepository: TaskRepository,
        saveChecklistDrafts: ([ChecklistEditorDraft], UUID) throws -> Void
    ) throws -> UUID {
        if let taskID = draft.taskID {
            try update(taskID: taskID, draft: draft, title: sanitizedTitle, repository: taskRepository)
            try saveChecklistDrafts(draft.checklistItems, taskID)
            return taskID
        }

        let task = try CreateTaskUseCase(repository: taskRepository).execute(
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

    func archive(taskID: UUID, repository: TaskRepository) throws {
        try ArchiveTaskUseCase(repository: repository).execute(taskID: taskID)
    }

    func setStatus(_ status: TaskStatus, taskID: UUID, repository: TaskRepository) throws {
        try SetTaskStatusUseCase(repository: repository).execute(taskID: taskID, status: status)
    }

    func softDelete(taskID: UUID, repository: TaskRepository) throws {
        try SoftDeleteTaskUseCase(repository: repository).execute(taskID: taskID)
    }

    private func update(taskID: UUID, draft: TaskEditorDraft, title: String, repository: TaskRepository) throws {
        try UpdateTaskUseCase(repository: repository).execute(
            taskID: taskID,
            title: title,
            status: draft.status,
            parentID: draft.parentID,
            categoryID: draft.categoryID,
            colorHex: draft.colorHex,
            iconName: draft.iconName,
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            estimatedSeconds: draft.estimatedMinutes.map { $0 * 60 },
            dueAt: draft.hasDueDate ? draft.dueAt : nil
        )
    }
}
