import Foundation
import SwiftData

@Model
final class InboxItem {
    var id: UUID = UUID()
    /// Stable identity for suggestion state even if persistence rebuilds this row with another `id`.
    var suggestionContextID: UUID?
    /// Changes only when the title changes, so a dismissal applies to one title revision.
    var suggestionRevisionID: UUID?
    /// A monotonic dismissal marker for the current suggestion revision.
    var dismissedSuggestionRevisionID: UUID?
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

    init(
        title: String,
        isCompleted: Bool = false,
        sortOrder: Double = 0,
        deviceID: String
    ) {
        id = UUID()
        suggestionContextID = id
        suggestionRevisionID = UUID()
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        completedAt = isCompleted ? Date() : nil
        createdAt = Date()
        updatedAt = Date()
        self.deviceID = deviceID
        clientMutationID = UUID()
    }
}
