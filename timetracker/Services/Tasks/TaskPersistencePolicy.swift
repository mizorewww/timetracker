import Foundation

nonisolated enum TaskPersistenceField: Equatable {
    case taskTitle
    case categoryTitle
    case notes
    case iconName
    case colorHex

    var localizationKey: String {
        switch self {
        case .taskTitle:
            "persistence.field.taskName"
        case .categoryTitle:
            "persistence.field.categoryName"
        case .notes:
            "persistence.field.notes"
        case .iconName:
            "persistence.field.symbol"
        case .colorHex:
            "persistence.field.color"
        }
    }
}

nonisolated enum TaskPersistenceValidationError: LocalizedError, Equatable {
    case required(field: TaskPersistenceField)
    case controlCharacter(field: TaskPersistenceField)
    case byteLimitExceeded(field: TaskPersistenceField, actual: Int, maximum: Int)

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

nonisolated struct PreparedTaskPersistenceValues {
    let title: String
    let colorHex: String?
    let iconName: String?
    let notes: String?
}

nonisolated enum TaskPersistencePolicy {
    static func taskTitleValidationError(for title: String) -> TaskPersistenceValidationError? {
        validationError {
            _ = try requiredSingleLine(title, field: .taskTitle)
        }
    }

    static func taskNotesValidationError(for notes: String?) -> TaskPersistenceValidationError? {
        validationError {
            _ = try optionalMultiline(notes, field: .notes)
        }
    }

    static func taskIconNameValidationError(for iconName: String?) -> TaskPersistenceValidationError? {
        validationError {
            _ = try optionalSingleLine(iconName, field: .iconName)
        }
    }

    static func taskColorHexValidationError(for colorHex: String?) -> TaskPersistenceValidationError? {
        validationError {
            _ = try optionalSingleLine(colorHex, field: .colorHex)
        }
    }

    static func prepareTask(
        title: String,
        colorHex: String?,
        iconName: String?,
        notes: String?
    ) throws -> PreparedTaskPersistenceValues {
        try PreparedTaskPersistenceValues(
            title: requiredSingleLine(title, field: .taskTitle),
            colorHex: optionalSingleLine(colorHex, field: .colorHex),
            iconName: optionalSingleLine(iconName, field: .iconName),
            notes: optionalMultiline(notes, field: .notes)
        )
    }

    static func prepareCategory(
        title: String,
        colorHex: String?,
        iconName: String?
    ) throws -> PreparedTaskPersistenceValues {
        try PreparedTaskPersistenceValues(
            title: requiredSingleLine(title, field: .categoryTitle),
            colorHex: optionalSingleLine(colorHex, field: .colorHex),
            iconName: optionalSingleLine(iconName, field: .iconName),
            notes: nil
        )
    }

    private static func requiredSingleLine(
        _ value: String,
        field: TaskPersistenceField
    ) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TaskPersistenceValidationError.required(field: field)
        }
        try rejectUnsupportedControls(in: trimmed, field: field, allowsMultilineWhitespace: false)
        try enforceByteLimit(
            trimmed,
            maximum: SyncDataSnapshotRestoreLimits.maximumTitleByteCount,
            field: field
        )
        return trimmed
    }

    private static func optionalSingleLine(
        _ value: String?,
        field: TaskPersistenceField
    ) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        try rejectUnsupportedControls(in: trimmed, field: field, allowsMultilineWhitespace: false)
        try enforceByteLimit(
            trimmed,
            maximum: SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount,
            field: field
        )
        return trimmed
    }

    private static func optionalMultiline(
        _ value: String?,
        field: TaskPersistenceField
    ) throws -> String? {
        guard let value else { return nil }
        try rejectUnsupportedControls(in: value, field: field, allowsMultilineWhitespace: true)
        try enforceByteLimit(
            value,
            maximum: SyncDataSnapshotRestoreLimits.maximumNoteByteCount,
            field: field
        )
        return value
    }

    private static func rejectUnsupportedControls(
        in value: String,
        field: TaskPersistenceField,
        allowsMultilineWhitespace: Bool
    ) throws {
        let containsUnsupportedControl = value.unicodeScalars.contains { scalar in
            guard CharacterSet.controlCharacters.contains(scalar) else { return false }
            if allowsMultilineWhitespace,
               scalar.value == 9 || scalar.value == 10 || scalar.value == 13
            {
                return false
            }
            return true
        }
        guard !containsUnsupportedControl else {
            throw TaskPersistenceValidationError.controlCharacter(field: field)
        }
    }

    private static func enforceByteLimit(
        _ value: String,
        maximum: Int,
        field: TaskPersistenceField
    ) throws {
        let actual = value.utf8.count
        guard actual <= maximum else {
            throw TaskPersistenceValidationError.byteLimitExceeded(
                field: field,
                actual: actual,
                maximum: maximum
            )
        }
    }

    private static func validationError(
        _ validate: () throws -> Void
    ) -> TaskPersistenceValidationError? {
        do {
            try validate()
            return nil
        } catch let error as TaskPersistenceValidationError {
            return error
        } catch {
            assertionFailure("Task persistence validation threw an unexpected error: \(error)")
            return nil
        }
    }
}
