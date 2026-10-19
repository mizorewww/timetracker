import Foundation
import SwiftData

/// The tasks a system surface may offer for tracking, with their tree paths.
/// Shared by the Widget/Watch materializer and the App Intents task query so
/// both apply the same availability rules.
nonisolated struct TrackableTaskCatalog {
    /// Deduplicated task rows, including tombstones, for ownership checks.
    let canonicalTaskRows: [TaskNode]
    let tree: TaskTreeIndexes
    /// Visible, directly trackable tasks in hierarchy order.
    let trackableTasks: [TaskNode]

    init(context: ModelContext) throws {
        canonicalTaskRows = try context
            .fetch(FetchDescriptor<TaskNode>())
            .deduplicatedByID()
        let tasks = canonicalTaskRows
            .filter { $0.deletedAt == nil }
            .sorted(by: Self.taskHierarchyOrder)
        let recurrence = try Self.completeRecurrenceFacts(
            tasks: tasks,
            rules: context
                .fetch(FetchDescriptor<TaskRecurrenceRule>())
                .visibleDeduplicatedByID(),
            occurrences: context
                .fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
                .visibleDeduplicatedByID()
        )
        let trackableTaskIDs = TaskTrackingAvailabilityService
            .directWorkTaskIDs(
                tasks: tasks,
                recurrenceRules: recurrence.rules,
                recurrenceOccurrences: recurrence.occurrences
            )
            .subtracting(recurrence.incompleteTaskIDs)
        tree = TaskTreeService.indexes(tasks: tasks)
        trackableTasks = tasks.filter { trackableTaskIDs.contains($0.id) }
    }

    /// AD-036: segments whose task row and owning session have arrived, in
    /// ledger order. A staged CloudKit import can deliver a segment first.
    func readableSegments(
        _ segments: [TimeSegment],
        sessions: [TimeSession]
    ) -> [TimeSegment] {
        let existingTaskIDs = Set(canonicalTaskRows.map(\.id))
        var taskIDBySessionID: [UUID: UUID] = [:]
        for session in sessions
            where existingTaskIDs.contains(session.taskID)
        {
            taskIDBySessionID[session.id] = session.taskID
        }
        return segments
            .filter {
                existingTaskIDs.contains($0.taskID) &&
                    taskIDBySessionID[$0.sessionID] == $0.taskID
            }
            .sorted(by: TimeSegment.startOrder)
    }

    private static func completeRecurrenceFacts(
        tasks: [TaskNode],
        rules: [TaskRecurrenceRule],
        occurrences: [TaskRecurrenceOccurrence]
    ) -> (
        rules: [TaskRecurrenceRule],
        occurrences: [TaskRecurrenceOccurrence],
        incompleteTaskIDs: Set<UUID>
    ) {
        let taskIDs = Set(tasks.map(\.id))
        let visibleRuleByID = rules.latestByID()
        var incompleteTaskIDs = Set<UUID>()

        for occurrence in occurrences {
            let relationshipIsComplete =
                visibleRuleByID[occurrence.ruleID]?.templateTaskID ==
                occurrence.templateTaskID &&
                taskIDs.contains(occurrence.templateTaskID) &&
                taskIDs.contains(occurrence.generatedTaskID)
            guard relationshipIsComplete == false else { continue }
            if taskIDs.contains(occurrence.templateTaskID) {
                incompleteTaskIDs.insert(occurrence.templateTaskID)
            }
            if taskIDs.contains(occurrence.generatedTaskID) {
                incompleteTaskIDs.insert(occurrence.generatedTaskID)
            }
        }

        let completeRules = rules.filter {
            taskIDs.contains($0.templateTaskID)
        }
        let completeRuleByID = completeRules.latestByID()
        let completeOccurrences = occurrences.filter {
            completeRuleByID[$0.ruleID]?.templateTaskID ==
                $0.templateTaskID &&
                taskIDs.contains($0.templateTaskID) &&
                taskIDs.contains($0.generatedTaskID)
        }
        return (
            completeRules,
            completeOccurrences,
            incompleteTaskIDs
        )
    }

    private static func taskHierarchyOrder(
        _ lhs: TaskNode,
        _ rhs: TaskNode
    ) -> Bool {
        if lhs.depth != rhs.depth {
            return lhs.depth < rhs.depth
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id < rhs.id
    }
}
