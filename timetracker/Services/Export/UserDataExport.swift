import Foundation
import SwiftData

/// Every synced business table, LWW-deduplicated and sorted by ID. Used only
/// for the user-initiated JSON export, which is not a restorable backup.
nonisolated struct UserDataSnapshot: Encodable, Equatable, Sendable {
    var tasks: [TaskRecord]
    var taskCategories: [TaskCategoryRecord]
    var taskCategoryAssignments: [TaskCategoryAssignmentRecord]
    var sessions: [TimeSessionRecord]
    var segments: [TimeSegmentRecord]
    var pomodoroRuns: [PomodoroRunRecord]
    var countdownEvents: [CountdownEventRecord]
    var syncedPreferences: [SyncedPreferenceRecord]
    var checklistItems: [ChecklistItemRecord]
    var checklistItemVisuals: [ChecklistItemVisualRecord]
    var inboxItems: [InboxItemRecord]
    var inboxSuggestions: [InboxSuggestionRecord]
    var inboxCaptureReceipts: [InboxCaptureReceiptRecord]
    var taskRecurrenceRules: [TaskRecurrenceRuleRecord]
    var taskRecurrenceOccurrences: [TaskRecurrenceOccurrenceRecord]
    var taskQuantityGoals: [TaskQuantityGoalRecord]
    var taskQuantityEntries: [TaskQuantityEntryRecord]

    static func capture(context: ModelContext) throws -> UserDataSnapshot {
        try UserDataSnapshot(
            tasks: records(TaskNode.self, context, TaskRecord.init),
            taskCategories: records(TaskCategory.self, context, TaskCategoryRecord.init),
            taskCategoryAssignments: records(TaskCategoryAssignment.self, context, TaskCategoryAssignmentRecord.init),
            sessions: records(TimeSession.self, context, TimeSessionRecord.init),
            segments: records(TimeSegment.self, context, TimeSegmentRecord.init),
            pomodoroRuns: records(PomodoroRun.self, context, PomodoroRunRecord.init),
            countdownEvents: records(CountdownEvent.self, context, CountdownEventRecord.init),
            syncedPreferences: context.fetch(FetchDescriptor<SyncedPreference>())
                .deduplicatedByID()
                .filter { SyncedPreferenceService.shouldSyncKey($0.key) }
                .map(SyncedPreferenceRecord.init)
                .sortedByID(),
            checklistItems: records(ChecklistItem.self, context, ChecklistItemRecord.init),
            checklistItemVisuals: records(ChecklistItemVisual.self, context, ChecklistItemVisualRecord.init),
            inboxItems: InboxSuggestionIdentityService().physicalResolutions(
                from: context.fetch(FetchDescriptor<InboxItem>())
            ).map {
                InboxItemRecord(
                    $0.winner,
                    mergedDismissedSuggestionRevisionID: $0.mergedDismissedSuggestionRevisionID
                )
            }.sortedByID(),
            inboxSuggestions: records(InboxSuggestion.self, context, InboxSuggestionRecord.init),
            inboxCaptureReceipts: records(InboxCaptureReceipt.self, context, InboxCaptureReceiptRecord.init),
            taskRecurrenceRules: records(TaskRecurrenceRule.self, context, TaskRecurrenceRuleRecord.init),
            taskRecurrenceOccurrences: records(TaskRecurrenceOccurrence.self, context, TaskRecurrenceOccurrenceRecord.init),
            taskQuantityGoals: records(TaskQuantityGoal.self, context, TaskQuantityGoalRecord.init),
            taskQuantityEntries: records(TaskQuantityEntry.self, context, TaskQuantityEntryRecord.init)
        )
    }

    private static func records<Model: PersistentModel & PersistentUUIDModel, Record: UserDataRecord>(
        _: Model.Type,
        _ context: ModelContext,
        _ makeRecord: (Model) -> Record
    ) throws -> [Record] {
        try context.fetch(FetchDescriptor<Model>()).deduplicatedByID().map(makeRecord).sortedByID()
    }
}

struct UserDataExport: Encodable {
    let format = "timetracker.cloudSyncedData"
    let schemaVersion = 1
    let exportedAt: Date
    let appVersion: String
    let data: UserDataSnapshot

    /// Captures under the store lock in a fresh read context so the export is
    /// one consistent cut of the store.
    static func encodedJSON(container: ModelContainer, exportedAt: Date = Date()) throws -> String {
        let snapshot = try StoreMutationTransaction(
            scope: StoreScope(container: container),
            container: container
        ).withFreshReadContext(UserDataSnapshot.capture)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let export = UserDataExport(
            exportedAt: exportedAt,
            appVersion: AppBuildInfo.versionSummary,
            data: snapshot
        )
        return try String(decoding: encoder.encode(export), as: UTF8.self)
    }
}
