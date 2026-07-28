import Foundation

enum SyncConflictStateFileError: LocalizedError {
    case corruptStateQuarantined

    var errorDescription: String? {
        switch self {
        case .corruptStateQuarantined:
            AppStrings.localized("sync.state.corruptRecovered")
        }
    }
}

enum SyncConflictError: LocalizedError {
    case localSnapshotMissing
    case cloudSnapshotMissing
    case uploadSnapshotMissing
    case cloudRecoveryAlreadyInProgress

    var errorDescription: String? {
        switch self {
        case .localSnapshotMissing:
            AppStrings.localized("sync.conflict.error.localSnapshotMissing")
        case .cloudSnapshotMissing:
            AppStrings.localized("sync.conflict.error.cloudSnapshotMissing")
        case .uploadSnapshotMissing:
            AppStrings.localized("sync.conflict.error.uploadSnapshotMissing")
        case .cloudRecoveryAlreadyInProgress:
            AppStrings.localized("sync.conflict.error.recoveryInProgress")
        }
    }
}

struct SyncCloudExportCheckpoint: Codable, Equatable {
    let epoch: UInt64
    let generation: UInt64
    let fingerprint: String
    let startedAt: Date
}

enum SyncPendingLocalIntent: String, Codable, Equatable {
    case reconcileWithCloud
    case explicitlyReplaceCloud
}

enum CloudRecoveryImportKind: String, Codable, Equatable {
    case reconcileWithCloud
    case downloadCloud
}

struct CloudRecoveryContainerEventReceipt: Equatable {
    enum EventKind: Equatable {
        case setup
        case `import`
        case export
    }

    let storeIdentifier: String
    let kind: EventKind
    let startedAt: Date
    let completedAt: Date
    let succeeded: Bool
}

struct CloudRecoveryImportSession: Codable, Equatable {
    let id: UUID
    let kind: CloudRecoveryImportKind
    let startedAt: Date
    var storeIdentifier: String? = nil
    var setupCompletedAt: Date? = nil
    var initialImportCompletedAt: Date? = nil

    var hasCompletedInitialImport: Bool {
        storeIdentifier != nil &&
            setupCompletedAt != nil &&
            initialImportCompletedAt != nil
    }

    mutating func record(_ receipt: CloudRecoveryContainerEventReceipt) {
        guard receipt.succeeded,
              receipt.startedAt >= startedAt
        else {
            return
        }

        switch receipt.kind {
        case .setup:
            guard storeIdentifier == nil || storeIdentifier == receipt.storeIdentifier else {
                return
            }
            storeIdentifier = receipt.storeIdentifier
            setupCompletedAt = receipt.completedAt
        case .import:
            guard storeIdentifier == receipt.storeIdentifier,
                  let setupCompletedAt,
                  receipt.startedAt >= setupCompletedAt
            else {
                return
            }
            initialImportCompletedAt = receipt.completedAt
        case .export:
            return
        }
    }
}

struct SyncConflictState: Codable, Equatable {
    var baseFingerprint: String?
    var localSnapshot: SyncDataSnapshot?
    var localFingerprint: String?
    var pendingForcedUploadSnapshot: SyncDataSnapshot?
    var pendingLocalIntent: SyncPendingLocalIntent?
    var pendingConflictID: UUID?
    var pendingDetectedAt: Date?
    var pendingCloudSnapshot: SyncDataSnapshot?
    var pendingConflictWorkingSnapshot: SyncDataSnapshot?
    var cloudDownloadRecoveryCompleted: Bool?
    var cloudRecoveryImportSession: CloudRecoveryImportSession?
    var syncEpoch: UInt64?
    var localGeneration: UInt64?
    var baseAcknowledgedGeneration: UInt64?
    /// Lightweight generation checkpoints; full user snapshots are never
    /// duplicated per CloudKit event.
    var pendingCloudExportCheckpoints: [String: SyncCloudExportCheckpoint]?

    mutating func advanceSyncEpoch() {
        syncEpoch = (syncEpoch ?? 0) &+ 1
        localGeneration = 0
        baseAcknowledgedGeneration = nil
        pendingCloudExportCheckpoints = nil
    }

    mutating func clearPendingConflict() {
        pendingConflictID = nil
        pendingDetectedAt = nil
        pendingCloudSnapshot = nil
        pendingConflictWorkingSnapshot = nil
    }

    mutating func clearPendingLocalRecovery() {
        pendingForcedUploadSnapshot = nil
        pendingLocalIntent = nil
    }

    mutating func clearCloudRecoveryImportSession() {
        cloudRecoveryImportSession = nil
    }

    mutating func rotatePendingConflictIdentity() {
        guard pendingConflictID != nil else { return }
        pendingConflictID = UUID()
    }

    mutating func acceptCloudSnapshot(
        _ snapshot: SyncDataSnapshot,
        fingerprint: String
    ) {
        localSnapshot = snapshot
        localFingerprint = fingerprint
        baseFingerprint = fingerprint
        baseAcknowledgedGeneration = localGeneration
    }

    @discardableResult
    mutating func advanceLocalGeneration() -> UInt64 {
        let next = (localGeneration ?? 0) &+ 1
        localGeneration = next
        return next
    }

    mutating func pruneCloudExportCheckpoints(
        now: Date = Date(),
        maximumAge: TimeInterval = 24 * 60 * 60,
        maximumCount: Int = 16
    ) -> Bool {
        let original = pendingCloudExportCheckpoints ?? [:]
        let cutoff = now.addingTimeInterval(-maximumAge)
        let currentEpoch = syncEpoch ?? 0
        let retained = original
            .filter { $0.value.epoch == currentEpoch && $0.value.startedAt >= cutoff }
            .sorted { $0.value.startedAt > $1.value.startedAt }
            .prefix(max(0, maximumCount))
        let pruned = Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
        pendingCloudExportCheckpoints = pruned.isEmpty ? nil : pruned
        return pruned != original
    }

    mutating func removeExcludedPreferences() throws -> Bool {
        let localWasBase = localFingerprint != nil && localFingerprint == baseFingerprint
        var changed = false

        if var snapshot = localSnapshot, snapshot.removeExcludedPreferences() {
            localSnapshot = snapshot
            localFingerprint = try snapshot.fingerprint()
            baseFingerprint = localWasBase ? localFingerprint : nil
            // Any in-flight checkpoint fingerprints the legacy payload. It
            // must not be allowed to restore an excluded preference fingerprint
            // after this one-time state migration has completed.
            pendingCloudExportCheckpoints = nil
            changed = true
        }
        if var snapshot = pendingForcedUploadSnapshot, snapshot.removeExcludedPreferences() {
            pendingForcedUploadSnapshot = snapshot
            changed = true
        }
        if var snapshot = pendingCloudSnapshot, snapshot.removeExcludedPreferences() {
            pendingCloudSnapshot = snapshot
            changed = true
        }
        if var snapshot = pendingConflictWorkingSnapshot, snapshot.removeExcludedPreferences() {
            pendingConflictWorkingSnapshot = snapshot
            changed = true
        }
        return changed
    }
}

struct SyncDataExport: Encodable {
    let format = "timetracker.cloudSyncedData"
    let schemaVersion = 1
    let exportedAt: Date
    let appVersion: String
    let data: SyncDataSnapshot
}
