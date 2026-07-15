import Foundation
import SwiftData

enum SyncSnapshotDomain: CaseIterable, Hashable {
    case tasks
    case ledger
    case pomodoro
    case countdown
    case preferences
    case checklist
    case inbox
}

@MainActor
struct SyncConflictService {
    nonisolated static let stateFileName = "SyncConflictState.json"
    nonisolated static let pendingForcedUploadSnapshotFileName = "PendingForcedUploadSnapshot.json"
    nonisolated static let stateDirectoryName = "TimeTrackerSync"
    nonisolated static let corruptStateFilePrefix = "SyncConflictState.corrupt-"
    nonisolated static let corruptPendingSnapshotFilePrefix = "PendingForcedUploadSnapshot.corrupt-"
    nonisolated let stateURLOverride: URL?

    init(stateURL: URL? = nil) {
        self.stateURLOverride = stateURL
    }

    func bootstrap(context: ModelContext) throws -> SyncConflictPrompt? {
        try withExclusiveStateAccess {
            try bootstrapWithLockedState(context: context)
        }
    }

    private func bootstrapWithLockedState(context: ModelContext) throws -> SyncConflictPrompt? {
        var state = try loadState()
        if let pendingSnapshot = pendingForcedUploadSnapshotForRestore(from: state) {
            try pendingSnapshot.restoreAsLocalWinner(context: context)
            let uploadedSnapshot = try SyncDataSnapshot.capture(context: context)
            let fingerprint = try uploadedSnapshot.fingerprint()
            state.advanceSyncEpoch()
            state.advanceLocalGeneration()
            state.localSnapshot = uploadedSnapshot
            state.localFingerprint = fingerprint
            state.pendingForcedUploadSnapshot = uploadedSnapshot

            if AppCloudSync.persistenceMode == AppCloudSync.modeICloud {
                // Restoring the local winner only queues a CloudKit export. It
                // is not an accepted base until that exact export completes.
                state.clearPendingConflict()
            }
            try saveState(state)
            return nil
        }

        if let prompt = prompt(from: state) {
            return prompt
        }
        guard AppCloudSync.persistenceMode == AppCloudSync.modeICloud else { return nil }
        guard state.localSnapshot == nil else { return nil }

        let snapshot = try SyncDataSnapshot.capture(context: context)
        state.localSnapshot = snapshot
        state.localFingerprint = try snapshot.fingerprint()
        state.localGeneration = state.localGeneration ?? 0
        if !snapshot.hasProtectableUserContent {
            state.baseFingerprint = state.localFingerprint
            state.baseAcknowledgedGeneration = state.localGeneration
        }
        try saveState(state)
        return nil
    }

    func prompt() -> SyncConflictPrompt? {
        guard let state = try? loadState() else { return nil }
        return prompt(from: state)
    }

    static func hasDefaultPendingForcedUploadBackup() -> Bool {
        let service = SyncConflictService()
        if let snapshot = try? service.loadPendingForcedUploadSnapshot() {
            return snapshot.hasProtectableUserContent
        }
        // A corrupt authoritative state is quarantined by the failed load.
        // Keep the independent recovery mirror usable for this launch.
        guard let url = try? defaultPendingForcedUploadSnapshotURL(),
              let fallbackSnapshot = try? loadPendingForcedUploadSnapshot(at: url) else {
            return false
        }
        return fallbackSnapshot.hasProtectableUserContent
    }

    func pendingForcedUploadSnapshotForRestore(
        from state: SyncConflictState
    ) -> SyncDataSnapshot? {
        guard let snapshot = state.pendingForcedUploadSnapshot,
              snapshot.hasProtectableUserContent else {
            return nil
        }
        return snapshot
    }

    func prompt(from state: SyncConflictState) -> SyncConflictPrompt? {
        guard let id = state.pendingConflictID,
              let detectedAt = state.pendingDetectedAt,
              let localSnapshot = state.localSnapshot,
              let cloudSnapshot = state.pendingCloudSnapshot else {
            return nil
        }
        return SyncConflictPrompt(
            id: id,
            detectedAt: detectedAt,
            localSummary: localSnapshot.localizedSummary,
            cloudSummary: cloudSnapshot.localizedSummary
        )
    }
}
