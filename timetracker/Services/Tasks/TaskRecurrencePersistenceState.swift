import Foundation
import SwiftData

@MainActor
struct TaskRecurrencePersistenceState {
    var rulesByID: [UUID: TaskRecurrenceRule]
    let ruleRowsByID: [UUID: [TaskRecurrenceRule]]
    let taskRowsByID: [UUID: [TaskNode]]
    let occurrenceRowsByID: [UUID: [TaskRecurrenceOccurrence]]
    let quantityGoalRowsByID: [UUID: [TaskQuantityGoal]]
    let claimedRuleIDs: Set<UUID>
    let claimedRuleTemplateTaskIDs: Set<UUID>
    let claimedTaskIDs: Set<UUID>
    let claimedOccurrenceIDs: Set<UUID>
    let claimedOccurrenceKeys: Set<String>
    let claimedQuantityGoalIDs: Set<UUID>
    let taskByID: [UUID: TaskNode]
    let quantityGoalByID: [UUID: TaskQuantityGoal]
    let templateEligibleTaskIDs: Set<UUID>
    let activeWorkTaskIDs: Set<UUID>

    init(context: ModelContext) throws {
        let rules = try context.fetch(FetchDescriptor<TaskRecurrenceRule>())
        let tasks = try context.fetch(FetchDescriptor<TaskNode>())
        let occurrences = try context.fetch(
            FetchDescriptor<TaskRecurrenceOccurrence>()
        )
        let goals = try context.fetch(FetchDescriptor<TaskQuantityGoal>())
        let entries = try context.fetch(FetchDescriptor<TaskQuantityEntry>())
        let segments = try context.fetch(FetchDescriptor<TimeSegment>())
            .visibleDeduplicatedByID()
        let pomodoroRuns = try context.fetch(
            FetchDescriptor<PomodoroRun>()
        ).visibleDeduplicatedByID()

        rulesByID = rules.latestByID()
        ruleRowsByID = Dictionary(grouping: rules, by: \.id)
        taskRowsByID = Dictionary(grouping: tasks, by: \.id)
        occurrenceRowsByID = Dictionary(grouping: occurrences, by: \.id)
        quantityGoalRowsByID = Dictionary(grouping: goals, by: \.id)
        taskByID = tasks.latestByID()
        quantityGoalByID = goals.latestByID()
        claimedRuleIDs = Set(rules.map(\.id))
            .union(occurrences.map(\.ruleID))
        claimedRuleTemplateTaskIDs = Set(rules.map(\.templateTaskID))
            .union(occurrences.map(\.templateTaskID))
        claimedTaskIDs = Set(tasks.map(\.id))
            .union(occurrences.map(\.generatedTaskID))
            .union(entries.map(\.taskID))
        claimedOccurrenceIDs = Set(occurrences.map(\.id))
        claimedOccurrenceKeys = Set(
            occurrences.map {
                Self.occurrenceKey(
                    ruleID: $0.ruleID,
                    dayKey: $0.occurrenceDayKey
                )
            }
        )
        claimedQuantityGoalIDs = Set(goals.map(\.id))
            .union(entries.map(\.quantityGoalID))
        templateEligibleTaskIDs = TaskTrackingAvailabilityService()
            .trackableTaskIDs(tasks: Array(taskByID.values))
            .subtracting(Set(occurrences.map(\.generatedTaskID)))
        activeWorkTaskIDs = Set(
            segments.lazy.filter { $0.endedAt == nil }.map(\.taskID)
        ).union(
            pomodoroRuns.lazy.filter {
                $0.endedAt == nil &&
                    $0.state != .completed &&
                    $0.state != .cancelled
            }.map(\.taskID)
        )
    }

    static func occurrenceKey(ruleID: UUID, dayKey: String) -> String {
        ruleID.uuidString.lowercased() + "|" + dayKey
    }

    func ancestors(of taskID: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        var visited = Set<UUID>()
        var cursor = taskByID[taskID]?.parentID
        while let taskID = cursor,
              visited.insert(taskID).inserted,
              let task = taskByID[taskID] {
            result.insert(taskID)
            cursor = task.parentID
        }
        return result
    }
}
