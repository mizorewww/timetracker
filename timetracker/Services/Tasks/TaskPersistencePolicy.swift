import Foundation

nonisolated struct PreparedTaskPersistenceValues {
    let title: String
    let colorHex: String?
    let iconName: String?
    let notes: String?
}

nonisolated enum TaskPersistencePolicy {
    static func taskTitleValidationError(for title: String) -> PersistedFieldValidationError? {
        validationError {
            _ = try requiredSingleLine(title, field: .taskTitle)
        }
    }

    static func taskNotesValidationError(for notes: String?) -> PersistedFieldValidationError? {
        validationError {
            _ = try optionalMultiline(notes, field: .notes)
        }
    }

    static func taskIconNameValidationError(for iconName: String?) -> PersistedFieldValidationError? {
        validationError {
            _ = try optionalSingleLine(iconName, field: .iconName)
        }
    }

    static func taskColorHexValidationError(for colorHex: String?) -> PersistedFieldValidationError? {
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
        field: PersistedField
    ) throws -> String {
        try PersistedFieldValidator.requiredSingleLine(value, field: field)
    }

    private static func optionalSingleLine(
        _ value: String?,
        field: PersistedField
    ) throws -> String? {
        try PersistedFieldValidator.optionalSingleLine(value, field: field)
    }

    /// Notes keep their exact text, including surrounding whitespace.
    private static func optionalMultiline(
        _ value: String?,
        field: PersistedField
    ) throws -> String? {
        guard let value else { return nil }
        try PersistedFieldValidator.validate(
            value,
            field: field,
            maximum: PersistedFieldLimits.maximumNoteByteCount,
            allowsMultilineWhitespace: true
        )
        return value
    }

    private static func validationError(
        _ validate: () throws -> Void
    ) -> PersistedFieldValidationError? {
        do {
            try validate()
            return nil
        } catch let error as PersistedFieldValidationError {
            return error
        } catch {
            assertionFailure("Task persistence validation threw an unexpected error: \(error)")
            return nil
        }
    }
}
