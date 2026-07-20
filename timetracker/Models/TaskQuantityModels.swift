import Foundation
import SwiftData

nonisolated enum TaskQuantityPolicy {
    static let valueRange = 1...1_000_000
    static let maximumUnitLabelByteCount = 128
}

@Model
final class TaskQuantityGoal {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var targetAmount: Int = 1
    var unitLabel: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(
        taskID: UUID,
        targetAmount: Int,
        unitLabel: String,
        deviceID: String
    ) {
        id = TaskProgressIdentity.quantityGoalID(taskID: taskID)
        self.taskID = taskID
        self.targetAmount = targetAmount
        self.unitLabel = unitLabel
        self.deviceID = deviceID
    }
}

@Model
final class TaskQuantityEntry {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var quantityGoalID: UUID = UUID()
    var amount: Int = 1
    var recordedAt: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(
        id: UUID,
        taskID: UUID,
        amount: Int,
        recordedAt: Date = Date(),
        createdAt: Date = Date(),
        deviceID: String
    ) {
        self.id = id
        self.taskID = taskID
        quantityGoalID = TaskProgressIdentity.quantityGoalID(taskID: taskID)
        self.amount = amount
        self.recordedAt = recordedAt
        self.createdAt = createdAt
        updatedAt = createdAt
        self.deviceID = deviceID
    }
}
