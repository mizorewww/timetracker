import Foundation
import SwiftData

extension StoreScopedTaskLifecycleCommandCoordinator {
    static func quantityGoalState(
        taskID: UUID,
        context: ModelContext
    ) throws -> (activeMutationID: UUID?, hasDeletedRow: Bool) {
        let requestedTaskID = taskID
        let rows = try context.fetch(
            FetchDescriptor<TaskQuantityGoal>(
                predicate: #Predicate { $0.taskID == requestedTaskID }
            )
        )
        let goal = rows.latestByID()[
            TaskProgressIdentity.quantityGoalID(taskID: taskID)
        ]
        return (
            activeMutationID: goal?.deletedAt == nil
                ? goal?.clientMutationID
                : nil,
            hasDeletedRow: goal?.deletedAt != nil
        )
    }

    static func quantityEntryRevision(
        taskID: UUID,
        context: ModelContext
    ) throws -> UUID {
        let requestedTaskID = taskID
        let entries = try context.fetch(
            FetchDescriptor<TaskQuantityEntry>(
                predicate: #Predicate { $0.taskID == requestedTaskID }
            )
        )
        return TaskQuantityEntryRevision.value(
            taskID: taskID,
            entries: entries
        )
    }
}
