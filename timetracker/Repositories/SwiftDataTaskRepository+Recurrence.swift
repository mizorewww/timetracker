import Foundation

nonisolated extension SwiftDataTaskRepository {
    func createGeneratedRecurrenceTask(
        id: UUID,
        template: TaskNode,
        occurrenceDayKey: String,
        now: Date
    ) throws -> TaskNode {
        let task = try createTask(
            proposedID: id,
            title: template.title,
            parentID: template.id,
            colorHex: template.colorHex,
            iconName: template.iconName
        )
        task.kindRaw = "task"
        task.notes = template.notes
        task.estimatedSeconds = template.estimatedSeconds
        task.dueAt = nil
        task.sortOrder = TaskRecurrenceDayKey.generatedTaskSortOrder(
            for: occurrenceDayKey
        )
        task.createdAt = now
        task.updatedAt = now
        task.deviceID = deviceID
        task.clientMutationID = id
        return task
    }
}
