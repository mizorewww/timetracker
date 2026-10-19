import Foundation
import SwiftData

nonisolated extension SwiftDataTaskRepository {
    func categories() throws -> [TaskCategory] {
        try context.fetch(FetchDescriptor<TaskCategory>())
            .visibleDeduplicatedByID()
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id < rhs.id
            }
    }

    /// Every assignment row, tombstones included: several rows can name the
    /// same task, and the newest row decides its category even when it is a
    /// deletion (`logicalWinnersByTaskID()` before filtering `deletedAt`).
    func categoryAssignments() throws -> [TaskCategoryAssignment] {
        try context.fetch(FetchDescriptor<TaskCategoryAssignment>())
            .deduplicatedByID()
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id < rhs.id
            }
    }

    func category(id: UUID) throws -> TaskCategory? {
        let categoryID = id
        let descriptor = FetchDescriptor<TaskCategory>(predicate: #Predicate { $0.id == categoryID })
        return try context.fetch(descriptor).visibleDeduplicatedByID().first
    }

    func categoryID(forRootTaskID taskID: UUID) throws -> UUID? {
        let winner = try categoryAssignmentRows(forRootTaskID: taskID)
            .logicalWinnersByTaskID()[taskID]
        return winner?.deletedAt == nil ? winner?.categoryID : nil
    }

    @discardableResult
    func reorderCategories(
        orderedCategoryIDs: [UUID],
        now: Date
    ) throws -> Bool {
        let categories = try categories()
        let categoryByID = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, $0) }
        )
        guard orderedCategoryIDs.count == categories.count,
              Set(orderedCategoryIDs) == Set(categoryByID.keys)
        else {
            throw TaskRepositoryError.categoryUnavailable
        }
        guard categories.map(\.id) != orderedCategoryIDs else {
            return false
        }

        let mutationDate = PersistentLWWMutationDate.strictlyDominating(
            preferred: now,
            observed: categories.map(\.updatedAt)
        )
        // Keep the whole order mutation on one LWW revision. If two devices
        // happen to use the same persisted timestamp, a shared operation UUID
        // prevents the winning order from being selected independently by row.
        let batchMutationID = UUID()
        try context.performAtomicMutation {
            for (index, categoryID) in orderedCategoryIDs.enumerated() {
                guard let category = categoryByID[categoryID] else {
                    throw TaskRepositoryError.categoryUnavailable
                }
                category.sortOrder = SortOrderPolicy.position(index)
                category.updatedAt = mutationDate
                category.deviceID = deviceID
                category.clientMutationID = batchMutationID
            }
        }
        return true
    }

    @discardableResult
    func createCategory(
        proposedID: UUID = UUID(),
        title: String,
        colorHex: String? = nil,
        iconName: String? = nil,
        includesInForecast: Bool = true
    ) throws -> TaskCategory {
        let values = try TaskPersistencePolicy.prepareCategory(
            title: title,
            colorHex: colorHex,
            iconName: iconName
        )
        let existing = try categories()
        let category = TaskCategory(
            title: values.title,
            deviceID: deviceID,
            colorHex: values.colorHex,
            iconName: values.iconName,
            includesInForecast: includesInForecast,
            sortOrder: SortOrderPolicy.after(existing.last?.sortOrder)
        )
        category.id = proposedID
        context.insert(category)
        try context.saveAfterMutationStep()
        return category
    }

    func updateCategory(
        categoryID: UUID,
        title: String,
        colorHex: String?,
        iconName: String?,
        includesInForecast: Bool
    ) throws {
        let values = try TaskPersistencePolicy.prepareCategory(
            title: title,
            colorHex: colorHex,
            iconName: iconName
        )
        guard let category = try category(id: categoryID) else {
            throw TaskRepositoryError.categoryUnavailable
        }
        category.title = values.title
        category.colorHex = values.colorHex
        category.iconName = values.iconName
        category.includesInForecast = includesInForecast
        category.markMutated(at: Date(), deviceID: deviceID)
        try context.saveAfterMutationStep()
    }

    func softDeleteCategory(categoryID: UUID) throws {
        guard let category = try category(id: categoryID) else {
            throw TaskRepositoryError.categoryUnavailable
        }
        let now = Date()
        category.deletedAt = now
        category.markMutated(at: now, deviceID: deviceID)

        for assignment in try categoryAssignments()
            where assignment.categoryID == categoryID && assignment.deletedAt == nil
        {
            assignment.deletedAt = now
            assignment.markMutated(at: now, deviceID: deviceID)
        }
        try context.saveAfterMutationStep()
    }

    func setCategoryAssignment(categoryID: UUID?, forRootTaskID taskID: UUID) throws {
        let now = Date()
        let existing = try activeCategoryAssignments(forRootTaskID: taskID)

        guard let categoryID, try category(id: categoryID) != nil else {
            for assignment in existing {
                markCategoryAssignmentDeleted(assignment, now: now)
            }
            return
        }

        if let winner = existing.first {
            winner.categoryID = categoryID
            winner.markMutated(at: now, deviceID: deviceID)
            for duplicate in existing.dropFirst() {
                markCategoryAssignmentDeleted(duplicate, now: now)
            }
        } else {
            context.insert(TaskCategoryAssignment(taskID: taskID, categoryID: categoryID, deviceID: deviceID))
        }
    }

    private func categoryAssignmentRows(forRootTaskID taskID: UUID) throws -> [TaskCategoryAssignment] {
        let rootTaskID = taskID
        let descriptor = FetchDescriptor<TaskCategoryAssignment>(
            predicate: #Predicate { $0.taskID == rootTaskID }
        )
        return try context.fetch(descriptor).deduplicatedByID()
    }

    /// Rows still live for the task, newest first. Setting a category reuses
    /// the first and tombstones the rest so one row remains authoritative.
    private func activeCategoryAssignments(forRootTaskID taskID: UUID) throws -> [TaskCategoryAssignment] {
        try categoryAssignmentRows(forRootTaskID: taskID)
            .filter { $0.deletedAt == nil }
            .sorted { $0.isPreferredLogicalWinner(over: $1) }
    }

    private func markCategoryAssignmentDeleted(_ assignment: TaskCategoryAssignment, now: Date) {
        assignment.deletedAt = now
        assignment.markMutated(at: now, deviceID: deviceID)
    }
}
