import Foundation
import SwiftData

@Model
final class ChecklistItemVisual {
    var id: UUID = UUID()
    var checklistItemID: UUID = UUID()
    var iconName: String = "checkmark.circle"
    var colorHex: String = "1677FF"
    var suggestionTitleSnapshot: String?
    var suggestionModelID: String?
    var suggestionGeneratedAt: Date?
    var userEditedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(
        checklistItemID: UUID,
        iconName: String = "checkmark.circle",
        colorHex: String = "1677FF",
        suggestionTitleSnapshot: String? = nil,
        suggestionModelID: String? = nil,
        suggestionGeneratedAt: Date? = nil,
        userEditedAt: Date? = nil,
        deviceID: String
    ) {
        id = UUID()
        self.checklistItemID = checklistItemID
        self.iconName = iconName
        self.colorHex = colorHex
        self.suggestionTitleSnapshot = suggestionTitleSnapshot
        self.suggestionModelID = suggestionModelID
        self.suggestionGeneratedAt = suggestionGeneratedAt
        self.userEditedAt = userEditedAt
        createdAt = Date()
        updatedAt = Date()
        self.deviceID = deviceID
        clientMutationID = UUID()
    }
}

extension ChecklistItemVisual {
    /// Defines a deterministic LWW order for the logical "item has visual"
    /// key. CloudKit can materialize multiple physical UUIDs for one item.
    func isPreferredLogicalWinner(over other: ChecklistItemVisual) -> Bool {
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

extension Sequence<ChecklistItemVisual> {
    func logicalWinnersByChecklistItemID() -> [UUID: ChecklistItemVisual] {
        reduce(into: [:]) { winners, visual in
            guard let current = winners[visual.checklistItemID] else {
                winners[visual.checklistItemID] = visual
                return
            }
            if visual.isPreferredLogicalWinner(over: current) {
                winners[visual.checklistItemID] = visual
            }
        }
    }
}
