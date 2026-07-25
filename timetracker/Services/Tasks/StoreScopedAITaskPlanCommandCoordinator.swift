import Foundation
import SwiftData

@MainActor
struct StoreScopedAITaskPlanCommandCoordinator {
    let container: ModelContainer
    let writeAuthorization: StoreWriteAuthorization
    let deviceID: String?
    private let didReachCheckpoint: (AITaskPlanMutationCheckpoint) throws -> Void

    init(
        container: ModelContainer,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
        deviceID: String? = nil,
        didReachCheckpoint: @escaping (AITaskPlanMutationCheckpoint) throws -> Void = { _ in }
    ) {
        self.container = container
        self.writeAuthorization = writeAuthorization
        self.deviceID = deviceID
        self.didReachCheckpoint = didReachCheckpoint
    }

    func apply(
        _ draft: AITaskPlanDraft,
        now: Date = Date()
    ) throws -> AITaskPlanMutationOutcome {
        try writeAuthorization.requireUserWritesAllowed()
        let prepared = try Self.prepare(draft)
        let transaction = try StoreScopedTimerMutationTransaction(
            scope: TimerStoreScope(container: container),
            container: container
        )
        return try transaction.withFreshContext { context in
            let persistedCategoryIDs = try Set(
                context.fetch(FetchDescriptor<TaskCategory>()).map(\.id)
            )
            let persistedTaskIDs = try Set(
                context.fetch(FetchDescriptor<TaskNode>()).map(\.id)
            )
            let presentCategoryIDs = prepared.categoryIDs.intersection(persistedCategoryIDs)
            let presentTaskIDs = prepared.taskIDs.intersection(persistedTaskIDs)
            let expectedIdentityCount = prepared.categoryIDs.count + prepared.taskIDs.count
            let presentIdentityCount = presentCategoryIDs.count + presentTaskIDs.count

            if presentIdentityCount == expectedIdentityCount {
                return AITaskPlanMutationOutcome(
                    createdCategoryIDs: [],
                    createdTaskIDs: [],
                    firstRootTaskID: prepared.firstRootTaskID,
                    didCreate: false
                )
            }
            guard presentIdentityCount == 0 else {
                throw StoreScopedAITaskPlanMutationError.identityConflict
            }

            let resolvedDeviceID = deviceID ?? DeviceIdentity.current
            let repository = SwiftDataTaskRepository(
                context: context,
                deviceID: resolvedDeviceID
            )

            for category in prepared.categories {
                _ = try repository.createCategory(
                    proposedID: category.id,
                    title: category.title,
                    colorHex: category.colorHex,
                    iconName: category.iconName,
                    includesInForecast: true
                )
                try didReachCheckpoint(.categoryCreated(category.id))
            }

            var createdTaskIDs = Set<UUID>()
            for task in prepared.topologicallySortedTasks {
                var editorDraft = TaskEditorDraft(
                    parentID: task.parentID,
                    categoryID: task.categoryID
                )
                editorDraft.title = task.title
                editorDraft.colorHex = task.colorHex ?? ""
                editorDraft.iconName = task.iconName ?? ""
                editorDraft.notes = task.notes ?? ""
                editorDraft.estimatedMinutes = task.estimatedMinutes
                editorDraft.checklistItems = task.checklistItems
                editorDraft.quantityGoal = task.progress.quantityGoal.map {
                    TaskQuantityGoalDraft(
                        targetAmount: $0.targetAmount,
                        unitLabel: $0.unitLabel
                    )
                }
                editorDraft.dailyRecurrence = task.progress.dailyRecurrence

                let savedTaskID = try TaskDraftCommandHandler().saveNew(
                    draft: editorDraft,
                    proposedTaskID: task.id,
                    sanitizedTitle: task.title,
                    taskRepository: repository,
                    saveChecklistDrafts: { checklistDrafts, taskID in
                        try didReachCheckpoint(.taskCreated(taskID))
                        try ChecklistDraftService().save(
                            drafts: checklistDrafts,
                            taskID: taskID,
                            context: context,
                            deviceID: resolvedDeviceID
                        )
                        try didReachCheckpoint(.checklistSaved(taskID: taskID))
                    }
                )
                _ = try TaskDraftProgressMutationService(
                    context: context,
                    container: container,
                    writeAuthorization: writeAuthorization,
                    deviceID: resolvedDeviceID,
                    didReachCheckpoint: { checkpoint in
                        try didReachCheckpoint(
                            .progress(
                                taskID: savedTaskID,
                                checkpoint: checkpoint
                            )
                        )
                    }
                ).apply(
                    task.progress,
                    to: savedTaskID,
                    now: now
                )
                createdTaskIDs.insert(task.id)
            }

            return AITaskPlanMutationOutcome(
                createdCategoryIDs: prepared.categories.map(\.id),
                createdTaskIDs: draft.tasks.compactMap {
                    createdTaskIDs.contains($0.id) ? $0.id : nil
                },
                firstRootTaskID: prepared.firstRootTaskID,
                didCreate: true
            )
        }
    }
}

private extension StoreScopedAITaskPlanCommandCoordinator {
    struct PreparedCategory {
        let id: UUID
        let title: String
        let iconName: String?
        let colorHex: String?
    }

    struct PreparedTask {
        let id: UUID
        let categoryID: UUID?
        let parentID: UUID?
        let title: String
        let notes: String?
        let estimatedMinutes: Int?
        let iconName: String?
        let colorHex: String?
        let checklistItems: [ChecklistEditorDraft]
        let progress: PreparedTaskProgressDraft
    }

    struct PreparedPlan {
        let categories: [PreparedCategory]
        let topologicallySortedTasks: [PreparedTask]
        let categoryIDs: Set<UUID>
        let taskIDs: Set<UUID>
        let firstRootTaskID: UUID?
    }

    static func prepare(_ draft: AITaskPlanDraft) throws -> PreparedPlan {
        guard draft.tasks.isEmpty == false else {
            throw LLMTaskPlanServiceError.noTasks
        }
        let checklistCount = draft.tasks.reduce(0) { $0 + $1.checklistItems.count }
        guard draft.categories.count <= LLMTaskPlanService.maximumCategoryCount,
              draft.tasks.count <= LLMTaskPlanService.maximumTaskCount,
              checklistCount <= LLMTaskPlanService.maximumChecklistItemCount,
              draft.tasks.allSatisfy({
                  $0.checklistItems.count <= LLMTaskPlanService.maximumChecklistItemCountPerTask
              })
        else {
            throw LLMTaskPlanServiceError.limitExceeded
        }

        let allIDs = draft.categories.map(\.id) +
            draft.tasks.map(\.id) +
            draft.tasks.flatMap { $0.checklistItems.map(\.id) }
        guard Set(allIDs).count == allIDs.count else {
            throw LLMTaskPlanServiceError.duplicateReference
        }

        let categoryIDs = Set(draft.categories.map(\.id))
        let taskIDs = Set(draft.tasks.map(\.id))
        let appleHealthPlan = AppleHealthTaskCatalog.plan(
            for: AppleHealthTaskCatalog.allRoles
        )
        let reservedAppleHealthIDs = Set(
            appleHealthPlan.categories.map(\.id)
        ).union(AppleHealthTaskCatalog.syncOnlyTaskIDs)
        guard categoryIDs.union(taskIDs).isDisjoint(
            with: reservedAppleHealthIDs
        ) else {
            throw StoreScopedAITaskPlanMutationError.identityConflict
        }
        for task in draft.tasks {
            if task.parentID != nil, task.categoryID != nil {
                throw LLMTaskPlanServiceError.childCategory
            }
            if let parentID = task.parentID, taskIDs.contains(parentID) == false {
                throw LLMTaskPlanServiceError.orphanReference
            }
            if let categoryID = task.categoryID, categoryIDs.contains(categoryID) == false {
                throw LLMTaskPlanServiceError.orphanReference
            }
            if let minutes = task.estimatedMinutes,
               TaskEstimatePolicy.minuteRange.contains(minutes) == false
            {
                throw LLMTaskPlanServiceError.invalidField
            }
        }
        try validateGraph(draft.tasks)

        let categories = try draft.categories.map { category in
            let values = try TaskPersistencePolicy.prepareCategory(
                title: category.title,
                colorHex: category.colorHex,
                iconName: category.iconName
            )
            return PreparedCategory(
                id: category.id,
                title: values.title,
                iconName: values.iconName,
                colorHex: values.colorHex
            )
        }
        let tasks = try draft.tasks.map { task in
            let values = try TaskPersistencePolicy.prepareTask(
                title: task.title,
                colorHex: task.colorHex,
                iconName: task.iconName,
                notes: task.notes
            )
            let checklistDrafts = task.checklistItems.map {
                ChecklistEditorDraft(
                    title: $0.title,
                    iconName: $0.iconName,
                    colorHex: $0.colorHex
                )
            }
            let preparedChecklist = try ChecklistDraftPersistencePolicy.prepare(checklistDrafts)
            let preparedProgress = try TaskProgressDraftPersistencePolicy
                .prepare(
                    quantityGoal: task.quantityGoal,
                    dailyRecurrence: task.dailyRecurrence
                )
            return PreparedTask(
                id: task.id,
                categoryID: task.categoryID,
                parentID: task.parentID,
                title: values.title,
                notes: values.notes,
                estimatedMinutes: task.estimatedMinutes,
                iconName: values.iconName,
                colorHex: values.colorHex,
                checklistItems: preparedChecklist.map {
                    ChecklistEditorDraft(
                        title: $0.title,
                        isCompleted: $0.isCompleted,
                        iconName: $0.iconName,
                        colorHex: $0.colorHex
                    )
                },
                progress: preparedProgress
            )
        }

        return PreparedPlan(
            categories: categories,
            topologicallySortedTasks: topologicalSort(tasks),
            categoryIDs: categoryIDs,
            taskIDs: taskIDs,
            firstRootTaskID: draft.tasks.first(where: { $0.parentID == nil })?.id
        )
    }

    static func validateGraph(_ tasks: [AITaskPlanTaskDraft]) throws {
        enum VisitState {
            case visiting
            case visited
        }

        let parentIDByTaskID = Dictionary(
            uniqueKeysWithValues: tasks.map { ($0.id, $0.parentID) }
        )
        var states: [UUID: VisitState] = [:]
        var depthByTaskID: [UUID: Int] = [:]

        func depth(for taskID: UUID) throws -> Int {
            if let depth = depthByTaskID[taskID] {
                return depth
            }
            if states[taskID] == .visiting {
                throw LLMTaskPlanServiceError.cycle
            }
            guard let optionalParentID = parentIDByTaskID[taskID] else {
                throw LLMTaskPlanServiceError.orphanReference
            }

            states[taskID] = .visiting
            let resolvedDepth: Int = if let parentID = optionalParentID {
                try depth(for: parentID) + 1
            } else {
                0
            }
            guard resolvedDepth <= LLMTaskPlanService.maximumTaskDepth else {
                throw LLMTaskPlanServiceError.depthExceeded
            }
            states[taskID] = .visited
            depthByTaskID[taskID] = resolvedDepth
            return resolvedDepth
        }

        for task in tasks {
            _ = try depth(for: task.id)
        }
    }

    static func topologicalSort(_ tasks: [PreparedTask]) -> [PreparedTask] {
        var remaining = tasks
        var createdIDs = Set<UUID>()
        var sorted: [PreparedTask] = []
        sorted.reserveCapacity(tasks.count)

        while remaining.isEmpty == false {
            let ready = remaining.filter {
                $0.parentID == nil || createdIDs.contains($0.parentID!)
            }
            precondition(ready.isEmpty == false, "Validated AI task graph must be sortable")
            let readyIDs = Set(ready.map(\.id))
            sorted.append(contentsOf: ready)
            createdIDs.formUnion(readyIDs)
            remaining.removeAll { readyIDs.contains($0.id) }
        }
        return sorted
    }
}
