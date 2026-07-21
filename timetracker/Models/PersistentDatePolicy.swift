import Foundation

/// Date bounds shared by local mutations and sync snapshot restoration.
/// Keeping persisted dates inside this interval guarantees a locally accepted
/// record can complete a backup/export/restore round trip.
nonisolated enum PersistentDatePolicy {
    static let minimumDate = Date(
        timeIntervalSince1970: -2_208_988_800
    )
    static let maximumDateExclusive = Date(
        timeIntervalSince1970: 7_289_654_400
    )

    static func contains(_ date: Date) -> Bool {
        date >= minimumDate && date < maximumDateExclusive
    }
}
