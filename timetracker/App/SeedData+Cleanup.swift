import SwiftData

extension SeedData {
    static func clearDemoData(context: ModelContext) throws {
        let demoTasks = try context.fetch(FetchDescriptor<TaskNode>()).filter { $0.deviceID == "demo" }
        let demoTaskIDs = Set(demoTasks.map(\.id))
        let demoSessions = try context.fetch(FetchDescriptor<TimeSession>()).filter {
            $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID)
        }
        let demoSessionIDs = Set(demoSessions.map(\.id))

        for model in try context.fetch(FetchDescriptor<DailySummary>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<PomodoroRun>()).filter({ $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID) }) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<TimeSegment>()).filter({ $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID) || demoSessionIDs.contains($0.sessionID) }) {
            context.delete(model)
        }
        for model in demoSessions {
            context.delete(model)
        }
        let demoChecklistItems = try context.fetch(FetchDescriptor<ChecklistItem>()).filter { demoTaskIDs.contains($0.taskID) }
        let demoChecklistIDs = Set(demoChecklistItems.map(\.id))
        for model in demoChecklistItems {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<ChecklistItemVisual>()).filter({ $0.deviceID == "demo" || demoChecklistIDs.contains($0.checklistItemID) }) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<InboxSuggestion>()).filter({ $0.deviceID == "demo" }) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<InboxItem>()).filter({ $0.deviceID == "demo" }) {
            context.delete(model)
        }
        for model in demoTasks {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<TaskCategory>()).filter({ $0.deviceID == "demo" }) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<TaskCategoryAssignment>()).filter({ $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID) }) {
            context.delete(model)
        }
        try context.save()
        setAutomaticDemoSeedingDisabled(true)
    }

    static func clearAll(
        context: ModelContext,
        disablesAutomaticDemoSeeding: Bool,
        includesPreferences: Bool
    ) throws {
        for model in try context.fetch(FetchDescriptor<DailySummary>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<CountdownEvent>()) {
            context.delete(model)
        }
        if includesPreferences {
            for model in try context.fetch(FetchDescriptor<SyncedPreference>()) {
                context.delete(model)
            }
        }
        for model in try context.fetch(FetchDescriptor<PomodoroRun>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<TimeSegment>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<TimeSession>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<ChecklistItem>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<ChecklistItemVisual>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<InboxSuggestion>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<InboxItem>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<TaskNode>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<TaskCategory>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<TaskCategoryAssignment>()) {
            context.delete(model)
        }
        try context.save()
        if disablesAutomaticDemoSeeding {
            setAutomaticDemoSeedingDisabled(true)
        }
    }
}
