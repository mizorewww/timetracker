import Foundation
import SwiftData

/// Serializes local task availability changes with every timer admission for
/// the same SwiftData store. The canonical subtree and active work set are
/// fetched only after the shared timer lock is held.
@MainActor
struct StoreScopedTaskLifecycleCommandCoordinator {
    let container: ModelContainer
    let writeAuthorization: StoreWriteAuthorization
    let deviceID: String?
    let didReachDraftCheckpoint:
        @Sendable (TaskDraftMutationCheckpoint) throws -> Void

    init(
        container: ModelContainer,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
        deviceID: String? = nil,
        didReachDraftCheckpoint: @escaping
        @Sendable (TaskDraftMutationCheckpoint) throws -> Void = { _ in }
    ) {
        self.container = container
        self.writeAuthorization = writeAuthorization
        self.deviceID = deviceID
        self.didReachDraftCheckpoint = didReachDraftCheckpoint
    }

    func mutationSession() -> StoreScopedMutationSession {
        StoreScopedMutationSession(
            container: container,
            writeAuthorization: writeAuthorization
        )
    }

    func archive(taskID: UUID) throws -> TaskArchiveMutationOutcome {
        try mutationSession().withFreshMutationContext { context in
            let taskRepository = SwiftDataTaskRepository(
                context: context,
                deviceID: deviceID
            )
            let tasks = try taskRepository.allNodes()
            guard let task = tasks.first(where: { $0.id == taskID }) else {
                throw TaskLifecycleMutationError.taskNotFound
            }

            let relatedTaskIDs = Self.relatedTaskIDs(
                for: task,
                tasks: tasks
            )
            let hasCanonicalArchiveMarkers =
                task.archivedAt != nil &&
                task.statusRaw == LegacyTaskStatusRaw.archived
            guard hasCanonicalArchiveMarkers == false else {
                return TaskArchiveMutationOutcome(
                    taskID: taskID,
                    didMutate: false,
                    relatedTaskIDs: relatedTaskIDs
                )
            }

            let subtreeIDs = TaskTreeService()
                .descendantIDs(of: taskID, tasks: tasks)
                .union([taskID])
            let timeRepository = SwiftDataTimeTrackingRepository(
                context: context,
                deviceID: deviceID
            )
            let pomodoroRepository = SwiftDataPomodoroRepository(
                context: context,
                timeRepository: timeRepository,
                deviceID: deviceID
            )
            let hasActiveSegment = try timeRepository.activeSegments()
                .contains { subtreeIDs.contains($0.taskID) }
            let hasActivePomodoro = try pomodoroRepository.activeRuns()
                .contains { subtreeIDs.contains($0.taskID) }
            guard hasActiveSegment == false, hasActivePomodoro == false else {
                throw TaskLifecycleMutationError.activeWorkMustStop
            }

            try TaskDraftCommandHandler().archive(
                taskID: taskID,
                repository: taskRepository
            )
            return TaskArchiveMutationOutcome(
                taskID: taskID,
                didMutate: true,
                relatedTaskIDs: relatedTaskIDs
            )
        }
    }

    func unarchive(taskID: UUID) throws -> TaskUnarchiveMutationOutcome {
        try mutationSession().withFreshMutationContext { context in
            let taskRepository = SwiftDataTaskRepository(
                context: context,
                deviceID: deviceID
            )
            let tasks = try taskRepository.allNodes()
            guard let task = tasks.first(where: { $0.id == taskID }) else {
                throw TaskLifecycleMutationError.taskNotFound
            }
            let relatedTaskIDs = Self.relatedTaskIDs(for: task, tasks: tasks)
            guard task.deletedAt == nil, task.isArchivedForLifecycle else {
                return TaskUnarchiveMutationOutcome(
                    taskID: taskID,
                    didMutate: false,
                    relatedTaskIDs: relatedTaskIDs
                )
            }
            let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
            let repairPlan = TaskHierarchyRepairPlan(canonicalTasks: tasks)
            guard TaskTrackingAvailabilityService().hasArchivedAncestor(
                of: task,
                taskByID: taskByID,
                taskIDsToDisplayAsRoots: repairPlan.taskIDsToDisplayAsRoots
            ) == false else {
                throw TaskLifecycleMutationError.archivedAncestorMustRestoreFirst
            }

            try TaskDraftCommandHandler().unarchive(
                taskID: taskID,
                repository: taskRepository
            )
            return TaskUnarchiveMutationOutcome(
                taskID: taskID,
                didMutate: true,
                relatedTaskIDs: relatedTaskIDs
            )
        }
    }

    static func relatedTaskIDs(
        for task: TaskNode,
        tasks: [TaskNode]
    ) -> Set<UUID> {
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var related = TaskTreeService()
            .descendantIDs(of: task.id, tasks: tasks)
            .union([task.id])
        var visited = Set<UUID>()
        var parentID = task.parentID
        while let currentID = parentID,
              visited.insert(currentID).inserted,
              let parent = taskByID[currentID]
        {
            related.insert(currentID)
            parentID = parent.parentID
        }
        return related
    }
}

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

extension StoreScopedTaskLifecycleCommandCoordinator {
    static func quantityGoalState(
        taskID: UUID,
        context: ModelContext
    ) throws -> (activeMutationID: UUID?, hasDeletedRow: Bool) {
        let requestedTaskID = taskID
        let rows = try context.fetch(
            FetchDescriptor<TaskQuantityGoal>(
                predicate: #Predicate { $0.taskID == requestedTaskID }
            )
        )
        let goal = rows.latestByID()[
            TaskProgressIdentity.quantityGoalID(taskID: taskID)
        ]
        return (
            activeMutationID: goal?.deletedAt == nil
                ? goal?.clientMutationID
                : nil,
            hasDeletedRow: goal?.deletedAt != nil
        )
    }

    static func quantityEntryRevision(
        taskID: UUID,
        context: ModelContext
    ) throws -> UUID {
        let requestedTaskID = taskID
        let entries = try context.fetch(
            FetchDescriptor<TaskQuantityEntry>(
                predicate: #Predicate { $0.taskID == requestedTaskID }
            )
        )
        return TaskQuantityEntryRevision.value(
            taskID: taskID,
            entries: entries
        )
    }
}

extension StoreScopedTaskLifecycleCommandCoordinator {
    static func validateDraft(
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
                      quantityGoalDraft: draft.quantityGoal,
                      confirmsQuantityProgressReset:
                      draft.confirmsQuantityProgressReset,
                      taskRepository: taskRepository,
                      context: context
                  )
            else {
                throw TaskLifecycleMutationError.staleDraft
            }
        }

        let parentIsChanging = existingTask?.parentID != draft.parentID
        if let existingTask, parentIsChanging,
           let blocker = TaskTrackingAvailabilityService()
           .parentChangeBlocker(for: existingTask)
        {
            throw TaskLifecycleMutationError.parentChangeBlocked(blocker)
        }
        if let parentID = draft.parentID,
           parentIsChanging,
           TaskTrackingAvailabilityService()
           .trackableTaskIDs(tasks: tasks)
           .contains(parentID) == false
        {
            throw TaskLifecycleMutationError.parentUnavailable
        }

        if draft.parentID == nil,
           let categoryID = draft.categoryID,
           try taskRepository.category(id: categoryID) == nil
        {
            throw TaskLifecycleMutationError.staleDraft
        }
    }

    private static func baselineMatchesCurrentRelatedModels(
        _ baseline: TaskEditorDraftBaseline,
        taskID: UUID,
        quantityGoalDraft: TaskQuantityGoalDraft?,
        confirmsQuantityProgressReset: Bool,
        taskRepository: SwiftDataTaskRepository,
        context: ModelContext
    ) throws -> Bool {
        let requestedTaskID = taskID
        let checklistItems = try context.fetch(
            FetchDescriptor<ChecklistItem>(
                predicate: #Predicate { $0.taskID == requestedTaskID }
            )
        ).visibleDeduplicatedByID()
        let checklistItemMutationIDs = checklistItems.reduce(
            into: [UUID: UUID]()
        ) {
            $0[$1.id] = $1.clientMutationID
        }
        guard checklistItemMutationIDs ==
            baseline.checklistItemMutationIDs
        else {
            return false
        }

        let checklistItemIDs = Array(checklistItemMutationIDs.keys)
        let visualMutationIDs: [UUID: UUID] = if checklistItemIDs.isEmpty {
            [:]
        } else {
            try context.fetch(
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
        guard visualMutationIDs ==
            baseline.checklistVisualMutationIDs
        else {
            return false
        }

        let categoryAssignment = try taskRepository
            .categoryAssignments()
            .logicalWinnersByTaskID()[taskID]
        let categoryAssignmentMutationID = categoryAssignment?.deletedAt == nil
            ? categoryAssignment?.clientMutationID
            : nil
        guard categoryAssignmentMutationID ==
            baseline.categoryAssignmentMutationID
        else {
            return false
        }

        let quantityGoalState = try quantityGoalState(
            taskID: taskID,
            context: context
        )
        guard quantityGoalState.activeMutationID ==
            baseline.quantityGoalMutationID
        else {
            return false
        }
        let willTombstoneEntries = (
            baseline.quantityGoalMutationID != nil &&
                quantityGoalDraft == nil &&
                confirmsQuantityProgressReset
        ) || (
            baseline.quantityGoalMutationID == nil &&
                quantityGoalDraft != nil &&
                quantityGoalState.hasDeletedRow
        )
        if willTombstoneEntries {
            let currentRevision = try quantityEntryRevision(
                taskID: taskID,
                context: context
            )
            let baselineRevision = baseline.quantityEntryRevision ??
                TaskQuantityEntryRevision.value(
                    taskID: taskID,
                    entries: []
                )
            guard currentRevision == baselineRevision else {
                return false
            }
        }
        return try recurrenceRuleMutationID(
            taskID: taskID,
            context: context
        ) == baseline.recurrenceRuleMutationID
    }

    private static func recurrenceRuleMutationID(
        taskID: UUID,
        context: ModelContext
    ) throws -> UUID? {
        let requestedTaskID = taskID
        let rows = try context.fetch(
            FetchDescriptor<TaskRecurrenceRule>(
                predicate: #Predicate {
                    $0.templateTaskID == requestedTaskID
                }
            )
        )
        let rule = rows.latestByID()[
            TaskProgressIdentity.recurrenceRuleID(
                templateTaskID: taskID
            )
        ]
        return rule?.deletedAt == nil ? rule?.clientMutationID : nil
    }
}
