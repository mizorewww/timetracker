import Foundation
import SwiftData

/// Raw values persisted since schema V4. Keep this namespace independent from
/// presentation semantics so legacy stores and restore preflight share one
/// compatibility contract.
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

enum TaskStatus: String, Codable, CaseIterable {
    case planned
    case active
    case completed
    case archived
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
        self.id = UUID()
        self.title = title
        self.parentID = parentID
        self.sortOrder = sortOrder
        self.path = ""
        self.depth = 0
        self.statusRaw = LegacyTaskStatusRaw.active
        self.colorHex = colorHex
        self.iconName = iconName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deviceID = deviceID
        self.clientMutationID = UUID()
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
        self.id = UUID()
        self.title = title
        self.colorHex = colorHex
        self.iconName = iconName
        self.includesInForecast = includesInForecast
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deviceID = deviceID
        self.clientMutationID = UUID()
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
        self.id = UUID()
        self.taskID = taskID
        self.categoryID = categoryID
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deviceID = deviceID
        self.clientMutationID = UUID()
    }
}

extension TaskCategoryAssignment {
    /// Defines one deterministic last-write-wins order for the logical
    /// "root task has category" key. Assignment rows have independent UUIDs,
    /// so normal model-ID deduplication alone cannot resolve concurrent writes.
    func isPreferredLogicalWinner(over other: TaskCategoryAssignment) -> Bool {
        if updatedAt != other.updatedAt { return updatedAt > other.updatedAt }
        if (deletedAt == nil) != (other.deletedAt == nil) { return deletedAt != nil }
        if createdAt != other.createdAt { return createdAt > other.createdAt }
        if deviceID != other.deviceID { return deviceID > other.deviceID }
        if clientMutationID != other.clientMutationID {
            return clientMutationID.uuidString > other.clientMutationID.uuidString
        }
        return id.uuidString > other.id.uuidString
    }
}

extension Sequence where Element == TaskCategoryAssignment {
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

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
}

extension TaskStatus {
    static var editableCases: [TaskStatus] {
        [.planned, .active, .completed]
    }

    var displayName: String {
        switch self {
        case .planned: return AppStrings.localized("status.planned")
        case .active: return AppStrings.localized("status.active")
        case .completed: return AppStrings.localized("status.completed")
        case .archived: return AppStrings.localized("status.archived")
        }
    }

    var exampleText: String {
        switch self {
        case .planned: return AppStrings.localized("editor.task.status.planned.example")
        case .active: return AppStrings.localized("editor.task.status.active.example")
        case .completed: return AppStrings.localized("editor.task.status.completed.example")
        case .archived: return AppStrings.localized("status.archived")
        }
    }

    var symbolName: String {
        switch self {
        case .planned: return "calendar"
        case .active: return "circle"
        case .completed: return "checkmark.circle.fill"
        case .archived: return "archivebox"
        }
    }

    var colorHex: String {
        switch self {
        case .planned: return "0EA5E9"
        case .active: return "64748B"
        case .completed: return "16A34A"
        case .archived: return "64748B"
        }
    }
}
