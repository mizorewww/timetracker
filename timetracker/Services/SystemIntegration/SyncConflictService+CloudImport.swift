import CloudKit
import CoreData
import Foundation
import SwiftData

extension SyncConflictService {
    func handleCloudImport(context: ModelContext) throws -> SyncConflictPrompt? {
        try withExclusiveStateAccess {
            try handleCloudImportWithLockedState(context: context)
        }
    }

    private func handleCloudImportWithLockedState(
        context: ModelContext
    ) throws -> SyncConflictPrompt? {
        guard AppCloudSync.persistenceMode == AppCloudSync.modeICloud else { return nil }
        var state = try loadState()
        state.advanceSyncEpoch()
        if let forcedLocalSnapshot = pendingForcedUploadSnapshotForRestore(from: state) {
            // CloudKit may replay an older remote copy before the explicitly
            // selected local winner's corresponding export is acknowledged.
            try forcedLocalSnapshot.restoreAsLocalWinner(context: context)
            let restoredSnapshot = try SyncDataSnapshot.capture(context: context)
            state.localSnapshot = restoredSnapshot
            state.localFingerprint = try restoredSnapshot.fingerprint()
            state.advanceLocalGeneration()
            state.pendingForcedUploadSnapshot = restoredSnapshot
            try saveState(state)
            return nil
        }
        if prompt(from: state) != nil {
            let previousCloudFingerprint = try state.pendingCloudSnapshot?.fingerprint()
            let importedSnapshot = try SyncDataSnapshot.capture(context: context)
            if var cloudSnapshot = state.pendingCloudSnapshot,
               let workingSnapshot = state.pendingConflictWorkingSnapshot ?? state.pendingCloudSnapshot {
                cloudSnapshot.applyChanges(from: workingSnapshot, to: importedSnapshot)
                state.pendingCloudSnapshot = cloudSnapshot
            }
            state.pendingConflictWorkingSnapshot = importedSnapshot
            if try state.pendingCloudSnapshot?.fingerprint() != previousCloudFingerprint {
                state.rotatePendingConflictIdentity()
            }
            try saveState(state)
            return prompt(from: state)
        }

        let cloudSnapshot = try SyncDataSnapshot.capture(context: context)
        let cloudFingerprint = try cloudSnapshot.fingerprint()
        guard let localSnapshot = state.localSnapshot,
              let localFingerprint = state.localFingerprint else {
            state.acceptCloudSnapshot(cloudSnapshot, fingerprint: cloudFingerprint)
            try saveState(state)
            return nil
        }

        if cloudFingerprint == localFingerprint {
            state.baseFingerprint = cloudFingerprint
            state.baseAcknowledgedGeneration = state.localGeneration
            state.pendingCloudSnapshot = nil
            state.pendingConflictWorkingSnapshot = nil
            try saveState(state)
            return nil
        }

        if let baseFingerprint = state.baseFingerprint {
            if localFingerprint == baseFingerprint {
                state.acceptCloudSnapshot(cloudSnapshot, fingerprint: cloudFingerprint)
                try saveState(state)
                return nil
            }

            if cloudFingerprint == baseFingerprint {
                // The import replayed the accepted baseline while newer local
                // work was still waiting to export. Restore that local branch.
                try localSnapshot.restoreAsLocalWinner(context: context)
                let restoredSnapshot = try SyncDataSnapshot.capture(context: context)
                state.localSnapshot = restoredSnapshot
                state.localFingerprint = try restoredSnapshot.fingerprint()
                state.advanceLocalGeneration()
                try saveState(state)
                return nil
            }

            return try saveConflict(
                localSnapshot: localSnapshot,
                cloudSnapshot: cloudSnapshot,
                state: &state
            )
        }

        if localSnapshot.hasProtectableUserContent {
            return try saveConflict(
                localSnapshot: localSnapshot,
                cloudSnapshot: cloudSnapshot,
                state: &state
            )
        }

        state.acceptCloudSnapshot(cloudSnapshot, fingerprint: cloudFingerprint)
        try saveState(state)
        return nil
    }

    nonisolated static func isConflictLikeCloudError(_ error: Error?) -> Bool {
        guard let error else { return false }
        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain,
           CKError.Code(rawValue: nsError.code) == .serverRecordChanged {
            return true
        }
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSPersistentStoreSaveConflictsError {
            return true
        }
        return nsError.localizedDescription.localizedCaseInsensitiveContains("conflict")
    }

    private func saveConflict(
        localSnapshot: SyncDataSnapshot,
        cloudSnapshot: SyncDataSnapshot,
        state: inout SyncConflictState
    ) throws -> SyncConflictPrompt {
        let conflictID = UUID()
        let detectedAt = Date()
        state.pendingConflictID = conflictID
        state.pendingDetectedAt = detectedAt
        state.pendingCloudSnapshot = cloudSnapshot
        state.pendingConflictWorkingSnapshot = cloudSnapshot
        try saveState(state)
        return SyncConflictPrompt(
            id: conflictID,
            detectedAt: detectedAt,
            localSummary: localSnapshot.localizedSummary,
            cloudSummary: cloudSnapshot.localizedSummary
        )
    }
}
