import CryptoKit
import Foundation

struct SyncDataSnapshot: Codable, Equatable {
    var tasks: [TaskRecord] = []
    var taskCategories: [TaskCategoryRecord] = []
    var taskCategoryAssignments: [TaskCategoryAssignmentRecord] = []
    var sessions: [TimeSessionRecord] = []
    var segments: [TimeSegmentRecord] = []
    var pomodoroRuns: [PomodoroRunRecord] = []
    var countdownEvents: [CountdownEventRecord] = []
    var syncedPreferences: [SyncedPreferenceRecord] = []
    var checklistItems: [ChecklistItemRecord] = []
    var checklistItemVisuals: [ChecklistItemVisualRecord] = []
    var inboxItems: [InboxItemRecord] = []
    var inboxSuggestions: [InboxSuggestionRecord] = []
    /// Optional so snapshots written before schema V11 retain their existing
    /// recovery path. New captures always write an array, including `[]`.
    var inboxCaptureReceipts: [InboxCaptureReceiptRecord]?
    /// Optional tables preserve legacy snapshot semantics: missing means
    /// unknown pre-V13 state, while an explicit `[]` is authoritative.
    var taskRecurrenceRules: [TaskRecurrenceRuleRecord]?
    var taskRecurrenceOccurrences: [TaskRecurrenceOccurrenceRecord]?
    var taskQuantityGoals: [TaskQuantityGoalRecord]?
    var taskQuantityEntries: [TaskQuantityEntryRecord]?

    mutating func removeExcludedPreferences() -> Bool {
        let originalCount = syncedPreferences.count
        syncedPreferences.removeAll { !SyncedPreferenceService.shouldSyncKey($0.key) }
        return syncedPreferences.count != originalCount
    }

    mutating func applyChanges(from baseline: Self, to updated: Self) {
        tasks.applyChanges(from: baseline.tasks, to: updated.tasks)
        taskCategories.applyChanges(from: baseline.taskCategories, to: updated.taskCategories)
        taskCategoryAssignments.applyChanges(from: baseline.taskCategoryAssignments, to: updated.taskCategoryAssignments)
        sessions.applyChanges(from: baseline.sessions, to: updated.sessions)
        segments.applyChanges(from: baseline.segments, to: updated.segments)
        pomodoroRuns.applyChanges(from: baseline.pomodoroRuns, to: updated.pomodoroRuns)
        countdownEvents.applyChanges(from: baseline.countdownEvents, to: updated.countdownEvents)
        syncedPreferences.applyChanges(from: baseline.syncedPreferences, to: updated.syncedPreferences)
        checklistItems.applyChanges(from: baseline.checklistItems, to: updated.checklistItems)
        checklistItemVisuals.applyChanges(from: baseline.checklistItemVisuals, to: updated.checklistItemVisuals)
        inboxItems.applyChanges(from: baseline.inboxItems, to: updated.inboxItems)
        inboxSuggestions.applyChanges(from: baseline.inboxSuggestions, to: updated.inboxSuggestions)
        inboxCaptureReceipts = Self.applyingOptionalChanges(
            current: inboxCaptureReceipts,
            baseline: baseline.inboxCaptureReceipts,
            updated: updated.inboxCaptureReceipts
        )
        taskRecurrenceRules = Self.applyingOptionalChanges(
            current: taskRecurrenceRules,
            baseline: baseline.taskRecurrenceRules,
            updated: updated.taskRecurrenceRules
        )
        taskRecurrenceOccurrences = Self.applyingOptionalChanges(
            current: taskRecurrenceOccurrences,
            baseline: baseline.taskRecurrenceOccurrences,
            updated: updated.taskRecurrenceOccurrences
        )
        taskQuantityGoals = Self.applyingOptionalChanges(
            current: taskQuantityGoals,
            baseline: baseline.taskQuantityGoals,
            updated: updated.taskQuantityGoals
        )
        taskQuantityEntries = Self.applyingOptionalChanges(
            current: taskQuantityEntries,
            baseline: baseline.taskQuantityEntries,
            updated: updated.taskQuantityEntries
        )
    }

    private static func applyingOptionalChanges<Record: SyncSnapshotRecord & Equatable>(
        current: [Record]?,
        baseline: [Record]?,
        updated: [Record]?
    ) -> [Record]? {
        guard let updated else { return current }
        var result = current ?? []
        result.applyChanges(from: baseline ?? [], to: updated)
        return result
    }

    var hasProtectableUserContent: Bool {
        !tasks.isEmpty ||
            !taskCategories.isEmpty ||
            !taskCategoryAssignments.isEmpty ||
            !sessions.isEmpty ||
            !segments.isEmpty ||
            !pomodoroRuns.isEmpty ||
            !countdownEvents.isEmpty ||
            !syncedPreferences.isEmpty ||
            !checklistItems.isEmpty ||
            !checklistItemVisuals.isEmpty ||
            !inboxItems.isEmpty ||
            !inboxSuggestions.isEmpty ||
            !(inboxCaptureReceipts ?? []).isEmpty ||
            !(taskRecurrenceRules ?? []).isEmpty ||
            !(taskRecurrenceOccurrences ?? []).isEmpty ||
            !(taskQuantityGoals ?? []).isEmpty ||
            !(taskQuantityEntries ?? []).isEmpty
    }

    var hasVisibleUserContent: Bool {
        tasks.contains { $0.deletedAt == nil } ||
            taskCategories.contains { $0.deletedAt == nil } ||
            taskCategoryAssignments.contains { $0.deletedAt == nil } ||
            sessions.contains { $0.deletedAt == nil } ||
            segments.contains { $0.deletedAt == nil } ||
            pomodoroRuns.contains { $0.deletedAt == nil } ||
            countdownEvents.contains { $0.deletedAt == nil } ||
            syncedPreferences.contains { $0.deletedAt == nil } ||
            checklistItems.contains { $0.deletedAt == nil } ||
            checklistItemVisuals.contains { $0.deletedAt == nil } ||
            inboxItems.contains { $0.deletedAt == nil } ||
            inboxSuggestions.contains { $0.deletedAt == nil } ||
            (taskRecurrenceRules ?? []).contains { $0.deletedAt == nil } ||
            (taskRecurrenceOccurrences ?? []).contains { $0.deletedAt == nil } ||
            (taskQuantityGoals ?? []).contains { $0.deletedAt == nil } ||
            (taskQuantityEntries ?? []).contains { $0.deletedAt == nil }
    }

    var localizedSummary: String {
        if taskRecurrenceRules != nil ||
            taskRecurrenceOccurrences != nil ||
            taskQuantityGoals != nil ||
            taskQuantityEntries != nil
        {
            let recurrenceCount =
                (taskRecurrenceRules ?? []).filter {
                    $0.deletedAt == nil
                }.count +
                (taskRecurrenceOccurrences ?? []).filter {
                    $0.deletedAt == nil
                }.count
            let quantityCount =
                (taskQuantityGoals ?? []).filter {
                    $0.deletedAt == nil
                }.count +
                (taskQuantityEntries ?? []).filter {
                    $0.deletedAt == nil
                }.count
            return String(
                format: AppStrings.localized(
                    "sync.conflict.summaryWithTaskProgress"
                ),
                tasks.filter { $0.deletedAt == nil }.count,
                segments.filter { $0.deletedAt == nil }.count,
                pomodoroRuns.filter { $0.deletedAt == nil }.count,
                checklistItems.filter { $0.deletedAt == nil }.count,
                inboxItems.filter { $0.deletedAt == nil }.count,
                recurrenceCount,
                quantityCount
            )
        }
        return String(
            format: AppStrings.localized("sync.conflict.summary"),
            tasks.filter { $0.deletedAt == nil }.count,
            segments.filter { $0.deletedAt == nil }.count,
            pomodoroRuns.filter { $0.deletedAt == nil }.count,
            checklistItems.filter { $0.deletedAt == nil }.count,
            inboxItems.filter { $0.deletedAt == nil }.count
        )
    }

    func fingerprint() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        return Self.fingerprint(serializedData: data)
    }

    /// Reuses the SHA-256 contract of `fingerprint()` when a caller already
    /// owns the canonical sorted JSON bytes. This avoids encoding a large
    /// snapshot a second time on the durable-slot write and read paths.
    nonisolated static func fingerprint(serializedData: Data) -> String {
        let digest = SHA256.hash(data: serializedData)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
