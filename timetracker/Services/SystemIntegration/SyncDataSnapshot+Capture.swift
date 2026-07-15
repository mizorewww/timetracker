import SwiftData

extension SyncDataSnapshot {
    @MainActor
    static func capture(context: ModelContext) throws -> SyncDataSnapshot {
        try capture(
            context: context,
            updating: nil,
            domains: Set(SyncSnapshotDomain.allCases)
        )
    }

    @MainActor
    static func capture(
        context: ModelContext,
        updating baseline: SyncDataSnapshot?,
        domains: Set<SyncSnapshotDomain>
    ) throws -> SyncDataSnapshot {
        guard var snapshot = baseline else {
            return try captureAllDomains(context: context)
        }

        if domains.contains(.tasks) {
            snapshot.tasks = try context.fetch(FetchDescriptor<TaskNode>())
                .deduplicatedByID().map(TaskRecord.init).sortedByID()
            snapshot.taskCategories = try context.fetch(FetchDescriptor<TaskCategory>())
                .deduplicatedByID().map(TaskCategoryRecord.init).sortedByID()
            snapshot.taskCategoryAssignments = try context.fetch(FetchDescriptor<TaskCategoryAssignment>())
                .deduplicatedByID().map(TaskCategoryAssignmentRecord.init).sortedByID()
        }
        if domains.contains(.ledger) {
            snapshot.sessions = try context.fetch(FetchDescriptor<TimeSession>())
                .deduplicatedByID().map(TimeSessionRecord.init).sortedByID()
            snapshot.segments = try context.fetch(FetchDescriptor<TimeSegment>())
                .deduplicatedByID().map(TimeSegmentRecord.init).sortedByID()
        }
        if domains.contains(.pomodoro) {
            snapshot.pomodoroRuns = try context.fetch(FetchDescriptor<PomodoroRun>())
                .deduplicatedByID().map(PomodoroRunRecord.init).sortedByID()
        }
        if domains.contains(.countdown) {
            snapshot.countdownEvents = try context.fetch(FetchDescriptor<CountdownEvent>())
                .deduplicatedByID().map(CountdownEventRecord.init).sortedByID()
        }
        if domains.contains(.preferences) {
            snapshot.syncedPreferences = try context.fetch(FetchDescriptor<SyncedPreference>())
                .deduplicatedByID()
                .filter { SyncedPreferenceService.shouldSyncKey($0.key) }
                .map(SyncedPreferenceRecord.init)
                .sortedByID()
        }
        if domains.contains(.checklist) {
            snapshot.checklistItems = try context.fetch(FetchDescriptor<ChecklistItem>())
                .deduplicatedByID().map(ChecklistItemRecord.init).sortedByID()
            snapshot.checklistItemVisuals = try context.fetch(FetchDescriptor<ChecklistItemVisual>())
                .deduplicatedByID().map(ChecklistItemVisualRecord.init).sortedByID()
        }
        if domains.contains(.inbox) {
            snapshot.inboxItems = try context.fetch(FetchDescriptor<InboxItem>())
                .deduplicatedByID().map(InboxItemRecord.init).sortedByID()
            snapshot.inboxSuggestions = try context.fetch(FetchDescriptor<InboxSuggestion>())
                .deduplicatedByID().map(InboxSuggestionRecord.init).sortedByID()
        }
        return snapshot
    }

    @MainActor
    private static func captureAllDomains(context: ModelContext) throws -> SyncDataSnapshot {
        SyncDataSnapshot(
            tasks: try context.fetch(FetchDescriptor<TaskNode>()).deduplicatedByID().map(TaskRecord.init).sortedByID(),
            taskCategories: try context.fetch(FetchDescriptor<TaskCategory>()).deduplicatedByID().map(TaskCategoryRecord.init).sortedByID(),
            taskCategoryAssignments: try context.fetch(FetchDescriptor<TaskCategoryAssignment>()).deduplicatedByID().map(TaskCategoryAssignmentRecord.init).sortedByID(),
            sessions: try context.fetch(FetchDescriptor<TimeSession>()).deduplicatedByID().map(TimeSessionRecord.init).sortedByID(),
            segments: try context.fetch(FetchDescriptor<TimeSegment>()).deduplicatedByID().map(TimeSegmentRecord.init).sortedByID(),
            pomodoroRuns: try context.fetch(FetchDescriptor<PomodoroRun>()).deduplicatedByID().map(PomodoroRunRecord.init).sortedByID(),
            countdownEvents: try context.fetch(FetchDescriptor<CountdownEvent>()).deduplicatedByID().map(CountdownEventRecord.init).sortedByID(),
            syncedPreferences: try context.fetch(FetchDescriptor<SyncedPreference>())
                .deduplicatedByID()
                .filter { SyncedPreferenceService.shouldSyncKey($0.key) }
                .map(SyncedPreferenceRecord.init)
                .sortedByID(),
            checklistItems: try context.fetch(FetchDescriptor<ChecklistItem>()).deduplicatedByID().map(ChecklistItemRecord.init).sortedByID(),
            checklistItemVisuals: try context.fetch(FetchDescriptor<ChecklistItemVisual>()).deduplicatedByID().map(ChecklistItemVisualRecord.init).sortedByID(),
            inboxItems: try context.fetch(FetchDescriptor<InboxItem>()).deduplicatedByID().map(InboxItemRecord.init).sortedByID(),
            inboxSuggestions: try context.fetch(FetchDescriptor<InboxSuggestion>()).deduplicatedByID().map(InboxSuggestionRecord.init).sortedByID()
        )
    }
}
