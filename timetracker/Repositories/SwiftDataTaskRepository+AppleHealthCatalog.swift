import Foundation
import SwiftData

extension SwiftDataTaskRepository {
    /// This seed path must run inside a store-scoped atomic transaction. It
    /// delegates validation and relationship creation to the ordinary
    /// repository, then makes only the generated identities and initial
    /// conflict metadata deterministic.
    func createAppleHealthCategory(
        _ definition: AppleHealthTaskCategoryDefinition
    ) throws {
        let category = try createCategory(
            proposedID: definition.id,
            title: AppStrings.localized(definition.titleLocalizationKey),
            colorHex: definition.colorHex,
            iconName: definition.iconName,
            includesInForecast: false
        )
        applyAppleHealthSeedMetadata(
            to: category,
            id: definition.id,
            sortOrder: definition.sortOrder
        )
    }

    /// Like category seeding, this must remain within the coordinator's atomic
    /// transaction so the task and its deterministic assignment commit once.
    func createAppleHealthTask(
        _ definition: AppleHealthTaskDefinition
    ) throws {
        let task = try createTask(
            proposedID: definition.id,
            title: AppStrings.localized(definition.titleLocalizationKey),
            parentID: nil,
            categoryID: definition.categoryID,
            colorHex: definition.colorHex,
            iconName: definition.iconName
        )
        applyAppleHealthSeedMetadata(
            to: task,
            id: definition.id,
            sortOrder: definition.sortOrder
        )

        let assignments = try context.fetch(
            FetchDescriptor<TaskCategoryAssignment>()
        )
        guard let assignment = assignments.first(where: {
            $0.taskID == definition.id &&
                $0.categoryID == definition.categoryID &&
                $0.deletedAt == nil
        }) else {
            throw AppleHealthTaskCatalogMutationError
                .generatedAssignmentUnavailable
        }
        assignment.id = definition.categoryAssignmentID
        applyAppleHealthSeedMetadata(
            to: assignment,
            id: definition.categoryAssignmentID
        )
    }

    func resetAppleHealthCategoryAfterClear(
        _ category: TaskCategory,
        to definition: AppleHealthTaskCategoryDefinition,
        observedDates: [Date],
        now: Date
    ) throws {
        let values = try TaskPersistencePolicy.prepareCategory(
            title: AppStrings.localized(definition.titleLocalizationKey),
            colorHex: definition.colorHex,
            iconName: definition.iconName
        )
        category.title = values.title
        category.colorHex = values.colorHex
        category.iconName = values.iconName
        category.includesInForecast = false
        category.sortOrder = definition.sortOrder
        try applyAppleHealthClearRecoveryMetadata(
            category,
            observedDates: observedDates,
            now: now
        )
    }

    func resetAppleHealthTaskAfterClear(
        _ task: TaskNode,
        to definition: AppleHealthTaskDefinition,
        observedDates: [Date],
        now: Date
    ) throws {
        let values = try TaskPersistencePolicy.prepareTask(
            title: AppStrings.localized(definition.titleLocalizationKey),
            colorHex: definition.colorHex,
            iconName: definition.iconName,
            notes: nil
        )
        task.title = values.title
        task.kindRaw = "task"
        task.parentID = nil
        task.sortOrder = definition.sortOrder
        task.path = TaskHierarchyMetadata.canonicalPath(for: task.id)
        task.depth = 0
        task.statusRaw = LegacyTaskStatusRaw.active
        task.colorHex = values.colorHex
        task.iconName = values.iconName
        task.estimatedSeconds = nil
        task.dueAt = nil
        task.notes = nil
        task.archivedAt = nil
        try applyAppleHealthClearRecoveryMetadata(
            task,
            observedDates: observedDates,
            now: now
        )
    }

    @discardableResult
    func resetAppleHealthAssignmentAfterClear(
        _ assignment: TaskCategoryAssignment?,
        competingAssignments: [TaskCategoryAssignment],
        to definition: AppleHealthTaskDefinition,
        now: Date
    ) throws -> TaskCategoryAssignment {
        let assignment = assignment ?? {
            let created = TaskCategoryAssignment(
                taskID: definition.id,
                categoryID: definition.categoryID,
                deviceID: deviceID
            )
            created.id = definition.categoryAssignmentID
            created.createdAt = AppleHealthTaskCatalog.seedTimestamp
            context.insert(created)
            return created
        }()
        var seenPersistentIDs = Set<PersistentIdentifier>()
        let competitors = competingAssignments.filter { candidate in
            guard candidate !== assignment,
                  seenPersistentIDs.insert(
                    candidate.persistentModelID
                  ).inserted else {
                return false
            }
            return true
        }
        let observedDates =
            competitors.map(\.updatedAt) + [assignment.updatedAt]
        let competingTombstoneDate =
            PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: observedDates
            )
        var didTombstoneCompetitor = false
        for competitor in competitors where competitor.deletedAt == nil {
            competitor.deletedAt = competingTombstoneDate
            competitor.updatedAt = competingTombstoneDate
            competitor.deviceID = deviceID
            competitor.clientMutationID = UUID()
            didTombstoneCompetitor = true
        }
        assignment.taskID = definition.id
        assignment.categoryID = definition.categoryID
        assignment.deletedAt = nil
        assignment.updatedAt =
            PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: observedDates +
                    (didTombstoneCompetitor
                        ? [competingTombstoneDate]
                        : [])
            )
        assignment.deviceID = deviceID
        assignment.clientMutationID = UUID()
        try context.saveAfterMutationStep()
        return assignment
    }

    private func applyAppleHealthSeedMetadata(
        to model: TaskCategory,
        id: UUID,
        sortOrder: Double
    ) {
        model.createdAt = AppleHealthTaskCatalog.seedTimestamp
        model.updatedAt = AppleHealthTaskCatalog.seedTimestamp
        model.sortOrder = sortOrder
        model.deviceID = deviceID
        model.clientMutationID = id
    }

    private func applyAppleHealthSeedMetadata(
        to model: TaskNode,
        id: UUID,
        sortOrder: Double
    ) {
        model.createdAt = AppleHealthTaskCatalog.seedTimestamp
        model.updatedAt = AppleHealthTaskCatalog.seedTimestamp
        model.sortOrder = sortOrder
        model.deviceID = deviceID
        model.clientMutationID = id
    }

    private func applyAppleHealthSeedMetadata(
        to model: TaskCategoryAssignment,
        id: UUID
    ) {
        model.createdAt = AppleHealthTaskCatalog.seedTimestamp
        model.updatedAt = AppleHealthTaskCatalog.seedTimestamp
        model.deviceID = deviceID
        model.clientMutationID = id
    }

    private func applyAppleHealthClearRecoveryMetadata<Model>(
        _ model: Model,
        observedDates: [Date],
        now: Date
    ) throws where Model: SoftDeletablePersistentUUIDModel &
        ClientMutationTrackedModel {
        model.deletedAt = nil
        model.updatedAt = PersistentLWWMutationDate.strictlyDominating(
            preferred: now,
            observed: observedDates
        )
        model.deviceID = deviceID
        model.clientMutationID = UUID()
        try context.saveAfterMutationStep()
    }
}
