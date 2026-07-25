import Foundation
import SwiftData

extension TimeTrackerSchemaV10 {
    /// Frozen V10/V11 shape. Do not add current InboxSuggestion fields here.
    @Model
    final class InboxSuggestion {
        var id: UUID = UUID()
        var inboxItemID: UUID = UUID()
        var inboxItemContextID: UUID?
        var inboxItemRevisionID: UUID?
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
            inboxItemContextID: UUID? = nil,
            inboxItemRevisionID: UUID? = nil,
            taskID: UUID,
            reason: String? = nil,
            iconName: String = "checkmark.circle",
            colorHex: String = "1677FF",
            modelID: String? = nil,
            titleSnapshot: String,
            generatedAt: Date = Date(),
            deviceID: String
        ) {
            id = UUID()
            self.inboxItemID = inboxItemID
            self.inboxItemContextID = inboxItemContextID
            self.inboxItemRevisionID = inboxItemRevisionID
            self.taskID = taskID
            self.reason = reason
            self.iconName = iconName
            self.colorHex = colorHex
            self.modelID = modelID
            self.titleSnapshot = titleSnapshot
            self.generatedAt = generatedAt
            createdAt = Date()
            updatedAt = Date()
            self.deviceID = deviceID
            clientMutationID = UUID()
        }
    }
}

extension TimeTrackerSchemaV11 {
    /// V11 added InboxCaptureReceipt but retained the exact V10 suggestion shape.
    typealias InboxSuggestion = TimeTrackerSchemaV10.InboxSuggestion
}
