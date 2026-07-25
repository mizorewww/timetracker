import Foundation
import SwiftData

@Model
final class ChecklistItem {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var title: String = ""
    var isCompleted: Bool = false
    var sortOrder: Double = 0
    /// Position before the item was last marked complete, so uncompleting
    /// can restore its original place instead of appending to the group.
    var sortOrderBeforeCompletion: Double?
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
        id = UUID()
        self.taskID = taskID
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
