import Foundation
import SwiftData

@MainActor
struct StoreScopedAppleHealthTaskCatalogCommandCoordinator {
    let container: ModelContainer
    let writeAuthorization: StoreWriteAuthorization
    let deviceID: String?
    private let didReachCheckpoint:
        (AppleHealthTaskCatalogMutationCheckpoint) throws -> Void

    init(
        container: ModelContainer,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
        deviceID: String? = nil,
        didReachCheckpoint: @escaping
        (AppleHealthTaskCatalogMutationCheckpoint) throws -> Void = { _ in }
    ) {
        self.container = container
        self.writeAuthorization = writeAuthorization
        self.deviceID = deviceID
        self.didReachCheckpoint = didReachCheckpoint
    }

    func apply(
        roles: Set<AppleHealthTaskRole>,
        clearRecoveryTaskIDs: Set<UUID> = [],
        now: Date = Date()
    ) throws -> AppleHealthTaskCatalogMutationOutcome {
        let allDefinitions = AppleHealthTaskCatalog.plan(
            for: AppleHealthTaskCatalog.allRoles
        ).tasks
        let definitionByID = Dictionary(
            uniqueKeysWithValues: allDefinitions.map { ($0.id, $0) }
        )
        let receiptTaskIDs = clearRecoveryTaskIDs.intersection(
            Set(definitionByID.keys)
        )
        let recoveryRoles = Set(
            receiptTaskIDs.compactMap { definitionByID[$0]?.role }
        )
        let reconciliationRoles = roles.union(recoveryRoles)
        guard reconciliationRoles.isEmpty == false else { return .noChanges }
        // Authorization must reject a read-only store before the catalog
        // planning above runs; the session re-checks it before taking the lock.
        try writeAuthorization.requireUserWritesAllowed()
        let creationPlan = AppleHealthTaskCatalog.plan(for: roles)
        let reconciliationPlan = AppleHealthTaskCatalog.plan(
            for: reconciliationRoles
        )
        return try StoreScopedMutationSession(
            container: container,
            writeAuthorization: writeAuthorization
        ).withFreshMutationContext { context in
            let repository = SwiftDataTaskRepository(
                context: context,
                deviceID: deviceID ?? DeviceIdentity.current
            )
            var state = try PersistenceState(context: context)
            var outcome = AppleHealthTaskCatalogMutationOutcome.noChanges
            let activeReceiptTaskIDs = Set(
                receiptTaskIDs.filter { taskID in
                    guard let task = state.tasksByID[taskID] else {
                        return false
                    }
                    return task.deletedAt == nil
                }
            )
            let confirmedReceiptTaskIDs = Set(
                receiptTaskIDs.filter { taskID in
                    state.tasksByID[taskID]?.deletedAt != nil
                }
            )
            // Fixed catalog tombstones can arrive from another device or an
            // older app build, where this device cannot possess the local
            // Clear All receipt. Unlike a staged missing row, an observed
            // tombstone is sufficient proof that this deterministic
            // navigation metadata needs a newer active replacement.
            let tombstonedTaskIDs = Set(
                reconciliationPlan.tasks.compactMap { definition in
                    state.tasksByID[definition.id]?.deletedAt != nil
                        ? definition.id
                        : nil
                }
            )
            let restorableTaskIDs =
                confirmedReceiptTaskIDs.union(tombstonedTaskIDs)
            let restorableCategoryIDs = Set(
                reconciliationPlan.tasks.compactMap { definition in
                    restorableTaskIDs.contains(definition.id)
                        ? definition.categoryID
                        : nil
                }
            ).union(
                reconciliationPlan.categories.compactMap { definition in
                    state.categoriesByID[definition.id]?.deletedAt != nil
                        ? definition.id
                        : nil
                }
            )
            let creatableCategoryIDs =
                Set(creationPlan.categories.map(\.id))
                    .union(restorableCategoryIDs)
            // A receipt whose task row has not arrived yet stays pending. A
            // seed-timestamp replacement could otherwise lose to the delayed
            // Clear All tombstone and consume the only recovery authority.
            let creatableTaskIDs =
                Set(creationPlan.tasks.map(\.id))
                    .subtracting(receiptTaskIDs)
            for taskID in activeReceiptTaskIDs {
                outcome = outcome.consumingClearRecoveryTask(taskID)
            }

            try createOrRestoreCategories(
                reconciliationPlan.categories,
                creatableIDs: creatableCategoryIDs,
                recoverableIDs: restorableCategoryIDs,
                state: &state,
                repository: repository,
                now: now,
                outcome: &outcome
            )
            try createOrRestoreTasks(
                reconciliationPlan.tasks,
                creatableIDs: creatableTaskIDs,
                recoverableIDs: restorableTaskIDs,
                receiptIDs: receiptTaskIDs,
                state: &state,
                repository: repository,
                now: now,
                outcome: &outcome
            )
            return outcome
        }
    }
}

private extension StoreScopedAppleHealthTaskCatalogCommandCoordinator {
    struct PersistenceState {
        var categoriesByID: [UUID: TaskCategory]
        var categoryRowsByID: [UUID: [TaskCategory]]
        var tasksByID: [UUID: TaskNode]
        var taskRowsByID: [UUID: [TaskNode]]
        var assignmentsByID: [UUID: TaskCategoryAssignment]
        let assignmentRows: [TaskCategoryAssignment]
        let claimedTaskIDs: Set<UUID>

        init(context: ModelContext) throws {
            let categories = try context.fetch(FetchDescriptor<TaskCategory>())
            let tasks = try context.fetch(FetchDescriptor<TaskNode>())
            let assignments = try context.fetch(
                FetchDescriptor<TaskCategoryAssignment>()
            )
            categoriesByID = categories.latestByID()
            categoryRowsByID = Dictionary(grouping: categories, by: \.id)
            tasksByID = tasks.latestByID()
            taskRowsByID = Dictionary(grouping: tasks, by: \.id)
            assignmentsByID = assignments.latestByID()
            assignmentRows = assignments
            claimedTaskIDs = Set(tasks.map(\.id))
                .union(assignments.map(\.taskID))
        }
    }

    func createOrRestoreCategories(
        _ definitions: [AppleHealthTaskCategoryDefinition],
        creatableIDs: Set<UUID>,
        recoverableIDs: Set<UUID>,
        state: inout PersistenceState,
        repository: SwiftDataTaskRepository,
        now: Date,
        outcome: inout AppleHealthTaskCatalogMutationOutcome
    ) throws {
        for definition in definitions {
            if let category = state.categoriesByID[definition.id] {
                guard recoverableIDs.contains(definition.id),
                      category.deletedAt != nil
                else {
                    continue
                }
                try repository.resetAppleHealthCategoryAfterClear(
                    category,
                    to: definition,
                    observedDates: state.categoryRowsByID[definition.id, default: []]
                        .map(\.updatedAt),
                    now: now
                )
                outcome = outcome.appendingRestoredCategory(definition.id)
                try didReachCheckpoint(.categoryRestored(definition.id))
                continue
            }

            guard creatableIDs.contains(definition.id) else { continue }
            try repository.createAppleHealthCategory(definition)
            outcome = outcome.appendingCreatedCategory(definition.id)
            try didReachCheckpoint(.categoryCreated(definition.id))
        }
    }

    func createOrRestoreTasks(
        _ definitions: [AppleHealthTaskDefinition],
        creatableIDs: Set<UUID>,
        recoverableIDs: Set<UUID>,
        receiptIDs: Set<UUID>,
        state: inout PersistenceState,
        repository: SwiftDataTaskRepository,
        now: Date,
        outcome: inout AppleHealthTaskCatalogMutationOutcome
    ) throws {
        for definition in definitions {
            guard categoryIsAvailable(definition.categoryID, state: state) ||
                outcome.createdCategoryIDs.contains(definition.categoryID) ||
                outcome.restoredCategoryIDs.contains(definition.categoryID)
            else {
                continue
            }

            if let task = state.tasksByID[definition.id] {
                guard task.deletedAt != nil else {
                    try repairActiveTaskPlacementAndAssignment(
                        task,
                        to: definition,
                        state: state,
                        repository: repository,
                        now: now,
                        outcome: &outcome
                    )
                    continue
                }
                guard recoverableIDs.contains(definition.id) else {
                    continue
                }
                try repository.resetAppleHealthTaskAfterClear(
                    task,
                    to: definition,
                    observedDates: state.taskRowsByID[definition.id, default: []]
                        .map(\.updatedAt),
                    now: now
                )
                outcome = outcome.appendingRestoredTask(definition.id)
                try didReachCheckpoint(.taskRestored(definition.id))
                try repairAssignment(
                    definition,
                    state: state,
                    repository: repository,
                    now: now,
                    outcome: &outcome
                )
                if receiptIDs.contains(definition.id) {
                    outcome = outcome.consumingClearRecoveryTask(
                        definition.id
                    )
                }
                continue
            }

            guard creatableIDs.contains(definition.id) else { continue }
            guard state.claimedTaskIDs.contains(definition.id) == false,
                  state.assignmentsByID[definition.categoryAssignmentID] == nil
            else {
                continue
            }
            try repository.createAppleHealthTask(definition)
            outcome = outcome.appendingCreatedTask(definition.id)
            try didReachCheckpoint(.taskCreated(definition.id))
            if receiptIDs.contains(definition.id) {
                outcome = outcome.consumingClearRecoveryTask(
                    definition.id
                )
            }
        }
    }

    func repairActiveTaskPlacementAndAssignment(
        _ task: TaskNode,
        to definition: AppleHealthTaskDefinition,
        state: PersistenceState,
        repository: SwiftDataTaskRepository,
        now: Date,
        outcome: inout AppleHealthTaskCatalogMutationOutcome
    ) throws {
        let didRepairPlacement = try repository.repairAppleHealthTaskPlacement(
            task,
            to: definition,
            visibleTasks: state.tasksByID.values.filter { $0.deletedAt == nil },
            observedDates: state.taskRowsByID[definition.id, default: []]
                .map(\.updatedAt),
            now: now
        )
        if didRepairPlacement {
            outcome = outcome.appendingRestoredTask(definition.id)
            try didReachCheckpoint(.taskRestored(definition.id))
        }

        guard assignmentNeedsRepair(definition, state: state) else { return }
        try repairAssignment(
            definition,
            state: state,
            repository: repository,
            now: now,
            outcome: &outcome
        )
    }

    func assignmentNeedsRepair(
        _ definition: AppleHealthTaskDefinition,
        state: PersistenceState
    ) -> Bool {
        guard let canonical =
            state.assignmentsByID[definition.categoryAssignmentID],
            canonical.deletedAt == nil,
            canonical.taskID == definition.id,
            canonical.categoryID == definition.categoryID
        else {
            return true
        }

        let relevantRows = assignmentRows(for: definition, state: state)
        let activeRows = relevantRows.filter { $0.deletedAt == nil }
        let logicalWinner = state.assignmentRows
            .filter { $0.taskID == definition.id }
            .logicalWinnersByTaskID()[definition.id]
        guard activeRows.count == 1,
              activeRows[0].persistentModelID == canonical.persistentModelID,
              logicalWinner?.persistentModelID ==
              canonical.persistentModelID
        else {
            return true
        }
        return false
    }

    func repairAssignment(
        _ definition: AppleHealthTaskDefinition,
        state: PersistenceState,
        repository: SwiftDataTaskRepository,
        now: Date,
        outcome: inout AppleHealthTaskCatalogMutationOutcome
    ) throws {
        let assignment =
            state.assignmentsByID[definition.categoryAssignmentID]
        try repository.repairAppleHealthAssignment(
            assignment,
            competingAssignments: assignmentRows(
                for: definition,
                state: state
            ),
            to: definition,
            now: now
        )
        outcome = outcome.appendingRestoredAssignment(
            definition.categoryAssignmentID
        )
        try didReachCheckpoint(
            .assignmentRestored(definition.categoryAssignmentID)
        )
    }

    func assignmentRows(
        for definition: AppleHealthTaskDefinition,
        state: PersistenceState
    ) -> [TaskCategoryAssignment] {
        state.assignmentRows.filter { assignment in
            assignment.taskID == definition.id ||
                assignment.id == definition.categoryAssignmentID
        }
    }

    func categoryIsAvailable(
        _ id: UUID,
        state: PersistenceState
    ) -> Bool {
        state.categoriesByID[id]?.deletedAt == nil
    }
}
