import Foundation

nonisolated enum InboxPersistenceField: Equatable {
    case itemTitle
    case notes
    case suggestionReason
    case iconName
    case colorHex
    case modelID
    case titleSnapshot

    var localizationKey: String {
        switch self {
        case .itemTitle:
            "inbox.persistence.field.title"
        case .notes:
            "inbox.persistence.field.notes"
        case .suggestionReason:
            "inbox.persistence.field.reason"
        case .iconName:
            "inbox.persistence.field.symbol"
        case .colorHex:
            "inbox.persistence.field.color"
        case .modelID:
            "inbox.persistence.field.model"
        case .titleSnapshot:
            "inbox.persistence.field.titleSnapshot"
        }
    }
}

enum InboxPersistenceValidationError: LocalizedError, Equatable {
    case required(field: InboxPersistenceField)
    case controlCharacter(field: InboxPersistenceField)
    case byteLimitExceeded(field: InboxPersistenceField, actual: Int, maximum: Int)

    var errorDescription: String? {
        let field: InboxPersistenceField
        let formatKey: String
        switch self {
        case let .required(value):
            field = value
            formatKey = "inbox.persistence.error.requiredFormat"
        case let .controlCharacter(value):
            field = value
            formatKey = "inbox.persistence.error.controlCharacterFormat"
        case let .byteLimitExceeded(value, _, _):
            field = value
            formatKey = "inbox.persistence.error.tooLongFormat"
        }
        return String(
            format: AppStrings.localized(formatKey),
            AppStrings.localized(field.localizationKey)
        )
    }
}

struct PreparedInboxItemText {
    let title: String
    let notes: String?
    let suggestionReason: String?

    @MainActor
    func apply(to item: InboxItem) {
        item.title = title
        item.notes = notes
        item.suggestionReason = suggestionReason
    }
}

struct PreparedInboxSuggestionText {
    let reason: String?
    let iconName: String
    let colorHex: String
    let modelID: String?
    let titleSnapshot: String

    @MainActor
    func apply(to suggestion: InboxSuggestion) {
        suggestion.reason = reason
        suggestion.iconName = iconName
        suggestion.colorHex = colorHex
        suggestion.modelID = modelID
        suggestion.titleSnapshot = titleSnapshot
    }
}

@MainActor
struct PreparedInboxSuggestionMutation {
    let suggestion: InboxSuggestion
    let text: PreparedInboxSuggestionText
}

enum InboxPersistencePolicy {
    static func prepareItem(
        title: String,
        notes: String?,
        suggestionReason: String?
    ) throws -> PreparedInboxItemText {
        PreparedInboxItemText(
            title: try requiredSingleLine(
                title,
                field: .itemTitle,
                maximum: SyncDataSnapshotRestoreLimits.maximumTitleByteCount
            ),
            notes: try optionalMultiline(
                notes,
                field: .notes,
                trimsOuterWhitespace: false
            ),
            suggestionReason: try optionalMultiline(
                suggestionReason,
                field: .suggestionReason,
                trimsOuterWhitespace: true
            )
        )
    }

    static func prepareSuggestion(
        reason: String?,
        iconName: String,
        colorHex: String,
        modelID: String?,
        titleSnapshot: String
    ) throws -> PreparedInboxSuggestionText {
        let preparedIconName = try optionalSingleLine(iconName, field: .iconName)
        let preparedColorHex = try optionalSingleLine(colorHex, field: .colorHex)
        return PreparedInboxSuggestionText(
            reason: try optionalMultiline(
                reason,
                field: .suggestionReason,
                trimsOuterWhitespace: true
            ),
            iconName: ChecklistVisualSanitizer.sanitizedIcon(preparedIconName),
            colorHex: ChecklistVisualSanitizer.sanitizedColor(preparedColorHex),
            modelID: try optionalSingleLine(modelID, field: .modelID),
            titleSnapshot: try requiredSingleLine(
                titleSnapshot,
                field: .titleSnapshot,
                maximum: SyncDataSnapshotRestoreLimits.maximumTitleByteCount
            )
        )
    }

    private static func requiredSingleLine(
        _ value: String,
        field: InboxPersistenceField,
        maximum: Int
    ) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InboxPersistenceValidationError.required(field: field)
        }
        try rejectUnsupportedControls(
            in: trimmed,
            field: field,
            allowsMultilineWhitespace: false
        )
        try enforceByteLimit(trimmed, maximum: maximum, field: field)
        return trimmed
    }

    private static func optionalSingleLine(
        _ value: String?,
        field: InboxPersistenceField
    ) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        try rejectUnsupportedControls(
            in: trimmed,
            field: field,
            allowsMultilineWhitespace: false
        )
        try enforceByteLimit(
            trimmed,
            maximum: SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount,
            field: field
        )
        return trimmed
    }

    private static func optionalMultiline(
        _ value: String?,
        field: InboxPersistenceField,
        trimsOuterWhitespace: Bool
    ) throws -> String? {
        guard let value else { return nil }
        let prepared = trimsOuterWhitespace
            ? value.trimmingCharacters(in: .whitespacesAndNewlines)
            : value
        guard !prepared.isEmpty else { return nil }
        try rejectUnsupportedControls(
            in: prepared,
            field: field,
            allowsMultilineWhitespace: true
        )
        try enforceByteLimit(
            prepared,
            maximum: SyncDataSnapshotRestoreLimits.maximumNoteByteCount,
            field: field
        )
        return prepared
    }

    private static func rejectUnsupportedControls(
        in value: String,
        field: InboxPersistenceField,
        allowsMultilineWhitespace: Bool
    ) throws {
        let containsUnsupportedControl = value.unicodeScalars.contains { scalar in
            guard CharacterSet.controlCharacters.contains(scalar) else { return false }
            if allowsMultilineWhitespace,
               scalar.value == 9 || scalar.value == 10 || scalar.value == 13 {
                return false
            }
            return true
        }
        guard !containsUnsupportedControl else {
            throw InboxPersistenceValidationError.controlCharacter(field: field)
        }
    }

    private static func enforceByteLimit(
        _ value: String,
        maximum: Int,
        field: InboxPersistenceField
    ) throws {
        let actual = value.utf8.count
        guard actual <= maximum else {
            throw InboxPersistenceValidationError.byteLimitExceeded(
                field: field,
                actual: actual,
                maximum: maximum
            )
        }
    }
}
