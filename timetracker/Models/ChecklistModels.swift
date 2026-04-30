import Foundation
import SwiftData

@Model
final class ChecklistItem {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var title: String = ""
    var isCompleted: Bool = false
    var sortOrder: Double = 0
    var completedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(
        taskID: UUID,
        title: String,
        isCompleted: Bool = false,
        sortOrder: Double = 0,
        deviceID: String
    ) {
        self.id = UUID()
        self.taskID = taskID
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
