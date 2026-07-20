import Foundation

extension SyncSnapshotContentValidator {
    mutating func validateTaskProgress(
        _ snapshot: SyncDataSnapshot
    ) throws {
        for record in snapshot.taskRecurrenceRules ?? [] {
            try text(
                record.cadenceRaw,
                maximum: .compact,
                table: .taskRecurrenceRules,
                id: record.id,
                field: "cadenceRaw"
            )
            try text(
                record.startDayKey,
                maximum: .compact,
                table: .taskRecurrenceRules,
                id: record.id,
                field: "startDayKey"
            )
            try text(
                record.timeZoneIdentifier,
                maximum: .compact,
                table: .taskRecurrenceRules,
                id: record.id,
                field: "timeZoneIdentifier"
            )
            try dates(
                [
                    ("createdAt", record.createdAt),
                    ("updatedAt", record.updatedAt),
                    ("deletedAt", record.deletedAt),
                ],
                table: .taskRecurrenceRules,
                id: record.id
            )
        }

        for record in snapshot.taskRecurrenceOccurrences ?? [] {
            try text(
                record.occurrenceDayKey,
                maximum: .compact,
                table: .taskRecurrenceOccurrences,
                id: record.id,
                field: "occurrenceDayKey"
            )
            try text(
                record.timeZoneIdentifier,
                maximum: .compact,
                table: .taskRecurrenceOccurrences,
                id: record.id,
                field: "timeZoneIdentifier"
            )
            try dates(
                [
                    ("createdAt", record.createdAt),
                    ("updatedAt", record.updatedAt),
                    ("deletedAt", record.deletedAt),
                ],
                table: .taskRecurrenceOccurrences,
                id: record.id
            )
        }

        for record in snapshot.taskQuantityGoals ?? [] {
            try text(
                record.unitLabel,
                maximum: .compact,
                table: .taskQuantityGoals,
                id: record.id,
                field: "unitLabel"
            )
            try dates(
                [
                    ("createdAt", record.createdAt),
                    ("updatedAt", record.updatedAt),
                    ("deletedAt", record.deletedAt),
                ],
                table: .taskQuantityGoals,
                id: record.id
            )
        }

        for record in snapshot.taskQuantityEntries ?? [] {
            try dates(
                [
                    ("recordedAt", record.recordedAt),
                    ("createdAt", record.createdAt),
                    ("updatedAt", record.updatedAt),
                    ("deletedAt", record.deletedAt),
                ],
                table: .taskQuantityEntries,
                id: record.id
            )
        }
    }
}
