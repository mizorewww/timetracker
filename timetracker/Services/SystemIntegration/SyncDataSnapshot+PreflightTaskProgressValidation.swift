import Foundation

extension SyncDataSnapshot {
    func requireCanonicalDayKey(
        _ value: String,
        table: SyncSnapshotTable,
        id: UUID,
        field: String
    ) throws {
        guard TaskRecurrenceDayKey.isCanonical(value) else {
            throw invalidTaskProgressRawValue(
                table: table,
                id: id,
                field: field,
                value: value
            )
        }
    }

    func requireQuantityValue(
        _ value: Int,
        table: SyncSnapshotTable,
        id: UUID,
        field: String
    ) throws {
        guard TaskQuantityPolicy.valueRange.contains(value) else {
            throw SyncDataSnapshotPreflightError.invalidInteger(
                table: table,
                id: id,
                field: field,
                value: value,
                allowed: "\(TaskQuantityPolicy.valueRange)"
            )
        }
    }

    func requireMaximumBytes(
        _ value: String,
        maximum: Int,
        table: SyncSnapshotTable,
        id: UUID,
        field: String
    ) throws {
        let actual = value.utf8.count
        guard actual <= maximum else {
            throw SyncDataSnapshotPreflightError.fieldByteLimitExceeded(
                table: table,
                id: id,
                field: field,
                actual: actual,
                maximum: maximum
            )
        }
    }

    func invalidTaskProgressRawValue(
        table: SyncSnapshotTable,
        id: UUID,
        field: String,
        value: String
    ) -> SyncDataSnapshotPreflightError {
        .invalidRawValue(
            table: table,
            id: id,
            field: field,
            value: value
        )
    }
}
