import Foundation
import SwiftData

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

    init(
        title: String,
        isCompleted: Bool = false,
        sortOrder: Double = 0,
        deviceID: String
    ) {
        self.id = UUID()
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.completedAt = isCompleted ? Date() : nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deviceID = deviceID
        self.clientMutationID = UUID()
    }
}
