import Foundation

enum SyncSnapshotTable: String, Equatable {
    case tasks
    case taskCategories
    case taskCategoryAssignments
    case sessions
    case segments
    case pomodoroRuns
    case countdownEvents
    case syncedPreferences
    case checklistItems
    case checklistItemVisuals
    case inboxItems
    case inboxSuggestions
    case inboxCaptureReceipts
    case taskRecurrenceRules
    case taskRecurrenceOccurrences
    case taskQuantityGoals
    case taskQuantityEntries
}

enum SyncDataSnapshotPreflightError: LocalizedError, Equatable {
    case tableRecordLimitExceeded(table: SyncSnapshotTable, actual: Int, maximum: Int)
    case totalRecordLimitExceeded(actual: Int, maximum: Int)
    case duplicateIdentifier(table: SyncSnapshotTable, id: UUID)
    case fieldByteLimitExceeded(
        table: SyncSnapshotTable,
        id: UUID,
        field: String,
        actual: Int,
        maximum: Int
    )
    case invalidRawValue(table: SyncSnapshotTable, id: UUID, field: String, value: String)
    case invalidInteger(
        table: SyncSnapshotTable,
        id: UUID,
        field: String,
        value: Int,
        allowed: String
    )
    case invalidPreferenceKey(id: UUID, key: String)
    case invalidPreferenceValue(id: UUID, key: String)
    case inconsistentSessionTask(
        table: SyncSnapshotTable,
        id: UUID,
        sessionID: UUID,
        expectedTaskID: UUID,
        actualTaskID: UUID
    )
    case inconsistentInboxSuggestionIdentity(id: UUID, inboxItemID: UUID)
    case inconsistentInboxCaptureReceipt(id: UUID, inboxItemID: UUID)
    case inconsistentInboxCaptureCommandKey(commandKey: String)
    case nonCanonicalIdentity(
        table: SyncSnapshotTable,
        id: UUID,
        expectedID: UUID
    )
    case mismatchedReference(
        table: SyncSnapshotTable,
        id: UUID,
        field: String,
        expectedID: UUID,
        actualID: UUID?
    )
    case inconsistentStringValue(
        table: SyncSnapshotTable,
        id: UUID,
        field: String,
        expected: String,
        actual: String
    )

    var errorDescription: String? {
        switch self {
        case let .tableRecordLimitExceeded(table, actual, maximum):
            return "Sync snapshot table \(table.rawValue) has \(actual) records; maximum is \(maximum)."
        case let .totalRecordLimitExceeded(actual, maximum):
            return "Sync snapshot has \(actual) records; maximum is \(maximum)."
        case let .duplicateIdentifier(table, id):
            return "Sync snapshot table \(table.rawValue) repeats identifier \(id.uuidString)."
        case let .fieldByteLimitExceeded(table, id, field, actual, maximum):
            return "Sync snapshot \(table.rawValue).\(field) for \(id.uuidString) is \(actual) UTF-8 bytes; maximum is \(maximum)."
        case let .invalidRawValue(table, id, field, value):
            return "Sync snapshot \(table.rawValue).\(field) for \(id.uuidString) has unsupported value '\(value)'."
        case let .invalidInteger(table, id, field, value, allowed):
            return "Sync snapshot \(table.rawValue).\(field) for \(id.uuidString) is \(value); expected \(allowed)."
        case let .invalidPreferenceKey(id, key):
            return "Sync snapshot preference key '\(key)' for \(id.uuidString) is empty or contains control characters."
        case let .invalidPreferenceValue(id, key):
            return "Sync snapshot preference \(key) for \(id.uuidString) does not contain the expected JSON value type."
        case let .inconsistentSessionTask(table, id, sessionID, expectedTaskID, actualTaskID):
            return "Sync snapshot \(table.rawValue) record \(id.uuidString) references session \(sessionID.uuidString) for task \(expectedTaskID.uuidString), not \(actualTaskID.uuidString)."
        case let .inconsistentInboxSuggestionIdentity(id, inboxItemID):
            return "Sync snapshot Inbox suggestion \(id.uuidString) disagrees with Inbox item \(inboxItemID.uuidString) about logical suggestion identity."
        case let .inconsistentInboxCaptureReceipt(id, inboxItemID):
            return "Sync snapshot Inbox capture receipt \(id.uuidString) references missing Inbox item \(inboxItemID.uuidString)."
        case let .inconsistentInboxCaptureCommandKey(commandKey):
            return "Sync snapshot Inbox capture receipts disagree about the committed result for external command key '\(commandKey)'."
        case let .nonCanonicalIdentity(table, id, expectedID):
            return "Sync snapshot \(table.rawValue) identifier \(id.uuidString) is not canonical; expected \(expectedID.uuidString)."
        case let .mismatchedReference(table, id, field, expectedID, actualID):
            let actual = actualID?.uuidString ?? "nil"
            return "Sync snapshot \(table.rawValue).\(field) for \(id.uuidString) is \(actual); expected \(expectedID.uuidString)."
        case let .inconsistentStringValue(table, id, field, expected, actual):
            return "Sync snapshot \(table.rawValue).\(field) for \(id.uuidString) is '\(actual)'; expected \(expected)."
        }
    }
}

nonisolated enum SyncDataSnapshotRestoreLimits {
    static let maximumRecordsPerTable = 100_000
    static let maximumTotalRecords = 250_000
    static let maximumTitleByteCount = 4 * 1024
    static let maximumNoteByteCount = 64 * 1024
    static let maximumCompactFieldByteCount = 256
}

extension SyncDataSnapshot {
    func validateForRestore() throws {
        try validateRecordCounts()
        try validateUniqueIdentifiers()
        try validateRestoreSemantics()
    }

    private func validateRecordCounts() throws {
        let tableCounts: [(SyncSnapshotTable, Int)] = [
            (.tasks, tasks.count),
            (.taskCategories, taskCategories.count),
            (.taskCategoryAssignments, taskCategoryAssignments.count),
            (.sessions, sessions.count),
            (.segments, segments.count),
            (.pomodoroRuns, pomodoroRuns.count),
            (.countdownEvents, countdownEvents.count),
            (.syncedPreferences, syncedPreferences.count),
            (.checklistItems, checklistItems.count),
            (.checklistItemVisuals, checklistItemVisuals.count),
            (.inboxItems, inboxItems.count),
            (.inboxSuggestions, inboxSuggestions.count),
            (.inboxCaptureReceipts, (inboxCaptureReceipts ?? []).count),
            (.taskRecurrenceRules, (taskRecurrenceRules ?? []).count),
            (.taskRecurrenceOccurrences, (taskRecurrenceOccurrences ?? []).count),
            (.taskQuantityGoals, (taskQuantityGoals ?? []).count),
            (.taskQuantityEntries, (taskQuantityEntries ?? []).count),
        ]

        for (table, count) in tableCounts where count > SyncDataSnapshotRestoreLimits.maximumRecordsPerTable {
            throw SyncDataSnapshotPreflightError.tableRecordLimitExceeded(
                table: table,
                actual: count,
                maximum: SyncDataSnapshotRestoreLimits.maximumRecordsPerTable
            )
        }

        let totalCount = tableCounts.reduce(into: 0) { $0 += $1.1 }
        guard totalCount <= SyncDataSnapshotRestoreLimits.maximumTotalRecords else {
            throw SyncDataSnapshotPreflightError.totalRecordLimitExceeded(
                actual: totalCount,
                maximum: SyncDataSnapshotRestoreLimits.maximumTotalRecords
            )
        }
    }

    private func validateUniqueIdentifiers() throws {
        try requireUniqueIdentifiers(tasks, table: .tasks)
        try requireUniqueIdentifiers(taskCategories, table: .taskCategories)
        try requireUniqueIdentifiers(taskCategoryAssignments, table: .taskCategoryAssignments)
        try requireUniqueIdentifiers(sessions, table: .sessions)
        try requireUniqueIdentifiers(segments, table: .segments)
        try requireUniqueIdentifiers(pomodoroRuns, table: .pomodoroRuns)
        try requireUniqueIdentifiers(countdownEvents, table: .countdownEvents)
        try requireUniqueIdentifiers(syncedPreferences, table: .syncedPreferences)
        try requireUniqueIdentifiers(checklistItems, table: .checklistItems)
        try requireUniqueIdentifiers(checklistItemVisuals, table: .checklistItemVisuals)
        try requireUniqueIdentifiers(inboxItems, table: .inboxItems)
        try requireUniqueIdentifiers(inboxSuggestions, table: .inboxSuggestions)
        try requireUniqueIdentifiers(inboxCaptureReceipts ?? [], table: .inboxCaptureReceipts)
        try requireUniqueIdentifiers(taskRecurrenceRules ?? [], table: .taskRecurrenceRules)
        try requireUniqueIdentifiers(
            taskRecurrenceOccurrences ?? [],
            table: .taskRecurrenceOccurrences
        )
        try requireUniqueIdentifiers(taskQuantityGoals ?? [], table: .taskQuantityGoals)
        try requireUniqueIdentifiers(taskQuantityEntries ?? [], table: .taskQuantityEntries)
    }

    private func requireUniqueIdentifiers<Record: SyncSnapshotRecord>(
        _ records: [Record],
        table: SyncSnapshotTable
    ) throws {
        var identifiers = Set<UUID>()
        identifiers.reserveCapacity(records.count)
        for record in records where !identifiers.insert(record.id).inserted {
            throw SyncDataSnapshotPreflightError.duplicateIdentifier(table: table, id: record.id)
        }
    }
}
