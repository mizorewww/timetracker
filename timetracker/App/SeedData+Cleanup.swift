#if DEBUG
import Foundation
import SwiftData

extension SeedData {
    static func clearDemoData(context: ModelContext) throws {
        try context.performAtomicMutation {
            try clearDemoDataChanges(context: context)
        }
        setAutomaticDemoSeedingDisabled(true)
    }

    private static func clearDemoDataChanges(context: ModelContext) throws {
        let now = Date()
        let deviceID = DeviceIdentity.current
        let allTasks = try context.fetch(FetchDescriptor<TaskNode>())
        let seededDemoTaskIDs = Set(
            allTasks.lazy.filter { SyntheticDataOrigin.marks($0.deviceID) }.map(\.id)
        )
        let demoRules = try context.fetch(
            FetchDescriptor<TaskRecurrenceRule>()
        ).filter {
            SyntheticDataOrigin.marks($0.deviceID) ||
                seededDemoTaskIDs.contains($0.templateTaskID)
        }
        let demoRuleIDs = Set(demoRules.map(\.id))
        let demoOccurrences = try context.fetch(
            FetchDescriptor<TaskRecurrenceOccurrence>()
        ).filter {
            SyntheticDataOrigin.marks($0.deviceID) ||
                demoRuleIDs.contains($0.ruleID) ||
                seededDemoTaskIDs.contains($0.templateTaskID) ||
                seededDemoTaskIDs.contains($0.generatedTaskID)
        }
        let demoTaskIDs = seededDemoTaskIDs.union(
            demoOccurrences.map(\.generatedTaskID)
        )
        let demoTasks = allTasks.filter { demoTaskIDs.contains($0.id) }
        let demoSessions = try context.fetch(FetchDescriptor<TimeSession>())
            .filter {
                SyntheticDataOrigin.marks($0.deviceID) || demoTaskIDs.contains($0.taskID)
            }
        let demoSessionIDs = Set(demoSessions.map(\.id))
        let demoGoals = try context.fetch(
            FetchDescriptor<TaskQuantityGoal>()
        ).filter {
            SyntheticDataOrigin.marks($0.deviceID) ||
                demoTaskIDs.contains($0.taskID)
        }
        let demoGoalIDs = Set(demoGoals.map(\.id))

        try tombstone(
            context.fetch(FetchDescriptor<PomodoroRun>()).filter {
                SyntheticDataOrigin.marks($0.deviceID) || demoTaskIDs.contains($0.taskID)
            },
            now: now,
            deviceID: deviceID
        )
        try tombstone(
            context.fetch(FetchDescriptor<TimeSegment>()).filter {
                SyntheticDataOrigin.marks($0.deviceID) || demoTaskIDs.contains($0.taskID) || demoSessionIDs.contains($0.sessionID)
            },
            now: now,
            deviceID: deviceID
        )
        tombstone(demoSessions, now: now, deviceID: deviceID)
        tombstone(demoOccurrences, now: now, deviceID: deviceID)
        try tombstone(
            context.fetch(FetchDescriptor<TaskQuantityEntry>())
                .filter {
                    SyntheticDataOrigin.marks($0.deviceID) ||
                        demoTaskIDs.contains($0.taskID) ||
                        demoGoalIDs.contains($0.quantityGoalID)
                },
            now: now,
            deviceID: deviceID
        )
        tombstone(demoGoals, now: now, deviceID: deviceID)
        tombstone(demoRules, now: now, deviceID: deviceID)
        let demoChecklistItems = try context.fetch(FetchDescriptor<ChecklistItem>()).filter { demoTaskIDs.contains($0.taskID) }
        let demoChecklistIDs = Set(demoChecklistItems.map(\.id))
        tombstone(demoChecklistItems, now: now, deviceID: deviceID)
        try tombstone(
            context.fetch(FetchDescriptor<ChecklistItemVisual>()).filter {
                SyntheticDataOrigin.marks($0.deviceID) || demoChecklistIDs.contains($0.checklistItemID)
            },
            now: now,
            deviceID: deviceID
        )
        try tombstone(
            context.fetch(FetchDescriptor<InboxSuggestion>()).filter {
                SyntheticDataOrigin.marks($0.deviceID) || demoTaskIDs.contains($0.taskID)
            },
            now: now,
            deviceID: deviceID
        )
        try tombstone(
            context.fetch(FetchDescriptor<InboxItem>()).filter { SyntheticDataOrigin.marks($0.deviceID) },
            now: now,
            deviceID: deviceID
        )
        tombstone(demoTasks, now: now, deviceID: deviceID)
        try tombstone(
            context.fetch(FetchDescriptor<TaskCategory>()).filter { SyntheticDataOrigin.marks($0.deviceID) },
            now: now,
            deviceID: deviceID
        )
        try tombstone(
            context.fetch(FetchDescriptor<TaskCategoryAssignment>()).filter {
                SyntheticDataOrigin.marks($0.deviceID) || demoTaskIDs.contains($0.taskID)
            },
            now: now,
            deviceID: deviceID
        )
        try context.saveAfterMutationStep()
    }
}
#endif
