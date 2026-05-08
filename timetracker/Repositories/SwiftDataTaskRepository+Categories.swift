import Foundation
import SwiftData

extension SwiftDataTaskRepository {
    func categories() throws -> [TaskCategory] {
        let descriptor = FetchDescriptor<TaskCategory>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        )
        return try context.fetch(descriptor)
    }

    func categoryAssignments() throws -> [TaskCategoryAssignment] {
        let descriptor = FetchDescriptor<TaskCategoryAssignment>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.createdAt)
            ]
        )
        return try context.fetch(descriptor)
    }

    func category(id: UUID) throws -> TaskCategory? {
        let categoryID = id
        var descriptor = FetchDescriptor<TaskCategory>(
            predicate: #Predicate { $0.id == categoryID && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func categoryID(forRootTaskID taskID: UUID) throws -> UUID? {
        try activeCategoryAssignment(forRootTaskID: taskID)?.categoryID
    }

    @discardableResult
    func createCategory(
        title: String,
        colorHex: String? = nil,
        iconName: String? = nil,
        includesInForecast: Bool = true
    ) throws -> TaskCategory {
        let existing = try categories()
        let category = TaskCategory(
            title: title,
            deviceID: deviceID,
            colorHex: colorHex,
            iconName: iconName,
            includesInForecast: includesInForecast,
            sortOrder: (existing.last?.sortOrder ?? 0) + 10
        )
        context.insert(category)
        try context.save()
        return category
    }

    func updateCategory(
        categoryID: UUID,
        title: String,
        colorHex: String?,
        iconName: String?,
        includesInForecast: Bool
    ) throws {
        guard let category = try category(id: categoryID) else { return }
        category.title = title
        category.colorHex = colorHex
        category.iconName = iconName
        category.includesInForecast = includesInForecast
        category.updatedAt = Date()
        category.clientMutationID = UUID()
        try context.save()
    }

    func softDeleteCategory(categoryID: UUID) throws {
        guard let category = try category(id: categoryID) else { return }
        let now = Date()
        category.deletedAt = now
        category.updatedAt = now
        category.clientMutationID = UUID()

        for assignment in try categoryAssignments() where assignment.categoryID == categoryID {
            assignment.deletedAt = now
            assignment.updatedAt = now
            assignment.clientMutationID = UUID()
        }
        try context.save()
    }

    func setCategoryAssignment(categoryID: UUID?, forRootTaskID taskID: UUID) throws {
        let now = Date()
        let existing = try activeCategoryAssignment(forRootTaskID: taskID)

        guard let categoryID, try category(id: categoryID) != nil else {
            if let existing {
                existing.deletedAt = now
                existing.updatedAt = now
                existing.clientMutationID = UUID()
            }
            return
        }

        if let existing {
            existing.categoryID = categoryID
            existing.updatedAt = now
            existing.clientMutationID = UUID()
        } else {
            context.insert(TaskCategoryAssignment(taskID: taskID, categoryID: categoryID, deviceID: deviceID))
        }
    }

    private func activeCategoryAssignment(forRootTaskID taskID: UUID) throws -> TaskCategoryAssignment? {
        let rootTaskID = taskID
        var descriptor = FetchDescriptor<TaskCategoryAssignment>(
            predicate: #Predicate { $0.taskID == rootTaskID && $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
