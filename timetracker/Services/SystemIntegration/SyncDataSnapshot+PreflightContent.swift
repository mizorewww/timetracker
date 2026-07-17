import Foundation

struct SyncSnapshotContentValidator {
    private var totalTextByteCount = 0

    mutating func validate(snapshot: SyncDataSnapshot) throws {
        try validateTasks(snapshot)
        try validateLedger(snapshot)
        try validatePlanning(snapshot)
        try validatePreferences(snapshot)
        try validateChecklist(snapshot)
        try validateInbox(snapshot)
    }

    private mutating func validateTasks(_ snapshot: SyncDataSnapshot) throws {
        for record in snapshot.tasks {
            try text(record.title, maximum: .title, table: .tasks, id: record.id, field: "title")
            try text(record.kindRaw, maximum: .compact, table: .tasks, id: record.id, field: "kindRaw")
            try text(record.path, maximum: .title, table: .tasks, id: record.id, field: "path")
            try text(record.statusRaw, maximum: .compact, table: .tasks, id: record.id, field: "statusRaw")
            try text(record.colorHex, maximum: .compact, table: .tasks, id: record.id, field: "colorHex")
            try text(record.iconName, maximum: .compact, table: .tasks, id: record.id, field: "iconName")
            try text(record.notes, maximum: .note, table: .tasks, id: record.id, field: "notes")
            try sortable(record.sortOrder, table: .tasks, id: record.id, field: "sortOrder")
            try dates(
                [
                    ("dueAt", record.dueAt),
                    ("createdAt", record.createdAt),
                    ("updatedAt", record.updatedAt),
                    ("archivedAt", record.archivedAt),
                    ("deletedAt", record.deletedAt)
                ],
                table: .tasks,
                id: record.id
            )
        }

        for record in snapshot.taskCategories {
            try text(record.title, maximum: .title, table: .taskCategories, id: record.id, field: "title")
            try text(record.colorHex, maximum: .compact, table: .taskCategories, id: record.id, field: "colorHex")
            try text(record.iconName, maximum: .compact, table: .taskCategories, id: record.id, field: "iconName")
            try sortable(record.sortOrder, table: .taskCategories, id: record.id, field: "sortOrder")
            try dates(
                [("createdAt", record.createdAt), ("updatedAt", record.updatedAt), ("deletedAt", record.deletedAt)],
                table: .taskCategories,
                id: record.id
            )
        }

        for record in snapshot.taskCategoryAssignments {
            try dates(
                [("createdAt", record.createdAt), ("updatedAt", record.updatedAt), ("deletedAt", record.deletedAt)],
                table: .taskCategoryAssignments,
                id: record.id
            )
        }
    }

    private mutating func validateLedger(_ snapshot: SyncDataSnapshot) throws {
        for record in snapshot.sessions {
            try text(record.titleSnapshot, maximum: .title, table: .sessions, id: record.id, field: "titleSnapshot")
            try text(record.sourceRaw, maximum: .compact, table: .sessions, id: record.id, field: "sourceRaw")
            try text(record.note, maximum: .note, table: .sessions, id: record.id, field: "note")
            try dates(
                [
                    ("startedAt", record.startedAt),
                    ("endedAt", record.endedAt),
                    ("createdAt", record.createdAt),
                    ("updatedAt", record.updatedAt),
                    ("deletedAt", record.deletedAt)
                ],
                table: .sessions,
                id: record.id
            )
        }

        for record in snapshot.segments {
            try text(record.sourceRaw, maximum: .compact, table: .segments, id: record.id, field: "sourceRaw")
            try dates(
                [
                    ("startedAt", record.startedAt),
                    ("endedAt", record.endedAt),
                    ("createdAt", record.createdAt),
                    ("updatedAt", record.updatedAt),
                    ("deletedAt", record.deletedAt)
                ],
                table: .segments,
                id: record.id
            )
        }
    }

    private mutating func validatePlanning(_ snapshot: SyncDataSnapshot) throws {
        for record in snapshot.pomodoroRuns {
            try text(record.stateRaw, maximum: .compact, table: .pomodoroRuns, id: record.id, field: "stateRaw")
            try dates(
                [
                    ("startedAt", record.startedAt),
                    ("endedAt", record.endedAt),
                    ("createdAt", record.createdAt),
                    ("updatedAt", record.updatedAt),
                    ("deletedAt", record.deletedAt)
                ],
                table: .pomodoroRuns,
                id: record.id
            )
        }

        for record in snapshot.countdownEvents {
            try text(record.title, maximum: .title, table: .countdownEvents, id: record.id, field: "title")
            try dates(
                [
                    ("date", record.date),
                    ("createdAt", record.createdAt),
                    ("updatedAt", record.updatedAt),
                    ("deletedAt", record.deletedAt)
                ],
                table: .countdownEvents,
                id: record.id
            )
        }
    }

    private mutating func validatePreferences(_ snapshot: SyncDataSnapshot) throws {
        for record in snapshot.syncedPreferences {
            try text(record.key, maximum: .compact, table: .syncedPreferences, id: record.id, field: "key")
            try text(
                record.valueJSON,
                maximum: .preferenceValue,
                table: .syncedPreferences,
                id: record.id,
                field: "valueJSON"
            )
            try dates(
                [("createdAt", record.createdAt), ("updatedAt", record.updatedAt), ("deletedAt", record.deletedAt)],
                table: .syncedPreferences,
                id: record.id
            )
        }
    }

    private mutating func validateChecklist(_ snapshot: SyncDataSnapshot) throws {
        for record in snapshot.checklistItems {
            try text(record.title, maximum: .title, table: .checklistItems, id: record.id, field: "title")
            try sortable(record.sortOrder, table: .checklistItems, id: record.id, field: "sortOrder")
            try dates(
                [
                    ("completedAt", record.completedAt),
                    ("createdAt", record.createdAt),
                    ("updatedAt", record.updatedAt),
                    ("deletedAt", record.deletedAt)
                ],
                table: .checklistItems,
                id: record.id
            )
        }

        for record in snapshot.checklistItemVisuals {
            try text(record.iconName, maximum: .compact, table: .checklistItemVisuals, id: record.id, field: "iconName")
            try text(record.colorHex, maximum: .compact, table: .checklistItemVisuals, id: record.id, field: "colorHex")
            try text(
                record.suggestionTitleSnapshot,
                maximum: .title,
                table: .checklistItemVisuals,
                id: record.id,
                field: "suggestionTitleSnapshot"
            )
            try text(
                record.suggestionModelID,
                maximum: .compact,
                table: .checklistItemVisuals,
                id: record.id,
                field: "suggestionModelID"
            )
            try dates(
                [
                    ("suggestionGeneratedAt", record.suggestionGeneratedAt),
                    ("userEditedAt", record.userEditedAt),
                    ("createdAt", record.createdAt),
                    ("updatedAt", record.updatedAt),
                    ("deletedAt", record.deletedAt)
                ],
                table: .checklistItemVisuals,
                id: record.id
            )
        }
    }

    private mutating func validateInbox(_ snapshot: SyncDataSnapshot) throws {
        for record in snapshot.inboxItems {
            try text(record.title, maximum: .title, table: .inboxItems, id: record.id, field: "title")
            try text(record.notes, maximum: .note, table: .inboxItems, id: record.id, field: "notes")
            try text(
                record.suggestionReason,
                maximum: .note,
                table: .inboxItems,
                id: record.id,
                field: "suggestionReason"
            )
            try sortable(record.sortOrder, table: .inboxItems, id: record.id, field: "sortOrder")
            try dates(
                [
                    ("completedAt", record.completedAt),
                    ("suggestionGeneratedAt", record.suggestionGeneratedAt),
                    ("createdAt", record.createdAt),
                    ("updatedAt", record.updatedAt),
                    ("deletedAt", record.deletedAt)
                ],
                table: .inboxItems,
                id: record.id
            )
        }

        for record in snapshot.inboxSuggestions {
            try text(record.reason, maximum: .note, table: .inboxSuggestions, id: record.id, field: "reason")
            try text(record.iconName, maximum: .compact, table: .inboxSuggestions, id: record.id, field: "iconName")
            try text(record.colorHex, maximum: .compact, table: .inboxSuggestions, id: record.id, field: "colorHex")
            try text(record.modelID, maximum: .compact, table: .inboxSuggestions, id: record.id, field: "modelID")
            try text(
                record.titleSnapshot,
                maximum: .title,
                table: .inboxSuggestions,
                id: record.id,
                field: "titleSnapshot"
            )
            try dates(
                [
                    ("generatedAt", record.generatedAt),
                    ("createdAt", record.createdAt),
                    ("updatedAt", record.updatedAt),
                    ("deletedAt", record.deletedAt)
                ],
                table: .inboxSuggestions,
                id: record.id
            )
        }

        for record in snapshot.inboxCaptureReceipts ?? [] {
            try text(
                record.commandKey,
                maximum: .compact,
                table: .inboxCaptureReceipts,
                id: record.id,
                field: "commandKey"
            )
            try text(
                record.payloadFingerprint,
                maximum: .compact,
                table: .inboxCaptureReceipts,
                id: record.id,
                field: "payloadFingerprint"
            )
            try dates(
                [
                    ("createdAt", record.createdAt),
                    ("updatedAt", record.updatedAt),
                    ("deletedAt", record.deletedAt)
                ],
                table: .inboxCaptureReceipts,
                id: record.id
            )
        }
    }
}

private extension SyncSnapshotContentValidator {
    enum TextLimit {
        case title
        case note
        case compact
        case preferenceValue

        var byteCount: Int {
            switch self {
            case .title: SyncDataSnapshotRestoreLimits.maximumTitleByteCount
            case .note: SyncDataSnapshotRestoreLimits.maximumNoteByteCount
            case .compact: SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount
            case .preferenceValue: SyncDataSnapshotRestoreLimits.maximumPreferenceValueByteCount
            }
        }
    }

    mutating func text(
        _ value: String?,
        maximum: TextLimit,
        table: SyncSnapshotTable,
        id: UUID,
        field: String
    ) throws {
        guard let value else { return }
        let byteCount = value.utf8.count
        guard byteCount <= maximum.byteCount else {
            throw SyncDataSnapshotPreflightError.fieldByteLimitExceeded(
                table: table,
                id: id,
                field: field,
                actual: byteCount,
                maximum: maximum.byteCount
            )
        }
        totalTextByteCount += byteCount
        guard totalTextByteCount <= SyncDataSnapshotRestoreLimits.maximumTotalTextByteCount else {
            throw SyncDataSnapshotPreflightError.totalTextByteLimitExceeded(
                actual: totalTextByteCount,
                maximum: SyncDataSnapshotRestoreLimits.maximumTotalTextByteCount
            )
        }
    }

    func sortable(
        _ value: Double,
        table: SyncSnapshotTable,
        id: UUID,
        field: String
    ) throws {
        guard value.isFinite else {
            throw SyncDataSnapshotPreflightError.nonFiniteNumber(table: table, id: id, field: field)
        }
        let nextValue = value + 10
        guard nextValue.isFinite, nextValue > value else {
            throw SyncDataSnapshotPreflightError.sortOrderCannotAdvance(table: table, id: id, field: field)
        }
    }

    func dates(
        _ values: [(String, Date?)],
        table: SyncSnapshotTable,
        id: UUID
    ) throws {
        for (field, value) in values {
            guard let value else { continue }
            let interval = value.timeIntervalSinceReferenceDate
            guard interval.isFinite,
                  value >= SyncDataSnapshotRestoreLimits.minimumDate,
                  value < SyncDataSnapshotRestoreLimits.maximumDateExclusive else {
                throw SyncDataSnapshotPreflightError.invalidDate(table: table, id: id, field: field)
            }
        }
    }
}
