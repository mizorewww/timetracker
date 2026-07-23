import Foundation
import SwiftData

extension SwiftDataTaskRepository {
    func categories() throws -> [TaskCategory] {
        try context.fetch(FetchDescriptor<TaskCategory>())
            .visibleDeduplicatedByID()
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func categoryAssignments() throws -> [TaskCategoryAssignment] {
        try context.fetch(FetchDescriptor<TaskCategoryAssignment>())
            .visibleDeduplicatedByID()
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func category(id: UUID) throws -> TaskCategory? {
        let categoryID = id
        let descriptor = FetchDescriptor<TaskCategory>(predicate: #Predicate { $0.id == categoryID })
        return try context.fetch(descriptor).visibleDeduplicatedByID().first
    }

    func categoryID(forRootTaskID taskID: UUID) throws -> UUID? {
        try activeCategoryAssignments(forRootTaskID: taskID).first?.categoryID
    }

    @discardableResult
    func createCategory(
        title: String,
        colorHex: String? = nil,
        iconName: String? = nil,
        includesInForecast: Bool = true
    ) throws -> TaskCategory {
        try createCategory(
            proposedID: UUID(),
            title: title,
            colorHex: colorHex,
            iconName: iconName,
            includesInForecast: includesInForecast
        )
    }

    /// Creates a category with an identity chosen by an enclosing idempotent
    /// command. The protocol entry point intentionally keeps its existing
    /// repository-owned identity behavior.
    @discardableResult
    func createCategory(
        proposedID: UUID,
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
            sortOrder: (existing.last?.sortOrder ?? 0) + 10
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
        category.updatedAt = Date()
        category.deviceID = deviceID
        category.clientMutationID = UUID()
        try context.saveAfterMutationStep()
    }

    func softDeleteCategory(categoryID: UUID) throws {
        guard let category = try category(id: categoryID) else {
            throw TaskRepositoryError.categoryUnavailable
        }
        try validateAppleHealthCategoryDeletion(categoryID: categoryID)
        let now = Date()
        category.deletedAt = now
        category.updatedAt = now
        category.deviceID = deviceID
        category.clientMutationID = UUID()

        for assignment in try categoryAssignments() where assignment.categoryID == categoryID {
            assignment.deletedAt = now
            assignment.updatedAt = now
            assignment.deviceID = deviceID
            assignment.clientMutationID = UUID()
        }
        try context.saveAfterMutationStep()
    }

    func setCategoryAssignment(categoryID: UUID?, forRootTaskID taskID: UUID) throws {
        try validateAppleHealthCategoryAssignment(categoryID: categoryID, taskID: taskID)
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
            winner.updatedAt = now
            winner.deviceID = deviceID
            winner.clientMutationID = UUID()
            for duplicate in existing.dropFirst() {
                markCategoryAssignmentDeleted(duplicate, now: now)
            }
        } else {
            context.insert(TaskCategoryAssignment(taskID: taskID, categoryID: categoryID, deviceID: deviceID))
        }
    }

    private func activeCategoryAssignments(forRootTaskID taskID: UUID) throws -> [TaskCategoryAssignment] {
        let rootTaskID = taskID
        let descriptor = FetchDescriptor<TaskCategoryAssignment>(
            predicate: #Predicate { $0.taskID == rootTaskID }
        )
        return try context.fetch(descriptor)
            .visibleDeduplicatedByID()
            .sorted { $0.isPreferredLogicalWinner(over: $1) }
    }

    private func markCategoryAssignmentDeleted(_ assignment: TaskCategoryAssignment, now: Date) {
        assignment.deletedAt = now
        assignment.updatedAt = now
        assignment.deviceID = deviceID
        assignment.clientMutationID = UUID()
    }
}
