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
        let recoverableTaskIDs = clearRecoveryTaskIDs.intersection(
            Set(definitionByID.keys)
        )
        let recoveryRoles = Set(
            recoverableTaskIDs.compactMap { definitionByID[$0]?.role }
        )
        let reconciliationRoles = roles.union(recoveryRoles)
        guard reconciliationRoles.isEmpty == false else { return .noChanges }
        try writeAuthorization.requireUserWritesAllowed()
        let creationPlan = AppleHealthTaskCatalog.plan(for: roles)
        let reconciliationPlan = AppleHealthTaskCatalog.plan(
            for: reconciliationRoles
        )
        let transaction = StoreScopedTimerMutationTransaction(
            scope: try TimerStoreScope(container: container),
            container: container
        )

        return try transaction.withFreshContext { context in
            let repository = SwiftDataTaskRepository(
                context: context,
                deviceID: deviceID ?? DeviceIdentity.current
            )
            var state = try PersistenceState(context: context)
            var outcome = AppleHealthTaskCatalogMutationOutcome.noChanges
            let activeRecoveryTaskIDs = Set(
                recoverableTaskIDs.filter { taskID in
                    guard let task = state.tasksByID[taskID] else {
                        return false
                    }
                    return task.deletedAt == nil
                }
            )
            let confirmedRecoveryTaskIDs = Set(
                recoverableTaskIDs.filter { taskID in
                    state.tasksByID[taskID]?.deletedAt != nil
                }
            )
            let confirmedRecoveryCategoryIDs = Set(
                reconciliationPlan.tasks.compactMap { definition in
                    confirmedRecoveryTaskIDs.contains(definition.id)
                        ? definition.categoryID
                        : nil
                }
            )
            let creatableCategoryIDs =
                Set(creationPlan.categories.map(\.id))
                    .union(confirmedRecoveryCategoryIDs)
            // A receipt whose task row has not arrived yet stays pending. A
            // seed-timestamp replacement could otherwise lose to the delayed
            // Clear All tombstone and consume the only recovery authority.
            let creatableTaskIDs =
                Set(creationPlan.tasks.map(\.id))
                    .subtracting(recoverableTaskIDs)
            for taskID in activeRecoveryTaskIDs {
                outcome = outcome.consumingClearRecoveryTask(taskID)
            }

            try createOrRestoreCategories(
                reconciliationPlan.categories,
                creatableIDs: creatableCategoryIDs,
                recoverableIDs: confirmedRecoveryCategoryIDs,
                state: &state,
                repository: repository,
                now: now,
                outcome: &outcome
            )
            try createOrRestoreTasks(
                reconciliationPlan.tasks,
                creatableIDs: creatableTaskIDs,
                recoverableIDs: confirmedRecoveryTaskIDs,
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
        let assignmentRowsByID: [UUID: [TaskCategoryAssignment]]
        let assignmentRowsByTaskID: [UUID: [TaskCategoryAssignment]]
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
            assignmentRowsByID = Dictionary(grouping: assignments, by: \.id)
            assignmentRowsByTaskID = Dictionary(
                grouping: assignments,
                by: \.taskID
            )
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
                      category.deletedAt != nil else {
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
        state: inout PersistenceState,
        repository: SwiftDataTaskRepository,
        now: Date,
        outcome: inout AppleHealthTaskCatalogMutationOutcome
    ) throws {
        for definition in definitions {
            guard categoryIsAvailable(definition.categoryID, state: state) ||
                    outcome.createdCategoryIDs.contains(definition.categoryID) ||
                    outcome.restoredCategoryIDs.contains(definition.categoryID) else {
                continue
            }

            if let task = state.tasksByID[definition.id] {
                guard recoverableIDs.contains(definition.id) else {
                    continue
                }
                guard task.deletedAt != nil else {
                    outcome = outcome.consumingClearRecoveryTask(
                        definition.id
                    )
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
                try resetAssignmentAfterClear(
                    definition,
                    state: state,
                    repository: repository,
                    now: now,
                    outcome: &outcome
                )
                outcome = outcome.consumingClearRecoveryTask(
                    definition.id
                )
                continue
            }

            guard creatableIDs.contains(definition.id) else { continue }
            guard state.claimedTaskIDs.contains(definition.id) == false,
                  state.assignmentsByID[definition.categoryAssignmentID] == nil else {
                continue
            }
            try repository.createAppleHealthTask(definition)
            outcome = outcome.appendingCreatedTask(definition.id)
            try didReachCheckpoint(.taskCreated(definition.id))
            if recoverableIDs.contains(definition.id) {
                outcome = outcome.consumingClearRecoveryTask(
                    definition.id
                )
            }
        }
    }

    func resetAssignmentAfterClear(
        _ definition: AppleHealthTaskDefinition,
        state: PersistenceState,
        repository: SwiftDataTaskRepository,
        now: Date,
        outcome: inout AppleHealthTaskCatalogMutationOutcome
    ) throws {
        let assignment =
            state.assignmentsByID[definition.categoryAssignmentID]
        try repository.resetAppleHealthAssignmentAfterClear(
            assignment,
            competingAssignments:
                state.assignmentRowsByTaskID[
                    definition.id,
                    default: []
                ] + state.assignmentRowsByID[
                    definition.categoryAssignmentID,
                    default: []
                ],
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

    func categoryIsAvailable(
        _ id: UUID,
        state: PersistenceState
    ) -> Bool {
        state.categoriesByID[id]?.deletedAt == nil
    }
}
