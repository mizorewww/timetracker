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
            allTasks.lazy.filter { $0.deviceID == "demo" }.map(\.id)
        )
        let demoRules = try context.fetch(
            FetchDescriptor<TaskRecurrenceRule>()
        ).filter {
            $0.deviceID == "demo" ||
                seededDemoTaskIDs.contains($0.templateTaskID)
        }
        let demoRuleIDs = Set(demoRules.map(\.id))
        let demoOccurrences = try context.fetch(
            FetchDescriptor<TaskRecurrenceOccurrence>()
        ).filter {
            $0.deviceID == "demo" ||
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
                $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID)
            }
        let demoSessionIDs = Set(demoSessions.map(\.id))
        let demoGoals = try context.fetch(
            FetchDescriptor<TaskQuantityGoal>()
        ).filter {
            $0.deviceID == "demo" ||
                demoTaskIDs.contains($0.taskID)
        }
        let demoGoalIDs = Set(demoGoals.map(\.id))

        try tombstone(
            context.fetch(FetchDescriptor<PomodoroRun>()).filter {
                $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID)
            },
            now: now,
            deviceID: deviceID
        )
        try tombstone(
            context.fetch(FetchDescriptor<TimeSegment>()).filter {
                $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID) || demoSessionIDs.contains($0.sessionID)
            },
            now: now,
            deviceID: deviceID
        )
        tombstone(demoSessions, now: now, deviceID: deviceID)
        tombstone(demoOccurrences, now: now, deviceID: deviceID)
        try tombstone(
            context.fetch(FetchDescriptor<TaskQuantityEntry>())
                .filter {
                    $0.deviceID == "demo" ||
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
                $0.deviceID == "demo" || demoChecklistIDs.contains($0.checklistItemID)
            },
            now: now,
            deviceID: deviceID
        )
        try tombstone(
            context.fetch(FetchDescriptor<InboxSuggestion>()).filter {
                $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID)
            },
            now: now,
            deviceID: deviceID
        )
        try tombstone(
            context.fetch(FetchDescriptor<InboxItem>()).filter { $0.deviceID == "demo" },
            now: now,
            deviceID: deviceID
        )
        tombstone(demoTasks, now: now, deviceID: deviceID)
        try tombstone(
            context.fetch(FetchDescriptor<TaskCategory>()).filter { $0.deviceID == "demo" },
            now: now,
            deviceID: deviceID
        )
        try tombstone(
            context.fetch(FetchDescriptor<TaskCategoryAssignment>()).filter {
                $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID)
            },
            now: now,
            deviceID: deviceID
        )
        try context.saveAfterMutationStep()
    }

    static func clearAllChanges(
        context: ModelContext,
        includesPreferences: Bool
    ) throws {
        let now = Date()
        let deviceID = DeviceIdentity.current
        // CloudKit user-fact models retain a tombstone so offline devices receive
        // the reset instead of resurrecting old rows.
        try tombstone(context.fetch(FetchDescriptor<CountdownEvent>()), now: now, deviceID: deviceID)
        if includesPreferences {
            try tombstone(context.fetch(FetchDescriptor<SyncedPreference>()), now: now, deviceID: deviceID)
        }
        try tombstone(context.fetch(FetchDescriptor<PomodoroRun>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TimeSegment>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TimeSession>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TaskRecurrenceOccurrence>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TaskQuantityEntry>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TaskQuantityGoal>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TaskRecurrenceRule>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<ChecklistItem>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<ChecklistItemVisual>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<InboxSuggestion>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<InboxItem>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<InboxCaptureReceipt>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TaskNode>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TaskCategory>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TaskCategoryAssignment>()), now: now, deviceID: deviceID)
        try context.saveAfterMutationStep()
    }

    private static func tombstone<Model: SoftDeletablePersistentUUIDModel>(
        _ models: [Model],
        now: Date,
        deviceID: String
    ) {
        for model in models {
            let mutationDate = PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: model.updatedAt
            )
            model.deletedAt = mutationDate
            model.updatedAt = mutationDate
            model.deviceID = deviceID
            (model as? ClientMutationTrackedModel)?.clientMutationID = UUID()
        }
    }
}
