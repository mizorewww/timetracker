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
        let demoTasks = try context.fetch(FetchDescriptor<TaskNode>()).filter { $0.deviceID == "demo" }
        let demoTaskIDs = Set(demoTasks.map(\.id))
        let demoSessions = try context.fetch(FetchDescriptor<TimeSession>()).filter {
            $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID)
        }
        let demoSessionIDs = Set(demoSessions.map(\.id))

        tombstone(
            try context.fetch(FetchDescriptor<PomodoroRun>()).filter {
                $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID)
            },
            now: now,
            deviceID: deviceID
        )
        tombstone(
            try context.fetch(FetchDescriptor<TimeSegment>()).filter {
                $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID) || demoSessionIDs.contains($0.sessionID)
            },
            now: now,
            deviceID: deviceID
        )
        tombstone(demoSessions, now: now, deviceID: deviceID)
        let demoChecklistItems = try context.fetch(FetchDescriptor<ChecklistItem>()).filter { demoTaskIDs.contains($0.taskID) }
        let demoChecklistIDs = Set(demoChecklistItems.map(\.id))
        tombstone(demoChecklistItems, now: now, deviceID: deviceID)
        tombstone(
            try context.fetch(FetchDescriptor<ChecklistItemVisual>()).filter {
                $0.deviceID == "demo" || demoChecklistIDs.contains($0.checklistItemID)
            },
            now: now,
            deviceID: deviceID
        )
        tombstone(
            try context.fetch(FetchDescriptor<InboxSuggestion>()).filter {
                $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID)
            },
            now: now,
            deviceID: deviceID
        )
        tombstone(
            try context.fetch(FetchDescriptor<InboxItem>()).filter { $0.deviceID == "demo" },
            now: now,
            deviceID: deviceID
        )
        tombstone(demoTasks, now: now, deviceID: deviceID)
        tombstone(
            try context.fetch(FetchDescriptor<TaskCategory>()).filter { $0.deviceID == "demo" },
            now: now,
            deviceID: deviceID
        )
        tombstone(
            try context.fetch(FetchDescriptor<TaskCategoryAssignment>()).filter {
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
        tombstone(try context.fetch(FetchDescriptor<CountdownEvent>()), now: now, deviceID: deviceID)
        if includesPreferences {
            tombstone(try context.fetch(FetchDescriptor<SyncedPreference>()), now: now, deviceID: deviceID)
        }
        tombstone(try context.fetch(FetchDescriptor<PomodoroRun>()), now: now, deviceID: deviceID)
        tombstone(try context.fetch(FetchDescriptor<TimeSegment>()), now: now, deviceID: deviceID)
        tombstone(try context.fetch(FetchDescriptor<TimeSession>()), now: now, deviceID: deviceID)
        tombstone(try context.fetch(FetchDescriptor<ChecklistItem>()), now: now, deviceID: deviceID)
        tombstone(try context.fetch(FetchDescriptor<ChecklistItemVisual>()), now: now, deviceID: deviceID)
        tombstone(try context.fetch(FetchDescriptor<InboxSuggestion>()), now: now, deviceID: deviceID)
        tombstone(try context.fetch(FetchDescriptor<InboxItem>()), now: now, deviceID: deviceID)
        tombstone(try context.fetch(FetchDescriptor<InboxCaptureReceipt>()), now: now, deviceID: deviceID)
        tombstone(try context.fetch(FetchDescriptor<TaskNode>()), now: now, deviceID: deviceID)
        tombstone(try context.fetch(FetchDescriptor<TaskCategory>()), now: now, deviceID: deviceID)
        tombstone(try context.fetch(FetchDescriptor<TaskCategoryAssignment>()), now: now, deviceID: deviceID)
        try context.saveAfterMutationStep()
    }

    private static func tombstone<Model>(
        _ models: [Model],
        now: Date,
        deviceID: String
    ) where Model: SoftDeletablePersistentUUIDModel {
        for model in models {
            model.deletedAt = now
            model.updatedAt = now
            model.deviceID = deviceID
            (model as? ClientMutationTrackedModel)?.clientMutationID = UUID()
        }
    }
}
