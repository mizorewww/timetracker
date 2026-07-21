import Foundation
import SwiftData

@MainActor
struct TaskQuantityEntryPersistenceState {
    let tasks: [TaskNode]
    let recurrenceRules: [TaskRecurrenceRule]
    let recurrenceOccurrences: [TaskRecurrenceOccurrence]
    let quantityGoals: [TaskQuantityGoal]
    let quantityEntries: [TaskQuantityEntry]
    let taskByID: [UUID: TaskNode]
    let directWorkTaskIDs: Set<UUID>
    let recurrenceTemplateTaskIDs: Set<UUID>

    init(context: ModelContext) throws {
        tasks = try context.fetch(FetchDescriptor<TaskNode>())
        recurrenceRules = try context.fetch(
            FetchDescriptor<TaskRecurrenceRule>()
        )
        recurrenceOccurrences = try context.fetch(
            FetchDescriptor<TaskRecurrenceOccurrence>()
        )
        quantityGoals = try context.fetch(
            FetchDescriptor<TaskQuantityGoal>()
        )
        quantityEntries = try context.fetch(
            FetchDescriptor<TaskQuantityEntry>()
        )

        let canonicalTasks = tasks.deduplicatedByID()
        let visibleRules = recurrenceRules.visibleDeduplicatedByID()
        let visibleOccurrences = recurrenceOccurrences
            .visibleDeduplicatedByID()
        taskByID = canonicalTasks.reduce(into: [:]) {
            $0[$1.id] = $1
        }
        directWorkTaskIDs = TaskTrackingAvailabilityService()
            .directWorkTaskIDs(
                tasks: canonicalTasks,
                recurrenceRules: visibleRules,
                recurrenceOccurrences: visibleOccurrences
            )
        recurrenceTemplateTaskIDs = Set(
            visibleRules.map(\.templateTaskID)
        ).union(
            visibleOccurrences.map(\.templateTaskID)
        )
    }

    func affectedAncestorTaskIDs(for taskID: UUID) -> Set<UUID> {
        Set(
            StoreSelectionCoordinator().ancestorTaskIDs(
                for: taskID,
                taskByID: taskByID
            )
        )
    }
}
