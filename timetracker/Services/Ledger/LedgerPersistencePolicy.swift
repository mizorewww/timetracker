import Foundation

enum LedgerPersistencePolicy {
    static let maximumTitleSnapshotByteCount = PersistedFieldLimits.maximumTitleByteCount
    static let maximumNoteByteCount = PersistedFieldLimits.maximumNoteByteCount

    static func prepareNote(_ value: String?) throws -> String? {
        try PersistedFieldValidator.optionalMultiline(
            value,
            field: .ledgerNote,
            trimsOuterWhitespace: true,
            maximum: maximumNoteByteCount
        )
    }

    /// Title snapshots keep their exact text; only control characters and
    /// the byte ceiling are rejected.
    static func prepareTitleSnapshot(_ value: String?) throws -> String? {
        guard let value else { return nil }
        try PersistedFieldValidator.validate(
            value,
            field: .ledgerTitleSnapshot,
            maximum: maximumTitleSnapshotByteCount,
            allowsMultilineWhitespace: false
        )
        return value
    }
}
