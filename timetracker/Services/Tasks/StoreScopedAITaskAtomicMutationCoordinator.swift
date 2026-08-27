import Foundation
import SwiftData

/// Applies a reviewed AI workspace proposal under the same store lock as task,
/// checklist, timer, and lifecycle commands. Provider-facing tools never call
/// this type directly.
actor StoreScopedAITaskAtomicMutationCoordinator {
    let container: ModelContainer
    let scope: TimerStoreScope
    let writeAuthorization: StoreWriteAuthorization
    let deviceID: String
    let nowProvider: @Sendable () -> Date
    private let didReachCheckpoint:
        @Sendable (AITaskAtomicMutationCheckpoint) throws -> Void

    @MainActor
    init(
        container: ModelContainer,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
        deviceID: String = DeviceIdentity.current,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        didReachCheckpoint: @escaping
        @Sendable (AITaskAtomicMutationCheckpoint) throws -> Void = { _ in }
    ) throws {
        self.container = container
        scope = try TimerStoreScope(container: container)
        self.writeAuthorization = writeAuthorization
        self.deviceID = deviceID
        self.nowProvider = nowProvider
        self.didReachCheckpoint = didReachCheckpoint
    }

    func captureBaseline() throws -> AITaskAtomicMutationBaseline {
        try PerformanceSignpost.interval("AI workspace baseline capture") {
            try StoreScopedTimerMutationTransaction(
                scope: scope,
                container: container
            ).withFreshReadContext { context in
                try Self.captureBaseline(in: context)
            }
        }
    }

    func apply(
        _ plan: AITaskAtomicMutationPlan
    ) async throws -> AITaskAtomicMutationOutcome {
        try await writeAuthorization.requireUserWritesAllowed()
        return try PerformanceSignpost.interval("AI workspace atomic apply") {
            try StoreScopedTimerMutationTransaction(
                scope: scope,
                container: container
            ).withFreshContext(author: .localMutation) { context in
                let current = try Self.captureBaseline(in: context)
                guard current == plan.baseline else {
                    throw AITaskAtomicMutationError.workspaceChanged
                }

                try validate(
                    operations: plan.operations,
                    startingFrom: current.snapshot,
                    context: context
                )

                let repository = SwiftDataTaskRepository(
                    context: context,
                    deviceID: deviceID
                )
                for (index, operation) in plan.operations.enumerated() {
                    try apply(
                        operation,
                        repository: repository,
                        context: context
                    )
                    try didReachCheckpoint(.operationApplied(index: index))
                }

                let didMutateTasks = plan.operations.contains {
                    $0.mutatesTaskDomain
                }
                let didMutateChecklists = plan.operations.contains {
                    $0.mutatesChecklistDomain
                }
                return AITaskAtomicMutationOutcome(
                    didMutate: didMutateTasks || didMutateChecklists,
                    didMutateTasks: didMutateTasks,
                    didMutateChecklists: didMutateChecklists
                )
            }
        }
    }
}

private extension StoreScopedAITaskAtomicMutationCoordinator {
    static func captureBaseline(
        in context: ModelContext
    ) throws -> AITaskAtomicMutationBaseline {
        let quantityGoals = try context.fetch(
            FetchDescriptor<TaskQuantityGoal>()
        ).visibleDeduplicatedByID()
        let recurrenceRules = try context.fetch(
            FetchDescriptor<TaskRecurrenceRule>()
        ).visibleDeduplicatedByID()
        let capture = try AITaskWorkspaceCapture(
            taskCategories: context.fetch(
                FetchDescriptor<TaskCategory>()
            ),
            tasks: context.fetch(FetchDescriptor<TaskNode>()),
            taskCategoryAssignments: context.fetch(
                FetchDescriptor<TaskCategoryAssignment>()
            ),
            checklistItems: context.fetch(
                FetchDescriptor<ChecklistItem>()
            ),
            checklistVisuals: context.fetch(
                FetchDescriptor<ChecklistItemVisual>()
            ),
            quantityGoals: quantityGoals,
            recurrenceRules: recurrenceRules
        )
        return AITaskAtomicMutationBaseline(
            snapshot: capture.snapshot,
            workspace: capture.baselines,
            quantityGoalMutationIDs: quantityGoals.reduce(into: [:]) {
                $0[$1.id] = $1.clientMutationID
            },
            recurrenceRuleMutationIDs: recurrenceRules.reduce(into: [:]) {
                $0[$1.id] = $1.clientMutationID
            }
        )
    }

    func validate(
        operations: [AITaskWorkspaceOperation],
        startingFrom snapshot: AITaskWorkspaceSnapshot,
        context: ModelContext
    ) throws {
        var overlay = AITaskWorkspaceOverlay(snapshot: snapshot)
        for operation in operations {
            try validateProtectedIdentities(in: operation)
            try replay(operation, in: &overlay)
        }
        try validateCreateIdentities(
            operations: operations,
            context: context
        )
        try validateArchiveAdmission(
            operations: operations,
            context: context
        )
    }

    func replay(
        _ operation: AITaskWorkspaceOperation,
        in overlay: inout AITaskWorkspaceOverlay
    ) throws {
        switch operation {
        case let .useExistingCategory(categoryID):
            guard let category = overlay.category(id: categoryID) else {
                throw AITaskAtomicMutationError.targetUnavailable(categoryID)
            }
            let resolved = try overlay.useExistingCategory(
                named: category.title
            )
            guard resolved.id == categoryID else {
                throw AITaskAtomicMutationError.invalidOperation
            }

        case let .createCategory(category):
            _ = try overlay.createCategory(
                id: category.id,
                title: category.title,
                iconName: category.iconName,
                colorHex: category.colorHex,
                includesInForecast: category.includesInForecast,
                sortOrder: category.sortOrder
            )

        case let .updateCategory(before, after):
            guard overlay.category(id: before.id) == before,
                  before.id == after.id
            else {
                throw AITaskAtomicMutationError.invalidOperation
            }
            _ = try overlay.updateCategory(
                id: after.id,
                title: after.title,
                iconName: after.iconName,
                colorHex: after.colorHex,
                includesInForecast: after.includesInForecast
            )

        case let .deleteCategory(category, _):
            guard overlay.category(id: category.id) == category else {
                throw AITaskAtomicMutationError.invalidOperation
            }
            _ = try overlay.deleteCategory(id: category.id)

        case let .createTask(task):
            _ = try overlay.createTask(
                id: task.id,
                title: task.title,
                parentID: task.parentID,
                categoryID: task.categoryID,
                notes: task.notes,
                estimatedMinutes: task.estimatedMinutes,
                dueAt: task.dueAt,
                iconName: task.iconName,
                colorHex: task.colorHex,
                quantityGoal: task.quantityGoal,
                dailyRecurrence: task.dailyRecurrence,
                sortOrder: task.sortOrder
            )

        case let .updateTask(before, after):
            guard overlay.task(id: before.id) == before,
                  before.id == after.id
            else {
                throw AITaskAtomicMutationError.invalidOperation
            }
            _ = try overlay.updateTask(
                id: after.id,
                title: after.title,
                parentID: after.parentID,
                categoryID: after.categoryID,
                notes: after.notes,
                estimatedMinutes: after.estimatedMinutes,
                dueAt: after.dueAt,
                iconName: after.iconName,
                colorHex: after.colorHex,
                quantityGoal: after.quantityGoal,
                dailyRecurrence: after.dailyRecurrence
            )

        case let .archiveTask(before, after, _):
            guard overlay.task(id: before.id) == before,
                  before.id == after.id
            else {
                throw AITaskAtomicMutationError.invalidOperation
            }
            _ = try overlay.deleteTask(id: before.id)

        case let .createChecklistItem(item):
            _ = try overlay.createChecklistItem(
                id: item.id,
                taskID: item.taskID,
                title: item.title,
                isCompleted: item.isCompleted,
                iconName: item.iconName,
                colorHex: item.colorHex,
                sortOrder: item.sortOrder
            )

        case let .updateChecklistItem(before, after):
            guard overlay.checklistItem(id: before.id) == before,
                  before.id == after.id,
                  before.taskID == after.taskID
            else {
                throw AITaskAtomicMutationError.invalidOperation
            }
            _ = try overlay.updateChecklistItem(
                id: after.id,
                title: after.title,
                isCompleted: after.isCompleted,
                iconName: after.iconName,
                colorHex: after.colorHex
            )

        case let .deleteChecklistItem(item):
            guard overlay.checklistItem(id: item.id) == item else {
                throw AITaskAtomicMutationError.invalidOperation
            }
            _ = try overlay.deleteChecklistItem(id: item.id)
        }
    }

    func validateProtectedIdentities(
        in operation: AITaskWorkspaceOperation
    ) throws {
        guard let affectedID = operation.affectedIdentity,
              Self.protectedAppleHealthIDs.contains(affectedID)
        else {
            return
        }
        throw AITaskAtomicMutationError.protectedIdentity(affectedID)
    }

    func validateCreateIdentities(
        operations: [AITaskWorkspaceOperation],
        context: ModelContext
    ) throws {
        let proposedIDs = operations.compactMap {
            $0.createdIdentity
        }
        guard Set(proposedIDs).count == proposedIDs.count else {
            throw AITaskAtomicMutationError.invalidOperation
        }
        // Deliberately re-fetched instead of reusing the baseline snapshot:
        // the workspace snapshot is `visibleDeduplicatedByID`-filtered, while
        // a create must also not collide with soft-deleted persisted rows.
        let persistedIDs = try Set(
            context.fetch(FetchDescriptor<TaskCategory>()).map(\.id) +
                context.fetch(FetchDescriptor<TaskNode>()).map(\.id) +
                context.fetch(FetchDescriptor<ChecklistItem>()).map(\.id)
        )
        if let collision = Set(proposedIDs).intersection(persistedIDs)
            .sorted(by: Self.uuidOrder)
            .first
        {
            throw AITaskAtomicMutationError.identityConflict(collision)
        }
    }

    func validateArchiveAdmission(
        operations: [AITaskWorkspaceOperation],
        context: ModelContext
    ) throws {
        let archivedTaskIDs = operations.reduce(into: Set<UUID>()) {
            result, operation in
            guard case let .archiveTask(
                before,
                _,
                affectedDescendantIDs
            ) = operation
            else {
                return
            }
            result.insert(before.id)
            result.formUnion(affectedDescendantIDs)
        }
        guard archivedTaskIDs.isEmpty == false else { return }

        let hasActiveSegment = try context.fetch(
            FetchDescriptor<TimeSegment>()
        ).visibleDeduplicatedByID()
            .filter { $0.endedAt == nil }
            .contains { archivedTaskIDs.contains($0.taskID) }
        let completed = PomodoroState.completed.rawValue
        let cancelled = PomodoroState.cancelled.rawValue
        let hasActivePomodoro = try context.fetch(
            FetchDescriptor<PomodoroRun>()
        ).visibleDeduplicatedByID()
            .filter {
                $0.endedAt == nil &&
                    $0.stateRaw != completed &&
                    $0.stateRaw != cancelled
            }
            .contains { archivedTaskIDs.contains($0.taskID) }
        guard hasActiveSegment == false, hasActivePomodoro == false else {
            throw AITaskAtomicMutationError.activeWorkMustStop
        }
    }

    static var protectedAppleHealthIDs: Set<UUID> {
        let plan = AppleHealthTaskCatalog.plan(
            for: AppleHealthTaskCatalog.allRoles
        )
        return Set(plan.categories.map(\.id))
            .union(AppleHealthTaskCatalog.syncOnlyTaskIDs)
    }

    static func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}

private extension StoreScopedAITaskAtomicMutationCoordinator {
    func apply(
        _ operation: AITaskWorkspaceOperation,
        repository: SwiftDataTaskRepository,
        context: ModelContext
    ) throws {
        let now = nowProvider()
        switch operation {
        case .useExistingCategory:
            return

        case let .createCategory(category):
            let created = try repository.createCategory(
                proposedID: category.id,
                title: category.title,
                colorHex: category.colorHex,
                iconName: category.iconName,
                includesInForecast: category.includesInForecast
            )
            created.sortOrder = category.sortOrder

        case let .updateCategory(_, after):
            try repository.updateCategory(
                categoryID: after.id,
                title: after.title,
                colorHex: after.colorHex,
                iconName: after.iconName,
                includesInForecast: after.includesInForecast
            )

        case let .deleteCategory(category, _):
            try repository.softDeleteCategory(categoryID: category.id)

        case let .createTask(task):
            let created = try repository.createTask(
                proposedID: task.id,
                title: task.title,
                parentID: task.parentID,
                categoryID: task.categoryID,
                colorHex: task.colorHex,
                iconName: task.iconName
            )
            created.notes = task.notes
            created.estimatedSeconds = task.estimatedMinutes.map { $0 * 60 }
            created.dueAt = task.dueAt
            created.sortOrder = task.sortOrder
            try applyTaskProgress(
                quantityGoal: task.quantityGoal,
                dailyRecurrence: task.dailyRecurrence,
                taskID: task.id,
                now: now,
                context: context
            )

        case let .updateTask(before, after):
            try repository.updateTask(
                taskID: after.id,
                title: after.title,
                parentID: after.parentID,
                categoryID: after.categoryID,
                colorHex: after.colorHex,
                iconName: after.iconName,
                notes: after.notes,
                estimatedSeconds: after.estimatedMinutes.map { $0 * 60 },
                dueAt: after.dueAt
            )
            if before.quantityGoal != after.quantityGoal ||
                before.dailyRecurrence != after.dailyRecurrence
            {
                try applyTaskProgress(
                    quantityGoal: after.quantityGoal,
                    dailyRecurrence: after.dailyRecurrence,
                    taskID: after.id,
                    now: now,
                    context: context
                )
            }

        case let .archiveTask(before, _, _):
            try repository.archiveTask(taskID: before.id)

        case let .createChecklistItem(item):
            try createChecklistItem(
                item,
                now: now,
                context: context
            )

        case let .updateChecklistItem(_, after):
            try updateChecklistItem(
                after,
                now: now,
                context: context
            )

        case let .deleteChecklistItem(item):
            try deleteChecklistItem(
                item,
                now: now,
                context: context
            )
        }
    }

    func applyTaskProgress(
        quantityGoal: TaskQuantityGoalDraft?,
        dailyRecurrence: TaskDailyRecurrenceDraft?,
        taskID: UUID,
        now: Date,
        context: ModelContext
    ) throws {
        let prepared = try TaskProgressDraftPersistencePolicy.prepare(
            quantityGoal: quantityGoal,
            dailyRecurrence: dailyRecurrence,
            confirmsQuantityProgressReset: true
        )
        _ = try TaskDraftProgressMutationService(
            context: context,
            container: container,
            writeAuthorization: writeAuthorization,
            deviceID: deviceID,
            didReachCheckpoint: { _ in }
        ).apply(
            prepared,
            to: taskID,
            now: now
        )
    }

    func createChecklistItem(
        _ proposed: AITaskWorkspaceChecklistItem,
        now: Date,
        context: ModelContext
    ) throws {
        let item = ChecklistItem(
            taskID: proposed.taskID,
            title: proposed.title,
            isCompleted: proposed.isCompleted,
            sortOrder: proposed.sortOrder,
            deviceID: deviceID
        )
        item.id = proposed.id
        item.createdAt = now
        item.updatedAt = now
        item.completedAt = proposed.isCompleted ? now : nil
        context.insert(item)

        let visual = ChecklistItemVisual(
            checklistItemID: item.id,
            iconName: proposed.iconName,
            colorHex: proposed.colorHex,
            userEditedAt: ChecklistVisualSanitizer.isDefault(
                iconName: proposed.iconName,
                colorHex: proposed.colorHex
            ) ? nil : now,
            deviceID: deviceID
        )
        visual.createdAt = now
        visual.updatedAt = now
        context.insert(visual)
    }

    func updateChecklistItem(
        _ proposed: AITaskWorkspaceChecklistItem,
        now: Date,
        context: ModelContext
    ) throws {
        guard let item = try visibleChecklistItem(
            id: proposed.id,
            context: context
        ) else {
            throw AITaskAtomicMutationError.targetUnavailable(proposed.id)
        }
        let itemChanged = item.title != proposed.title ||
            item.isCompleted != proposed.isCompleted ||
            item.sortOrder != proposed.sortOrder
        if itemChanged {
            if item.isCompleted != proposed.isCompleted {
                item.completedAt = proposed.isCompleted ? now : nil
                item.sortOrderBeforeCompletion = proposed.isCompleted
                    ? item.sortOrder
                    : nil
            }
            item.title = proposed.title
            item.isCompleted = proposed.isCompleted
            item.sortOrder = proposed.sortOrder
            item.updatedAt = now
            item.deviceID = deviceID
            item.clientMutationID = UUID()
        }

        let visual = try visibleChecklistVisual(
            itemID: proposed.id,
            context: context
        )
        let visualChanged = visual.map {
            ChecklistVisualSanitizer.sanitizedIcon($0.iconName) !=
                proposed.iconName ||
                ChecklistVisualSanitizer.sanitizedColor($0.colorHex) !=
                proposed.colorHex
        } ?? true
        guard visualChanged else { return }

        if let visual {
            visual.iconName = proposed.iconName
            visual.colorHex = proposed.colorHex
            visual.suggestionTitleSnapshot = proposed.title
            visual.suggestionModelID = "manual"
            visual.suggestionGeneratedAt = nil
            visual.userEditedAt = now
            visual.updatedAt = now
            visual.deviceID = deviceID
            visual.clientMutationID = UUID()
        } else {
            let created = ChecklistItemVisual(
                checklistItemID: proposed.id,
                iconName: proposed.iconName,
                colorHex: proposed.colorHex,
                suggestionTitleSnapshot: proposed.title,
                suggestionModelID: "manual",
                userEditedAt: now,
                deviceID: deviceID
            )
            created.createdAt = now
            created.updatedAt = now
            context.insert(created)
        }
    }

    func deleteChecklistItem(
        _ proposed: AITaskWorkspaceChecklistItem,
        now: Date,
        context: ModelContext
    ) throws {
        guard let item = try visibleChecklistItem(
            id: proposed.id,
            context: context
        ) else {
            throw AITaskAtomicMutationError.targetUnavailable(proposed.id)
        }
        item.deletedAt = now
        item.updatedAt = now
        item.deviceID = deviceID
        item.clientMutationID = UUID()

        if let visual = try visibleChecklistVisual(
            itemID: proposed.id,
            context: context
        ) {
            visual.deletedAt = now
            visual.updatedAt = now
            visual.deviceID = deviceID
            visual.clientMutationID = UUID()
        }
    }

    func visibleChecklistItem(
        id: UUID,
        context: ModelContext
    ) throws -> ChecklistItem? {
        let requestedID = id
        return try context.fetch(
            FetchDescriptor<ChecklistItem>(
                predicate: #Predicate { $0.id == requestedID }
            )
        ).visibleDeduplicatedByID().first
    }

    func visibleChecklistVisual(
        itemID: UUID,
        context: ModelContext
    ) throws -> ChecklistItemVisual? {
        let requestedItemID = itemID
        return try context.fetch(
            FetchDescriptor<ChecklistItemVisual>(
                predicate: #Predicate {
                    $0.checklistItemID == requestedItemID
                }
            )
        ).deduplicatedByID()
            .logicalWinnersByChecklistItemID()[itemID]
            .flatMap { $0.deletedAt == nil ? $0 : nil }
    }
}

private nonisolated extension AITaskWorkspaceOperation {
    enum MutatedDomain {
        case task
        case checklist
    }

    /// Each mutating operation touches exactly one domain;
    /// `useExistingCategory` is a read-only admission and mutates neither.
    var mutatedDomain: MutatedDomain? {
        switch self {
        case .useExistingCategory:
            nil
        case .createCategory,
             .updateCategory,
             .deleteCategory,
             .createTask,
             .updateTask,
             .archiveTask:
            .task
        case .createChecklistItem,
             .updateChecklistItem,
             .deleteChecklistItem:
            .checklist
        }
    }

    var mutatesTaskDomain: Bool {
        mutatedDomain == .task
    }

    var mutatesChecklistDomain: Bool {
        mutatedDomain == .checklist
    }

    /// The primary identity the operation writes: the proposed record for
    /// creates, the existing record for updates, archives, and deletes.
    var affectedIdentity: UUID? {
        switch self {
        case .useExistingCategory:
            nil
        case let .createCategory(category):
            category.id
        case let .updateCategory(before, _):
            before.id
        case let .deleteCategory(category, _):
            category.id
        case let .createTask(task):
            task.id
        case let .updateTask(before, _):
            before.id
        case let .archiveTask(before, _, _):
            before.id
        case let .createChecklistItem(item):
            item.id
        case let .updateChecklistItem(before, _):
            before.id
        case let .deleteChecklistItem(item):
            item.id
        }
    }

    var createdIdentity: UUID? {
        switch self {
        case .createCategory,
             .createTask,
             .createChecklistItem:
            affectedIdentity
        case .useExistingCategory,
             .updateCategory,
             .deleteCategory,
             .updateTask,
             .archiveTask,
             .updateChecklistItem,
             .deleteChecklistItem:
            nil
        }
    }
}
