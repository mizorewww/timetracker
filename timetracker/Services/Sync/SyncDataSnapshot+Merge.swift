import Foundation

/// Record-level last-write-wins merge support for automatic sync-conflict
/// resolution. Mirrors the deterministic ordering documented for persistent
/// deduplication: newer `updatedAt` wins, a tombstone wins an equal timestamp,
/// then `createdAt`, then a canonical-content byte comparison so every device
/// picks the same winner for the same pair of records.
protocol SyncSnapshotLWWMergeableRecord: SyncSnapshotRecord, Codable {
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var deletedAt: Date? { get }
}

extension SyncSnapshotLWWMergeableRecord {
    func isPreferredMergeWinner(over other: Self) -> Bool {
        if updatedAt != other.updatedAt {
            return updatedAt > other.updatedAt
        }
        if (deletedAt == nil) != (other.deletedAt == nil) {
            return deletedAt != nil
        }
        if createdAt != other.createdAt {
            return createdAt > other.createdAt
        }
        // Same identity and timestamps but different content: fall back to a
        // canonical encoding comparison so the winner is independent of which
        // side of the merge supplied the record.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let ownBytes = try? encoder.encode(self),
              let otherBytes = try? encoder.encode(other),
              ownBytes != otherBytes
        else {
            return false
        }
        return !ownBytes.lexicographicallyPrecedes(otherBytes)
    }
}

extension Array where Element: SyncSnapshotLWWMergeableRecord {
    /// Unions two record arrays by identity, keeping the LWW winner for records
    /// present on both sides. The result is sorted by id so equal merge inputs
    /// always produce equal snapshots regardless of argument order.
    func mergedByIDLWW(with other: [Element]) -> [Element] {
        var winnerByID: [UUID: Element] = [:]
        winnerByID.reserveCapacity(count + other.count)
        for record in self {
            if let current = winnerByID[record.id] {
                winnerByID[record.id] = record.isPreferredMergeWinner(over: current) ? record : current
            } else {
                winnerByID[record.id] = record
            }
        }
        for record in other {
            if let current = winnerByID[record.id] {
                winnerByID[record.id] = record.isPreferredMergeWinner(over: current) ? record : current
            } else {
                winnerByID[record.id] = record
            }
        }
        return Array(winnerByID.values).sortedByID()
    }
}

extension SyncDataSnapshot {
    /// Two-way LWW union used by automatic conflict resolution. Neither side
    /// loses a record the other side lacks; shared identities keep the newest
    /// version under the same ordering rules CloudKit-style sync already
    /// applies. Optional tables treat `nil` as unknown pre-V13 state, so any
    /// non-nil side supplies the authoritative rows.
    func mergedForAutoResolution(with other: SyncDataSnapshot) -> SyncDataSnapshot {
        var merged = SyncDataSnapshot()
        merged.tasks = tasks.mergedByIDLWW(with: other.tasks)
        merged.taskCategories = taskCategories.mergedByIDLWW(with: other.taskCategories)
        merged.taskCategoryAssignments = taskCategoryAssignments.mergedByIDLWW(with: other.taskCategoryAssignments)
        merged.sessions = sessions.mergedByIDLWW(with: other.sessions)
        merged.segments = segments.mergedByIDLWW(with: other.segments)
        merged.pomodoroRuns = pomodoroRuns.mergedByIDLWW(with: other.pomodoroRuns)
        merged.countdownEvents = countdownEvents.mergedByIDLWW(with: other.countdownEvents)
        merged.syncedPreferences = Self.mergingSyncedPreferences(
            syncedPreferences,
            with: other.syncedPreferences
        )
        merged.checklistItems = checklistItems.mergedByIDLWW(with: other.checklistItems)
        merged.checklistItemVisuals = checklistItemVisuals.mergedByIDLWW(with: other.checklistItemVisuals)
        merged.inboxItems = inboxItems.mergedByIDLWW(with: other.inboxItems)
        merged.inboxSuggestions = inboxSuggestions.mergedByIDLWW(with: other.inboxSuggestions)
        merged.inboxCaptureReceipts = Self.mergingOptionalTable(
            inboxCaptureReceipts,
            with: other.inboxCaptureReceipts
        )
        merged.taskRecurrenceRules = Self.mergingOptionalTable(
            taskRecurrenceRules,
            with: other.taskRecurrenceRules
        )
        merged.taskRecurrenceOccurrences = Self.mergingOptionalTable(
            taskRecurrenceOccurrences,
            with: other.taskRecurrenceOccurrences
        )
        merged.taskQuantityGoals = Self.mergingOptionalTable(
            taskQuantityGoals,
            with: other.taskQuantityGoals
        )
        merged.taskQuantityEntries = Self.mergingOptionalTable(
            taskQuantityEntries,
            with: other.taskQuantityEntries
        )
        return merged
    }

    private static func mergingOptionalTable<Record: SyncSnapshotLWWMergeableRecord>(
        _ lhs: [Record]?,
        with rhs: [Record]?
    ) -> [Record]? {
        guard lhs != nil || rhs != nil else { return nil }
        return (lhs ?? []).mergedByIDLWW(with: rhs ?? [])
    }

    /// Preferences sync by logical key: the same setting can exist under
    /// different physical ids on two devices, so merge picks one LWW winner
    /// per key instead of unioning by id.
    private static func mergingSyncedPreferences(
        _ lhs: [SyncedPreferenceRecord],
        with rhs: [SyncedPreferenceRecord]
    ) -> [SyncedPreferenceRecord] {
        var winnerByKey: [String: SyncedPreferenceRecord] = [:]
        winnerByKey.reserveCapacity(lhs.count + rhs.count)
        for record in lhs + rhs {
            if let current = winnerByKey[record.key] {
                winnerByKey[record.key] = record.isPreferredMergeWinner(over: current) ? record : current
            } else {
                winnerByKey[record.key] = record
            }
        }
        return Array(winnerByKey.values).sortedByID()
    }
}

extension TaskRecord: SyncSnapshotLWWMergeableRecord {}
extension TaskCategoryRecord: SyncSnapshotLWWMergeableRecord {}
extension TaskCategoryAssignmentRecord: SyncSnapshotLWWMergeableRecord {}
extension TimeSessionRecord: SyncSnapshotLWWMergeableRecord {}
extension TimeSegmentRecord: SyncSnapshotLWWMergeableRecord {}
extension PomodoroRunRecord: SyncSnapshotLWWMergeableRecord {}
extension CountdownEventRecord: SyncSnapshotLWWMergeableRecord {}
extension SyncedPreferenceRecord: SyncSnapshotLWWMergeableRecord {}
extension ChecklistItemRecord: SyncSnapshotLWWMergeableRecord {}
extension ChecklistItemVisualRecord: SyncSnapshotLWWMergeableRecord {}
extension InboxItemRecord: SyncSnapshotLWWMergeableRecord {}
extension InboxCaptureReceiptRecord: SyncSnapshotLWWMergeableRecord {}
extension InboxSuggestionRecord: SyncSnapshotLWWMergeableRecord {}
extension TaskRecurrenceRuleRecord: SyncSnapshotLWWMergeableRecord {}
extension TaskRecurrenceOccurrenceRecord: SyncSnapshotLWWMergeableRecord {}
extension TaskQuantityGoalRecord: SyncSnapshotLWWMergeableRecord {}
extension TaskQuantityEntryRecord: SyncSnapshotLWWMergeableRecord {}
