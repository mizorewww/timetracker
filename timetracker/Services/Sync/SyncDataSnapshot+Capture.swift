import SwiftData

extension SyncDataSnapshot {
    /// Captures from the supplied context. Production sync entrypoints must
    /// call this only with the fresh context supplied by
    /// `withLockedFreshStoreContext`; direct calls are intended for isolated
    /// migrations and tests.
    nonisolated static func capture(context: ModelContext) throws -> SyncDataSnapshot {
        try capture(
            context: context,
            updating: nil,
            domains: Set(SyncSnapshotDomain.allCases)
        )
    }

    /// Incremental variant with the same store-lock precondition as the full
    /// capture entrypoint.
    nonisolated static func capture(
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
            snapshot.taskRecurrenceRules = try context.fetch(FetchDescriptor<TaskRecurrenceRule>())
                .deduplicatedByID().map(TaskRecurrenceRuleRecord.init).sortedByID()
            snapshot.taskRecurrenceOccurrences = try context.fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
                .deduplicatedByID().map(TaskRecurrenceOccurrenceRecord.init).sortedByID()
            snapshot.taskQuantityGoals = try context.fetch(FetchDescriptor<TaskQuantityGoal>())
                .deduplicatedByID().map(TaskQuantityGoalRecord.init).sortedByID()
            snapshot.taskQuantityEntries = try context.fetch(FetchDescriptor<TaskQuantityEntry>())
                .deduplicatedByID().map(TaskQuantityEntryRecord.init).sortedByID()
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
            snapshot.inboxItems = try InboxSuggestionIdentityService().physicalResolutions(
                from: context.fetch(FetchDescriptor<InboxItem>())
            ).map {
                InboxItemRecord(
                    $0.winner,
                    mergedDismissedSuggestionRevisionID: $0.mergedDismissedSuggestionRevisionID
                )
            }.sortedByID()
            snapshot.inboxSuggestions = try context.fetch(FetchDescriptor<InboxSuggestion>())
                .deduplicatedByID().map(InboxSuggestionRecord.init).sortedByID()
            snapshot.inboxCaptureReceipts = try context
                .fetch(FetchDescriptor<InboxCaptureReceipt>())
                .deduplicatedByID()
                .map(InboxCaptureReceiptRecord.init)
                .sortedByID()
        }
        return snapshot
    }

    private nonisolated static func captureAllDomains(context: ModelContext) throws -> SyncDataSnapshot {
        try SyncDataSnapshot(
            tasks: context.fetch(FetchDescriptor<TaskNode>()).deduplicatedByID().map(TaskRecord.init).sortedByID(),
            taskCategories: context.fetch(FetchDescriptor<TaskCategory>()).deduplicatedByID().map(TaskCategoryRecord.init).sortedByID(),
            taskCategoryAssignments: context.fetch(FetchDescriptor<TaskCategoryAssignment>()).deduplicatedByID().map(TaskCategoryAssignmentRecord.init).sortedByID(),
            sessions: context.fetch(FetchDescriptor<TimeSession>()).deduplicatedByID().map(TimeSessionRecord.init).sortedByID(),
            segments: context.fetch(FetchDescriptor<TimeSegment>()).deduplicatedByID().map(TimeSegmentRecord.init).sortedByID(),
            pomodoroRuns: context.fetch(FetchDescriptor<PomodoroRun>()).deduplicatedByID().map(PomodoroRunRecord.init).sortedByID(),
            countdownEvents: context.fetch(FetchDescriptor<CountdownEvent>()).deduplicatedByID().map(CountdownEventRecord.init).sortedByID(),
            syncedPreferences: context.fetch(FetchDescriptor<SyncedPreference>())
                .deduplicatedByID()
                .filter { SyncedPreferenceService.shouldSyncKey($0.key) }
                .map(SyncedPreferenceRecord.init)
                .sortedByID(),
            checklistItems: context.fetch(FetchDescriptor<ChecklistItem>()).deduplicatedByID().map(ChecklistItemRecord.init).sortedByID(),
            checklistItemVisuals: context.fetch(FetchDescriptor<ChecklistItemVisual>()).deduplicatedByID().map(ChecklistItemVisualRecord.init).sortedByID(),
            inboxItems: InboxSuggestionIdentityService().physicalResolutions(
                from: context.fetch(FetchDescriptor<InboxItem>())
            ).map {
                InboxItemRecord(
                    $0.winner,
                    mergedDismissedSuggestionRevisionID: $0.mergedDismissedSuggestionRevisionID
                )
            }.sortedByID(),
            inboxSuggestions: context.fetch(FetchDescriptor<InboxSuggestion>()).deduplicatedByID().map(InboxSuggestionRecord.init).sortedByID(),
            inboxCaptureReceipts: context.fetch(FetchDescriptor<InboxCaptureReceipt>()).deduplicatedByID().map(InboxCaptureReceiptRecord.init).sortedByID(),
            taskRecurrenceRules: context.fetch(FetchDescriptor<TaskRecurrenceRule>()).deduplicatedByID().map(TaskRecurrenceRuleRecord.init).sortedByID(),
            taskRecurrenceOccurrences: context.fetch(FetchDescriptor<TaskRecurrenceOccurrence>()).deduplicatedByID().map(TaskRecurrenceOccurrenceRecord.init).sortedByID(),
            taskQuantityGoals: context.fetch(FetchDescriptor<TaskQuantityGoal>()).deduplicatedByID().map(TaskQuantityGoalRecord.init).sortedByID(),
            taskQuantityEntries: context.fetch(FetchDescriptor<TaskQuantityEntry>()).deduplicatedByID().map(TaskQuantityEntryRecord.init).sortedByID()
        )
    }
}
