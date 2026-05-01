import Foundation
import SwiftData

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

    init(
        inboxItemID: UUID,
        taskID: UUID,
        reason: String? = nil,
        iconName: String = "checkmark.circle",
        colorHex: String = "1677FF",
        modelID: String? = nil,
        titleSnapshot: String,
        generatedAt: Date = Date(),
        deviceID: String
    ) {
        self.id = UUID()
        self.inboxItemID = inboxItemID
        self.taskID = taskID
        self.reason = reason
        self.iconName = iconName
        self.colorHex = colorHex
        self.modelID = modelID
        self.titleSnapshot = titleSnapshot
        self.generatedAt = generatedAt
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deviceID = deviceID
        self.clientMutationID = UUID()
    }
}
