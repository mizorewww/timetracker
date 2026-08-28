import Foundation
import SwiftData

extension StoreScopedTaskLifecycleCommandCoordinator {
    func save(
        draft: TaskEditorDraft,
        sanitizedTitle: String,
        proposedTaskID: UUID? = nil,
        now: Date = Date()
    ) throws -> TaskDraftMutationOutcome {
        // Authorization must reject a read-only store before any draft
        // validation work; the session re-checks it before taking the lock.
        try writeAuthorization.requireUserWritesAllowed()
        let preparedProgress = try TaskProgressDraftPersistencePolicy
            .prepare(
                quantityGoal: draft.quantityGoal,
                dailyRecurrence: draft.dailyRecurrence,
                confirmsQuantityProgressReset:
                draft.confirmsQuantityProgressReset
            )
        return try mutationSession().withFreshMutationContext { context in
            let resolvedDeviceID = deviceID ?? DeviceIdentity.current
            let taskRepository = SwiftDataTaskRepository(
                context: context,
                deviceID: resolvedDeviceID
            )
            let tasksBeforeSave = try taskRepository.allNodes()
            if draft.taskID == nil,
               let proposedTaskID,
               let savedTask = tasksBeforeSave.first(where: {
                   $0.id == proposedTaskID
               })
            {
                return TaskDraftMutationOutcome(
                    savedTaskID: savedTask.id,
                    relatedTaskIDs: Self.relatedTaskIDs(
                        for: savedTask,
                        tasks: tasksBeforeSave
                    ),
                    checklistAncestorIDs: Self.ancestorTaskIDs(
                        for: savedTask,
                        tasks: tasksBeforeSave
                    ),
                    recurrenceOutcome: .noChanges
                )
            }
            let existingTask: TaskNode?
            if let taskID = draft.taskID {
                guard let task = tasksBeforeSave.first(where: { $0.id == taskID }) else {
                    throw TaskLifecycleMutationError.taskNotFound
                }
                existingTask = task
            } else {
                existingTask = nil
            }

            try Self.validateDraft(
                draft,
                existingTask: existingTask,
                tasks: tasksBeforeSave,
                taskRepository: taskRepository,
                context: context
            )

            let relatedBeforeSave = existingTask.map {
                Self.relatedTaskIDs(for: $0, tasks: tasksBeforeSave)
            } ?? []
            let ancestorsBeforeSave = existingTask.map {
                Self.ancestorTaskIDs(for: $0, tasks: tasksBeforeSave)
            } ?? []
            let saveChecklistDrafts:
                ([ChecklistEditorDraft], UUID) throws -> Void = { drafts, taskID in
                    try ChecklistDraftService().save(
                        drafts: drafts,
                        taskID: taskID,
                        context: context,
                        deviceID: resolvedDeviceID
                    )
                }
            let savedTaskID: UUID = if let proposedTaskID {
                try TaskDraftCommandHandler().saveNew(
                    draft: draft,
                    proposedTaskID: proposedTaskID,
                    sanitizedTitle: sanitizedTitle,
                    taskRepository: taskRepository,
                    saveChecklistDrafts: saveChecklistDrafts
                )
            } else {
                try TaskDraftCommandHandler().save(
                    draft: draft,
                    sanitizedTitle: sanitizedTitle,
                    taskRepository: taskRepository,
                    saveChecklistDrafts: saveChecklistDrafts
                )
            }
            try didReachDraftCheckpoint(
                .taskAndChecklistSaved(savedTaskID)
            )

            let recurrenceOutcome = try TaskDraftProgressMutationService(
                context: context,
                container: container,
                writeAuthorization: writeAuthorization,
                deviceID: resolvedDeviceID,
                didReachCheckpoint: didReachDraftCheckpoint
            ).apply(
                preparedProgress,
                to: savedTaskID,
                now: now
            )

            let tasksAfterSave = try taskRepository.allNodes()
            guard let savedTask = tasksAfterSave.first(where: { $0.id == savedTaskID }) else {
                throw TaskLifecycleMutationError.taskNotFound
            }
            return TaskDraftMutationOutcome(
                savedTaskID: savedTaskID,
                relatedTaskIDs: relatedBeforeSave.union(
                    Self.relatedTaskIDs(for: savedTask, tasks: tasksAfterSave)
                ),
                checklistAncestorIDs: ancestorsBeforeSave.union(
                    Self.ancestorTaskIDs(for: savedTask, tasks: tasksAfterSave)
                ),
                recurrenceOutcome: recurrenceOutcome
            )
        }
    }

    private static func ancestorTaskIDs(
        for task: TaskNode,
        tasks: [TaskNode]
    ) -> Set<UUID> {
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var ancestors = Set<UUID>()
        var visited = Set<UUID>()
        var parentID = task.parentID
        while let currentID = parentID,
              visited.insert(currentID).inserted,
              let parent = taskByID[currentID]
        {
            ancestors.insert(currentID)
            parentID = parent.parentID
        }
        return ancestors
    }
}
