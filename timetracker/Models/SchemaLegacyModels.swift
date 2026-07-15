import Foundation
import SwiftData

extension TimeTrackerSchemaV4 {
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
            categoryID: UUID? = nil,
            colorHex: String? = nil,
            iconName: String? = nil,
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
}

extension TimeTrackerSchemaV7 {
    @Model
    final class ChecklistItemVisual {
        var id: UUID = UUID()
        var checklistItemID: UUID = UUID()
        var iconName: String = "checkmark.circle"
        var colorHex: String = "1677FF"
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?
        var deviceID: String = ""
        var clientMutationID: UUID = UUID()

        init(
            checklistItemID: UUID,
            iconName: String = "checkmark.circle",
            colorHex: String = "1677FF",
            deviceID: String
        ) {
            self.id = UUID()
            self.checklistItemID = checklistItemID
            self.iconName = iconName
            self.colorHex = colorHex
            self.createdAt = Date()
            self.updatedAt = Date()
            self.deviceID = deviceID
            self.clientMutationID = UUID()
        }
    }
}

extension TimeTrackerSchemaV9 {
    @Model
    final class InboxItem {
        var id: UUID = UUID()
        var title: String = ""
        var notes: String?
        var isCompleted: Bool = false
        var sortOrder: Double = 0
        var completedAt: Date?
        var suggestedTaskID: UUID?
        var suggestionReason: String?
        var suggestionGeneratedAt: Date?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?
        var deviceID: String = ""
        var clientMutationID: UUID = UUID()

        init(title: String, deviceID: String) {
            self.id = UUID()
            self.title = title
            self.createdAt = Date()
            self.updatedAt = Date()
            self.deviceID = deviceID
            self.clientMutationID = UUID()
        }
    }

    @Model
    final class InboxSuggestion {
        var id: UUID = UUID()
        var inboxItemID: UUID = UUID()
        var taskID: UUID = UUID()
        var reason: String?
        var iconName: String = "checkmark.circle"
        var colorHex: String = "1677FF"
        var modelID: String?
        var titleSnapshot: String = ""
        var generatedAt: Date = Date()
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?
        var deviceID: String = ""
        var clientMutationID: UUID = UUID()

        init(inboxItemID: UUID, taskID: UUID, titleSnapshot: String, deviceID: String) {
            self.id = UUID()
            self.inboxItemID = inboxItemID
            self.taskID = taskID
            self.titleSnapshot = titleSnapshot
            self.generatedAt = Date()
            self.createdAt = Date()
            self.updatedAt = Date()
            self.deviceID = deviceID
            self.clientMutationID = UUID()
        }
    }
}
