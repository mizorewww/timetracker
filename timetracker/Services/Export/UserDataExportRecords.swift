import Foundation

nonisolated protocol UserDataRecord: Sendable {
    var id: UUID { get }
}

nonisolated extension Array where Element: UserDataRecord {
    func sortedByID() -> [Element] {
        sorted { $0.id < $1.id }
    }
}

nonisolated struct TaskRecord: Codable, Equatable, UserDataRecord {
    let id: UUID
    let title: String
    let kindRaw: String
    let parentID: UUID?
    let sortOrder: Double
    let path: String
    let depth: Int
    let statusRaw: String
    let colorHex: String?
    let iconName: String?
    let estimatedSeconds: Int?
    let dueAt: Date?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let archivedAt: Date?
    let deletedAt: Date?

    init(_ model: TaskNode) {
        id = model.id
        title = model.title
        kindRaw = model.kindRaw
        parentID = model.parentID
        sortOrder = model.sortOrder
        path = model.path
        depth = model.depth
        statusRaw = model.statusRaw
        colorHex = model.colorHex
        iconName = model.iconName
        estimatedSeconds = model.estimatedSeconds
        dueAt = model.dueAt
        notes = model.notes
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        archivedAt = model.archivedAt
        deletedAt = model.deletedAt
    }
}

nonisolated struct TaskCategoryRecord: Codable, Equatable, UserDataRecord {
    let id: UUID
    let title: String
    let colorHex: String?
    let iconName: String?
    let includesInForecast: Bool
    let sortOrder: Double
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: TaskCategory) {
        id = model.id
        title = model.title
        colorHex = model.colorHex
        iconName = model.iconName
        includesInForecast = model.includesInForecast
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

nonisolated struct TaskCategoryAssignmentRecord:
    Codable,
    Equatable,
    UserDataRecord
{
    let id: UUID
    let taskID: UUID
    let categoryID: UUID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: TaskCategoryAssignment) {
        id = model.id
        taskID = model.taskID
        categoryID = model.categoryID
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}
