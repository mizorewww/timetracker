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

nonisolated extension Sequence<ChecklistItemVisual> {
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
