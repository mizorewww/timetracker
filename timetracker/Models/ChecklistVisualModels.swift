import Foundation
import SwiftData

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
