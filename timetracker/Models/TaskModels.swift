import Foundation
import SwiftData

enum TaskStatus: String, Codable, CaseIterable {
    case planned
    case active
    case paused
    case completed
    case archived
}

@Model
final class TaskNode {
    var id: UUID = UUID()
    var title: String = ""
    var kindRaw: String = "task"
    var parentID: UUID?
    var categoryID: UUID?
    var sortOrder: Double = 0
    var path: String = ""
    var depth: Int = 0
    var statusRaw: String = TaskStatus.active.rawValue
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
        categoryID: UUID? = nil,
        sortOrder: Double = 0
    ) {
        self.id = UUID()
        self.title = title
        self.parentID = parentID
        self.categoryID = categoryID
        self.sortOrder = sortOrder
        self.path = ""
        self.depth = 0
        self.statusRaw = TaskStatus.active.rawValue
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

extension TaskNode {
    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var isRunning: Bool {
        status == .paused ? false : false
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
        case .paused: return AppStrings.paused
        case .completed: return AppStrings.localized("status.completed")
        case .archived: return AppStrings.localized("status.archived")
        }
    }

    var exampleText: String {
        switch self {
        case .planned: return AppStrings.localized("editor.task.status.planned.example")
        case .active: return AppStrings.localized("editor.task.status.active.example")
        case .paused: return AppStrings.paused
        case .completed: return AppStrings.localized("editor.task.status.completed.example")
        case .archived: return AppStrings.localized("status.archived")
        }
    }

    var symbolName: String {
        switch self {
        case .planned: return "calendar"
        case .active: return "circle"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .archived: return "archivebox"
        }
    }

    var colorHex: String {
        switch self {
        case .planned: return "0EA5E9"
        case .active: return "64748B"
        case .paused: return "F97316"
        case .completed: return "16A34A"
        case .archived: return "64748B"
        }
    }
}
