import Foundation

extension SyncConflictService {
    func markCloudExportStarted(eventID: UUID, now: Date = Date()) throws {
        try withExclusiveStateAccess {
            try markCloudExportStartedWithLockedState(eventID: eventID, now: now)
        }
    }

    private func markCloudExportStartedWithLockedState(eventID: UUID, now: Date) throws {
        guard AppCloudSync.persistenceMode == AppCloudSync.modeICloud else { return }
        var state = try loadState()
        guard let fingerprint = state.localFingerprint else { return }
        _ = state.pruneCloudExportCheckpoints(now: now)
        var checkpoints = state.pendingCloudExportCheckpoints ?? [:]
        if checkpoints.count >= 16,
           let oldestEventID = checkpoints.min(by: { $0.value.startedAt < $1.value.startedAt })?.key {
            checkpoints.removeValue(forKey: oldestEventID)
        }
        checkpoints[eventID.uuidString] = SyncCloudExportCheckpoint(
            epoch: state.syncEpoch ?? 0,
            generation: state.localGeneration ?? 0,
            fingerprint: fingerprint,
            startedAt: now
        )
        state.pendingCloudExportCheckpoints = checkpoints
        try saveState(state)
    }

    func markCloudExportFinished(eventID: UUID, succeeded: Bool) throws {
        try withExclusiveStateAccess {
            try markCloudExportFinishedWithLockedState(eventID: eventID, succeeded: succeeded)
        }
    }

    private func markCloudExportFinishedWithLockedState(eventID: UUID, succeeded: Bool) throws {
        guard AppCloudSync.persistenceMode == AppCloudSync.modeICloud else { return }
        var state = try loadState()
        var checkpoints = state.pendingCloudExportCheckpoints ?? [:]
        guard let checkpoint = checkpoints.removeValue(forKey: eventID.uuidString) else { return }
        state.pendingCloudExportCheckpoints = checkpoints.isEmpty ? nil : checkpoints

        guard succeeded,
              checkpoint.epoch == (state.syncEpoch ?? 0),
              checkpoint.generation >= (state.baseAcknowledgedGeneration ?? 0) else {
            try saveState(state)
            return
        }

        // Only this event's generation is known to be remote. Newer local
        // generations remain dirty; older completions cannot move base back.
        state.baseFingerprint = checkpoint.fingerprint
        state.baseAcknowledgedGeneration = checkpoint.generation

        if let pendingSnapshot = state.pendingForcedUploadSnapshot,
           try pendingSnapshot.fingerprint() == checkpoint.fingerprint {
            state.pendingForcedUploadSnapshot = nil
        }
        try saveState(state)
    }
}
