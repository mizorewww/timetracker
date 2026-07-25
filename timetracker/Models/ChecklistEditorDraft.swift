import Foundation

nonisolated struct ChecklistEditorDraft:
    Codable,
    Identifiable,
    Equatable,
    Sendable
{
    let id: UUID
    var existingID: UUID?
    var title: String
    var isCompleted: Bool
    var iconName: String
    var colorHex: String

    nonisolated init(
        title: String = "",
        isCompleted: Bool = false,
        iconName: String = "checkmark.circle",
        colorHex: String = "1677FF"
    ) {
        id = UUID()
        existingID = nil
        self.title = title
        self.isCompleted = isCompleted
        self.iconName = iconName
        self.colorHex = colorHex
    }

    nonisolated init(
        id: UUID,
        existingID: UUID?,
        title: String,
        isCompleted: Bool,
        iconName: String,
        colorHex: String
    ) {
        self.id = id
        self.existingID = existingID
        self.title = title
        self.isCompleted = isCompleted
        self.iconName = iconName
        self.colorHex = colorHex
    }

    nonisolated init(
        item: ChecklistItem,
        visual: ChecklistItemVisual? = nil
    ) {
        id = item.id
        existingID = item.id
        title = item.title
        isCompleted = item.isCompleted
        iconName = visual?.iconName ?? "checkmark.circle"
        colorHex = visual?.colorHex ?? "1677FF"
    }
}
