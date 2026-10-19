import Foundation

/// A persisted user-text field, named in validation messages.
nonisolated enum PersistedField: Equatable {
    case taskTitle
    case categoryTitle
    case notes
    case iconName
    case colorHex
    case inboxTitle
    case inboxNotes
    case suggestionReason
    case suggestionIcon
    case suggestionColor
    case suggestionModel
    case suggestionTitle
    case ledgerNote
    case ledgerTitleSnapshot

    var localizationKey: String {
        switch self {
        case .taskTitle: "persistence.field.taskName"
        case .categoryTitle: "persistence.field.categoryName"
        case .notes: "persistence.field.notes"
        case .iconName: "persistence.field.symbol"
        case .colorHex: "persistence.field.color"
        case .inboxTitle: "inbox.persistence.field.title"
        case .inboxNotes: "inbox.persistence.field.notes"
        case .suggestionReason: "inbox.persistence.field.reason"
        case .suggestionIcon: "inbox.persistence.field.symbol"
        case .suggestionColor: "inbox.persistence.field.color"
        case .suggestionModel: "inbox.persistence.field.model"
        case .suggestionTitle: "inbox.persistence.field.titleSnapshot"
        case .ledgerNote: "ledger.persistence.field.note"
        case .ledgerTitleSnapshot: "ledger.persistence.field.titleSnapshot"
        }
    }
}

nonisolated enum PersistedFieldValidationError: LocalizedError, Equatable {
    case required(field: PersistedField)
    case controlCharacter(field: PersistedField)
    case byteLimitExceeded(field: PersistedField, actual: Int, maximum: Int)

    var errorDescription: String? {
        switch self {
        case let .required(field):
            String.localizedStringWithFormat(
                AppStrings.localized("persistence.error.requiredFormat"),
                AppStrings.localized(field.localizationKey)
            )
        case let .controlCharacter(field):
            String.localizedStringWithFormat(
                AppStrings.localized("persistence.error.controlCharacterFormat"),
                AppStrings.localized(field.localizationKey)
            )
        case let .byteLimitExceeded(field, actual, maximum):
            String.localizedStringWithFormat(
                AppStrings.localized("persistence.error.tooLongFormat"),
                AppStrings.localized(field.localizationKey),
                Int64(actual),
                Int64(maximum)
            )
        }
    }
}

/// The one write-side validator for persisted user text: control characters
/// and UTF-8 byte ceilings (`PersistedFieldLimits`).
nonisolated enum PersistedFieldValidator {
    /// Trimmed, non-empty, single-line text.
    static func requiredSingleLine(
        _ value: String,
        field: PersistedField,
        maximum: Int = PersistedFieldLimits.maximumTitleByteCount
    ) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PersistedFieldValidationError.required(field: field)
        }
        try validate(trimmed, field: field, maximum: maximum, allowsMultilineWhitespace: false)
        return trimmed
    }

    /// Trimmed single-line text; empty input becomes `nil`.
    static func optionalSingleLine(
        _ value: String?,
        field: PersistedField,
        maximum: Int = PersistedFieldLimits.maximumCompactFieldByteCount
    ) throws -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        try validate(trimmed, field: field, maximum: maximum, allowsMultilineWhitespace: false)
        return trimmed
    }

    /// Multiline text (tab, newline, and carriage return allowed); empty input
    /// becomes `nil`.
    static func optionalMultiline(
        _ value: String?,
        field: PersistedField,
        trimsOuterWhitespace: Bool,
        maximum: Int = PersistedFieldLimits.maximumNoteByteCount
    ) throws -> String? {
        guard let value else { return nil }
        let prepared = trimsOuterWhitespace
            ? value.trimmingCharacters(in: .whitespacesAndNewlines)
            : value
        guard !prepared.isEmpty else { return nil }
        try validate(prepared, field: field, maximum: maximum, allowsMultilineWhitespace: true)
        return prepared
    }

    static func validate(
        _ value: String,
        field: PersistedField,
        maximum: Int,
        allowsMultilineWhitespace: Bool
    ) throws {
        guard !containsUnsupportedControl(
            value,
            allowsMultilineWhitespace: allowsMultilineWhitespace
        ) else {
            throw PersistedFieldValidationError.controlCharacter(field: field)
        }
        let actual = value.utf8.count
        guard actual <= maximum else {
            throw PersistedFieldValidationError.byteLimitExceeded(
                field: field,
                actual: actual,
                maximum: maximum
            )
        }
    }

    static func containsUnsupportedControl(
        _ value: String,
        allowsMultilineWhitespace: Bool
    ) -> Bool {
        value.unicodeScalars.contains { scalar in
            guard CharacterSet.controlCharacters.contains(scalar) else { return false }
            return !(allowsMultilineWhitespace && (scalar == "\t" || scalar == "\n" || scalar == "\r"))
        }
    }
}
