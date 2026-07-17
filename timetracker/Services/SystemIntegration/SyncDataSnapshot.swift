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
        var updatedReceipts = inboxCaptureReceipts ?? []
        updatedReceipts.applyChanges(
            from: baseline.inboxCaptureReceipts ?? [],
            to: updated.inboxCaptureReceipts ?? []
        )
        inboxCaptureReceipts = updatedReceipts
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
        !(inboxCaptureReceipts ?? []).isEmpty
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
        inboxSuggestions.contains { $0.deletedAt == nil }
    }

    var localizedSummary: String {
        String(
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
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
