import Foundation

nonisolated enum LedgerPersistenceField: Equatable {
    case note
    case titleSnapshot

    var localizationKey: String {
        switch self {
        case .note:
            "ledger.persistence.field.note"
        case .titleSnapshot:
            "ledger.persistence.field.titleSnapshot"
        }
    }
}

enum LedgerPersistenceValidationError: LocalizedError, Equatable {
    case controlCharacter(field: LedgerPersistenceField)
    case byteLimitExceeded(
        field: LedgerPersistenceField,
        actual: Int,
        maximum: Int
    )

    var errorDescription: String? {
        switch self {
        case let .controlCharacter(field):
            String(
                format: AppStrings.localized("ledger.persistence.error.controlCharacterFormat"),
                AppStrings.localized(field.localizationKey)
            )
        case let .byteLimitExceeded(field, _, _):
            String(
                format: AppStrings.localized("ledger.persistence.error.tooLongFormat"),
                AppStrings.localized(field.localizationKey)
            )
        }
    }
}

enum LedgerPersistencePolicy {
    static let maximumTitleSnapshotByteCount = SyncDataSnapshotRestoreLimits.maximumTitleByteCount
    static let maximumNoteByteCount = SyncDataSnapshotRestoreLimits.maximumNoteByteCount

    static func prepareNote(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let prepared = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prepared.isEmpty else { return nil }
        try validate(
            prepared,
            field: .note,
            maximumByteCount: maximumNoteByteCount,
            allowedControlScalars: ["\t", "\n", "\r"]
        )
        return prepared
    }

    static func prepareTitleSnapshot(_ value: String?) throws -> String? {
        guard let value else { return nil }
        try validate(
            value,
            field: .titleSnapshot,
            maximumByteCount: maximumTitleSnapshotByteCount,
            allowedControlScalars: []
        )
        return value
    }

    private static func validate(
        _ value: String,
        field: LedgerPersistenceField,
        maximumByteCount: Int,
        allowedControlScalars: Set<Unicode.Scalar>
    ) throws {
        if value.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) && !allowedControlScalars.contains($0)
        }) {
            throw LedgerPersistenceValidationError.controlCharacter(field: field)
        }

        let actual = value.utf8.count
        guard actual <= maximumByteCount else {
            throw LedgerPersistenceValidationError.byteLimitExceeded(
                field: field,
                actual: actual,
                maximum: maximumByteCount
            )
        }
    }
}
