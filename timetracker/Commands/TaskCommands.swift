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

    func archive(taskID: UUID, repository: TaskRepository) throws {
        try ArchiveTaskUseCase(repository: repository).execute(taskID: taskID)
    }

    func unarchive(taskID: UUID, repository: TaskRepository) throws {
        try UnarchiveTaskUseCase(repository: repository).execute(taskID: taskID)
    }

    func softDelete(
        taskID: UUID,
        affectedTaskIDs: Set<UUID>,
        activeSegments: [TimeSegment],
        pomodoroRuns: [PomodoroRun],
        taskRepository: TaskRepository,
        timeRepository: TimeTrackingRepository,
        pomodoroRepository: PomodoroRepository
    ) throws {
        // A run can be active while resting even though it has no ledger
        // segment. Cancel runs first so every Pomodoro is made terminal and its
        // focus session is closed before its task disappears. Deletion always
        // preserves history, including very short focus attempts.
        for run in pomodoroRuns where affectedTaskIDs.contains(run.taskID) && run.isActiveForTaskDeletion {
            try CancelPomodoroUseCase(repository: pomodoroRepository).execute(
                runID: run.id,
                discardRecord: false
            )
        }

        // Pomodoro cancellation already closes its session. This second pass is
        // intentionally idempotent and catches regular timers plus any orphaned
        // Pomodoro segment whose run is missing.
        for segment in activeSegments where affectedTaskIDs.contains(segment.taskID) {
            try StopSegmentUseCase(repository: timeRepository).execute(segmentID: segment.id)
        }

        try SoftDeleteTaskUseCase(repository: taskRepository).execute(taskID: taskID)
    }

    private func update(taskID: UUID, draft: TaskEditorDraft, title: String, repository: TaskRepository) throws {
        try UpdateTaskUseCase(repository: repository).execute(
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

private extension PomodoroRun {
    var isActiveForTaskDeletion: Bool {
        deletedAt == nil &&
            endedAt == nil &&
            state != .completed &&
            state != .cancelled
    }
}
