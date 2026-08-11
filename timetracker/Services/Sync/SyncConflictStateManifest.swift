import Foundation

nonisolated enum SyncConflictSnapshotStorageSlot:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Sendable
{
    case local
    case pendingForcedUpload
    case pendingCloud
    case pendingConflictWorking

    var fileStem: String {
        switch self {
        case .local: "LocalSnapshot"
        case .pendingForcedUpload: "PendingForcedUploadSnapshot"
        case .pendingCloud: "PendingCloudSnapshot"
        case .pendingConflictWorking: "PendingConflictWorkingSnapshot"
        }
    }

    var corruptFilePrefix: String {
        "\(fileStem).corrupt-"
    }
}

nonisolated struct SyncConflictSnapshotReference:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    let slot: SyncConflictSnapshotStorageSlot
    let generation: Int
    let byteCount: Int
    let sha256: String

    init(
        slot: SyncConflictSnapshotStorageSlot,
        generation: Int,
        byteCount: Int,
        sha256: String
    ) {
        precondition((0 ... 1).contains(generation))
        self.slot = slot
        self.generation = generation
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    private enum CodingKeys: String, CodingKey {
        case slot
        case generation
        case byteCount
        case sha256
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let slot = try values.decode(SyncConflictSnapshotStorageSlot.self, forKey: .slot)
        let generation = try values.decode(Int.self, forKey: .generation)
        let byteCount = try values.decode(Int.self, forKey: .byteCount)
        let sha256 = try values.decode(String.self, forKey: .sha256)
        guard (0 ... 1).contains(generation),
              byteCount >= 0,
              sha256.utf8.count == 64,
              sha256.unicodeScalars.allSatisfy({ scalar in
                  switch scalar.value {
                  case 48 ... 57, 97 ... 102: true
                  default: false
                  }
              })
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .generation,
                in: values,
                debugDescription: "Invalid sync conflict snapshot reference"
            )
        }
        self.slot = slot
        self.generation = generation
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

/// The on-disk authority is deliberately a small manifest. Runtime callers
/// continue to use `SyncConflictState`, whose snapshots are materialized from
/// bounded A/B slot files after this manifest has been validated.
nonisolated struct SyncConflictStateManifest: Codable, Sendable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let baseFingerprint: String?
    let localFingerprint: String?
    let pendingLocalIntent: SyncPendingLocalIntent?
    let pendingConflictID: UUID?
    let pendingDetectedAt: Date?
    let cloudDownloadRecoveryCompleted: Bool?
    let cloudRecoveryImportSession: CloudRecoveryImportSession?
    let syncEpoch: UInt64?
    let localGeneration: UInt64?
    let baseAcknowledgedGeneration: UInt64?
    let pendingCloudExportCheckpoints: [String: SyncCloudExportCheckpoint]?
    let localSnapshot: SyncConflictSnapshotReference?
    let pendingForcedUploadSnapshot: SyncConflictSnapshotReference?
    let pendingCloudSnapshot: SyncConflictSnapshotReference?
    let pendingConflictWorkingSnapshot: SyncConflictSnapshotReference?

    init(
        state: SyncConflictState,
        localSnapshot: SyncConflictSnapshotReference?,
        pendingForcedUploadSnapshot: SyncConflictSnapshotReference?,
        pendingCloudSnapshot: SyncConflictSnapshotReference?,
        pendingConflictWorkingSnapshot: SyncConflictSnapshotReference?
    ) {
        formatVersion = Self.currentFormatVersion
        baseFingerprint = state.baseFingerprint
        localFingerprint = state.localFingerprint
        pendingLocalIntent = state.pendingLocalIntent
        pendingConflictID = state.pendingConflictID
        pendingDetectedAt = state.pendingDetectedAt
        cloudDownloadRecoveryCompleted = state.cloudDownloadRecoveryCompleted
        cloudRecoveryImportSession = state.cloudRecoveryImportSession
        syncEpoch = state.syncEpoch
        localGeneration = state.localGeneration
        baseAcknowledgedGeneration = state.baseAcknowledgedGeneration
        pendingCloudExportCheckpoints = state.pendingCloudExportCheckpoints
        self.localSnapshot = localSnapshot
        self.pendingForcedUploadSnapshot = pendingForcedUploadSnapshot
        self.pendingCloudSnapshot = pendingCloudSnapshot
        self.pendingConflictWorkingSnapshot = pendingConflictWorkingSnapshot
    }

    func state(
        localSnapshot: SyncDataSnapshot?,
        pendingForcedUploadSnapshot: SyncDataSnapshot?,
        pendingCloudSnapshot: SyncDataSnapshot?,
        pendingConflictWorkingSnapshot: SyncDataSnapshot?
    ) -> SyncConflictState {
        SyncConflictState(
            baseFingerprint: baseFingerprint,
            localSnapshot: localSnapshot,
            localFingerprint: localFingerprint,
            pendingForcedUploadSnapshot: pendingForcedUploadSnapshot,
            pendingLocalIntent: pendingLocalIntent,
            pendingConflictID: pendingConflictID,
            pendingDetectedAt: pendingDetectedAt,
            pendingCloudSnapshot: pendingCloudSnapshot,
            pendingConflictWorkingSnapshot: pendingConflictWorkingSnapshot,
            cloudDownloadRecoveryCompleted: cloudDownloadRecoveryCompleted,
            cloudRecoveryImportSession: cloudRecoveryImportSession,
            syncEpoch: syncEpoch,
            localGeneration: localGeneration,
            baseAcknowledgedGeneration: baseAcknowledgedGeneration,
            pendingCloudExportCheckpoints: pendingCloudExportCheckpoints
        )
    }

    var snapshotReferences: Set<SyncConflictSnapshotReference> {
        [
            localSnapshot,
            pendingForcedUploadSnapshot,
            pendingCloudSnapshot,
            pendingConflictWorkingSnapshot,
        ].reduce(into: Set<SyncConflictSnapshotReference>()) { references, reference in
            if let reference {
                references.insert(reference)
            }
        }
    }
}
