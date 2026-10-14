import Foundation

/// UTF-8 byte ceilings for persisted user text, enforced at each write policy.
nonisolated enum PersistedFieldLimits {
    static let maximumTitleByteCount = 4 * 1024
    static let maximumNoteByteCount = 64 * 1024
    static let maximumCompactFieldByteCount = 256
}
