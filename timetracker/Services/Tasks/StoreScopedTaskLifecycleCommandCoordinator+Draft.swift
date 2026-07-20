import Foundation
import SwiftData

extension StoreScopedTaskLifecycleCommandCoordinator {
    func save(
        draft: TaskEditorDraft,
        sanitizedTitle: String,
        proposedTaskID: UUID? = nil
    ) throws -> TaskDraftMutationOutcome {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )

        return try transaction.withFreshContext { context in
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
               }) {
                return TaskDraftMutationOutcome(
                    savedTaskID: savedTask.id,
                    relatedTaskIDs: Self.relatedTaskIDs(
                        for: savedTask,
                        tasks: tasksBeforeSave
                    ),
                    checklistAncestorIDs: Self.ancestorTaskIDs(
                        for: savedTask,
                        tasks: tasksBeforeSave
                    )
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
            let savedTaskID: UUID
            if let proposedTaskID {
                savedTaskID = try TaskDraftCommandHandler().saveNew(
                    draft: draft,
                    proposedTaskID: proposedTaskID,
                    sanitizedTitle: sanitizedTitle,
                    taskRepository: taskRepository,
                    saveChecklistDrafts: saveChecklistDrafts
                )
            } else {
                savedTaskID = try TaskDraftCommandHandler().save(
                    draft: draft,
                    sanitizedTitle: sanitizedTitle,
                    taskRepository: taskRepository,
                    saveChecklistDrafts: saveChecklistDrafts
                )
            }

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
                )
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
              let parent = taskByID[currentID] {
            ancestors.insert(currentID)
            parentID = parent.parentID
        }
        return ancestors
    }

    private static func validateDraft(
        _ draft: TaskEditorDraft,
        existingTask: TaskNode?,
        tasks: [TaskNode],
        taskRepository: SwiftDataTaskRepository,
        context: ModelContext
    ) throws {
        if let existingTask {
            guard let baseline = draft.baseline,
                  baseline.taskMutationID == existingTask.clientMutationID,
                  try baselineMatchesCurrentRelatedModels(
                    baseline,
                    taskID: existingTask.id,
                    taskRepository: taskRepository,
                    context: context
                  ) else {
                throw TaskLifecycleMutationError.staleDraft
            }
        }

        let parentIsChanging = existingTask?.parentID != draft.parentID
        if let existingTask, parentIsChanging,
           let blocker = TaskTrackingAvailabilityService().parentChangeBlocker(for: existingTask) {
            throw TaskLifecycleMutationError.parentChangeBlocked(blocker)
        }
        if let parentID = draft.parentID,
           parentIsChanging,
           TaskTrackingAvailabilityService()
            .trackableTaskIDs(tasks: tasks)
            .contains(parentID) == false {
            throw TaskLifecycleMutationError.parentUnavailable
        }

        if draft.parentID == nil,
           let categoryID = draft.categoryID,
           try taskRepository.category(id: categoryID) == nil {
            throw TaskLifecycleMutationError.staleDraft
        }
    }

    private static func baselineMatchesCurrentRelatedModels(
        _ baseline: TaskEditorDraftBaseline,
        taskID: UUID,
        taskRepository: SwiftDataTaskRepository,
        context: ModelContext
    ) throws -> Bool {
        let requestedTaskID = taskID
        let checklistItems = try context.fetch(
            FetchDescriptor<ChecklistItem>(
                predicate: #Predicate { $0.taskID == requestedTaskID }
            )
        ).visibleDeduplicatedByID()
        let checklistItemMutationIDs = checklistItems.reduce(into: [UUID: UUID]()) {
            $0[$1.id] = $1.clientMutationID
        }
        guard checklistItemMutationIDs == baseline.checklistItemMutationIDs else {
            return false
        }

        let checklistItemIDs = Array(checklistItemMutationIDs.keys)
        let visualMutationIDs: [UUID: UUID]
        if checklistItemIDs.isEmpty {
            visualMutationIDs = [:]
        } else {
            visualMutationIDs = try context.fetch(
                FetchDescriptor<ChecklistItemVisual>(
                    predicate: #Predicate {
                        checklistItemIDs.contains($0.checklistItemID)
                    }
                )
            )
            .deduplicatedByID()
            .logicalWinnersByChecklistItemID()
            .reduce(into: [:]) { result, pair in
                guard pair.value.deletedAt == nil else { return }
                result[pair.key] = pair.value.clientMutationID
            }
        }
        guard visualMutationIDs == baseline.checklistVisualMutationIDs else {
            return false
        }

        let categoryAssignment = try taskRepository
            .categoryAssignments()
            .logicalWinnersByTaskID()[taskID]
        let categoryAssignmentMutationID = categoryAssignment?.deletedAt == nil
            ? categoryAssignment?.clientMutationID
            : nil
        return categoryAssignmentMutationID == baseline.categoryAssignmentMutationID
    }
}
