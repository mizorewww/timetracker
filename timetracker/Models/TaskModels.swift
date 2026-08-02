import Foundation
import SwiftData

/// Raw values persisted since schema V4. This is a deprecated archive
/// compatibility contract, not a product-facing task state model. Existing
/// stores, CloudKit records, and backup snapshots must continue to round-trip
/// all four values without giving planned/active/completed any behavior.
nonisolated enum LegacyTaskStatusRaw {
    static let active = "active"
    static let planned = "planned"
    static let completed = "completed"
    static let archived = "archived"

    static let acceptedValues: Set<String> = [
        active,
        planned,
        completed,
        archived,
    ]
}

@Model
final class TaskNode {
    var id: UUID = UUID()
    var title: String = ""
    var kindRaw: String = "task"
    var parentID: UUID?
    var sortOrder: Double = 0
    var path: String = ""
    var depth: Int = 0
    /// Deprecated persistence compatibility. New product behavior only
    /// interprets the legacy archived value.
    var statusRaw: String = LegacyTaskStatusRaw.active
    var colorHex: String?
    var iconName: String?
    var estimatedSeconds: Int?
    var dueAt: Date?
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var archivedAt: Date?
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(
        title: String,
        parentID: UUID?,
        deviceID: String,
        colorHex: String? = nil,
        iconName: String? = nil,
        sortOrder: Double = 0
    ) {
        id = UUID()
        self.title = title
        self.parentID = parentID
        self.sortOrder = sortOrder
        path = ""
        depth = 0
        statusRaw = LegacyTaskStatusRaw.active
        self.colorHex = colorHex
        self.iconName = iconName
        createdAt = Date()
        updatedAt = Date()
        self.deviceID = deviceID
        clientMutationID = UUID()
    }
}

@Model
final class TaskCategory {
    var id: UUID = UUID()
    var title: String = ""
    var colorHex: String?
    var iconName: String?
    var includesInForecast: Bool = true
    var sortOrder: Double = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(
        title: String,
        deviceID: String,
        colorHex: String? = nil,
        iconName: String? = nil,
        includesInForecast: Bool = true,
        sortOrder: Double = 0
    ) {
        id = UUID()
        self.title = title
        self.colorHex = colorHex
        self.iconName = iconName
        self.includesInForecast = includesInForecast
        self.sortOrder = sortOrder
        createdAt = Date()
        updatedAt = Date()
        self.deviceID = deviceID
        clientMutationID = UUID()
    }
}

@Model
final class TaskCategoryAssignment {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var categoryID: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(taskID: UUID, categoryID: UUID, deviceID: String) {
        id = UUID()
        self.taskID = taskID
        self.categoryID = categoryID
        createdAt = Date()
        updatedAt = Date()
        self.deviceID = deviceID
        clientMutationID = UUID()
    }
}

extension TaskCategoryAssignment {
    /// Defines one deterministic last-write-wins order for the logical
    /// "root task has category" key. Assignment rows have independent UUIDs,
    /// so normal model-ID deduplication alone cannot resolve concurrent writes.
    func isPreferredLogicalWinner(over other: TaskCategoryAssignment) -> Bool {
        if updatedAt != other.updatedAt {
            return updatedAt > other.updatedAt
        }
        if (deletedAt == nil) != (other.deletedAt == nil) {
            return deletedAt != nil
        }
        if createdAt != other.createdAt {
            return createdAt > other.createdAt
        }
        if deviceID != other.deviceID {
            return deviceID > other.deviceID
        }
        if clientMutationID != other.clientMutationID {
            return clientMutationID.uuidString > other.clientMutationID.uuidString
        }
        return id.uuidString > other.id.uuidString
    }
}

nonisolated extension Sequence<TaskCategoryAssignment> {
    func logicalWinnersByTaskID() -> [UUID: TaskCategoryAssignment] {
        reduce(into: [:]) { winners, assignment in
            guard let current = winners[assignment.taskID] else {
                winners[assignment.taskID] = assignment
                return
            }
            if assignment.isPreferredLogicalWinner(over: current) {
                winners[assignment.taskID] = assignment
            }
        }
    }
}

extension TaskNode {
    var isArchivedForLifecycle: Bool {
        archivedAt != nil || statusRaw == LegacyTaskStatusRaw.archived
    }
}
