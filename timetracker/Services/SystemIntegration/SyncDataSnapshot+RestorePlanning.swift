import Foundation
import SwiftData

@MainActor
extension SyncDataSnapshot {
    func restorePomodoroRuns(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = try context.fetch(FetchDescriptor<PomodoroRun>())
            .latestByIDMarkingDuplicatesDeleted(now: now, deviceID: deviceID)
        let snapshotIDs = Set(pomodoroRuns.map(\.id))
        for run in existing.values where !snapshotIDs.contains(run.id) {
            run.deletedAt = now
            run.updatedAt = now
            run.deviceID = deviceID
            run.clientMutationID = UUID()
        }
        for record in pomodoroRuns {
            let focusSeconds = max(1, record.focusSecondsPlanned)
            let breakSeconds = max(1, record.breakSecondsPlanned)
            let longBreakSeconds = record.longBreakSecondsPlanned.map { max(1, $0) }
            let targetRounds = record.targetRounds.clamped(to: PomodoroPlan.roundRange)
            let model = existing[record.id] ?? PomodoroRun(
                taskID: record.taskID,
                focus: focusSeconds,
                breakSeconds: breakSeconds,
                longBreakSeconds: longBreakSeconds,
                targetRounds: targetRounds,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.taskID = record.taskID
            model.sessionID = record.sessionID
            model.focusSecondsPlanned = focusSeconds
            model.breakSecondsPlanned = breakSeconds
            model.longBreakSecondsPlanned = longBreakSeconds
            model.stateRaw = record.stateRaw
            model.startedAt = record.startedAt
            model.endedAt = record.endedAt
            model.completedFocusRounds = min(
                max(0, record.completedFocusRounds),
                targetRounds
            )
            model.targetRounds = targetRounds
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    func restoreCountdownEvents(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = try context.fetch(FetchDescriptor<CountdownEvent>())
            .latestByIDMarkingDuplicatesDeleted(now: now, deviceID: deviceID)
        let snapshotIDs = Set(countdownEvents.map(\.id))
        for event in existing.values where !snapshotIDs.contains(event.id) {
            event.deletedAt = now
            event.updatedAt = now
            event.deviceID = deviceID
            event.clientMutationID = UUID()
        }
        for record in countdownEvents {
            let model = existing[record.id] ?? CountdownEvent(
                title: record.title,
                date: record.date,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.title = record.title
            model.date = record.date
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    func restoreSyncedPreferences(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = try context.fetch(FetchDescriptor<SyncedPreference>())
            .latestByIDMarkingDuplicatesDeleted(now: now, deviceID: deviceID)
        let safeRecords = syncedPreferences.filter {
            SyncedPreferenceService.shouldSyncKey($0.key)
        }
        let snapshotIDs = Set(safeRecords.map(\.id))
        let logicalWinnerIDs = logicalSyncedPreferenceWinnerIDs(in: safeRecords)
        // Rows missing from the snapshot must remain older than the restored
        // logical winner. A same-key tombstone at `now` would otherwise hide
        // the snapshot's active value after both receive the same timestamp.
        let supersededAt = now.addingTimeInterval(-1)
        for preference in existing.values where !snapshotIDs.contains(preference.id) {
            preference.deletedAt = supersededAt
            preference.updatedAt = supersededAt
            preference.deviceID = deviceID
            preference.clientMutationID = UUID()
        }
        for record in safeRecords {
            let model = existing[record.id] ?? SyncedPreference(
                key: record.key,
                valueJSON: record.valueJSON,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.key = record.key
            model.valueJSON = record.valueJSON
            model.createdAt = record.createdAt
            // Preserve ordering between physical siblings of the same logical
            // key. Only the source winner becomes the new local write.
            model.updatedAt = logicalWinnerIDs.contains(record.id)
                ? max(record.updatedAt, now)
                : record.updatedAt
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = record.id
        }
    }

    private func logicalSyncedPreferenceWinnerIDs(
        in records: [SyncedPreferenceRecord]
    ) -> Set<UUID> {
        var winnersByKey: [String: SyncedPreferenceRecord] = [:]
        winnersByKey.reserveCapacity(records.count)
        for record in records {
            guard let current = winnersByKey[record.key] else {
                winnersByKey[record.key] = record
                continue
            }
            if record.updatedAt > current.updatedAt ||
                (record.updatedAt == current.updatedAt &&
                    record.deletedAt != nil && current.deletedAt == nil) ||
                (record.updatedAt == current.updatedAt &&
                    (record.deletedAt == nil) == (current.deletedAt == nil) &&
                    (record.createdAt > current.createdAt ||
                        (record.createdAt == current.createdAt &&
                            record.id.uuidString > current.id.uuidString)))
            {
                winnersByKey[record.key] = record
            }
        }
        return Set(winnersByKey.values.map(\.id))
    }
}
