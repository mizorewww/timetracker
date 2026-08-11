import Foundation

nonisolated struct PreparedSyncConflictSnapshotSlot: Sendable {
    let reference: SyncConflictSnapshotReference
    let data: Data
}

nonisolated struct PreparedSyncConflictStateManifestWrite: Sendable {
    let data: Data
    let manifest: SyncConflictStateManifest
    let snapshotSlots: [PreparedSyncConflictSnapshotSlot]
}

nonisolated extension SyncConflictService {
    func prepareManifestWrite(
        for state: SyncConflictState
    ) throws -> PreparedSyncConflictStateManifestWrite {
        let previousManifest = try existingManifestForWrite()
        var preparedSlots: [PreparedSyncConflictSnapshotSlot] = []
        var referencesByDigest: [String: SyncConflictSnapshotReference] = [:]

        func reference(
            for snapshot: SyncDataSnapshot?,
            preferredSlot: SyncConflictSnapshotStorageSlot
        ) throws -> SyncConflictSnapshotReference? {
            guard let snapshot else { return nil }
            let data = try Self.sortedJSONEncoder().encode(snapshot)
            try validateRecoverySnapshotWriteByteCount(data.count)
            let digest = SyncDataSnapshot.fingerprint(serializedData: data)
            if let prepared = referencesByDigest[digest] {
                return prepared
            }
            if let existing = previousManifest?.snapshotReferences.first(where: {
                $0.sha256 == digest && $0.byteCount == data.count
            }) {
                referencesByDigest[digest] = existing
                return existing
            }

            let reference = try nextSnapshotReference(
                preferredSlot: preferredSlot,
                byteCount: data.count,
                sha256: digest,
                excluding: Set(preparedSlots.map(\.reference))
            )
            referencesByDigest[digest] = reference
            preparedSlots.append(
                PreparedSyncConflictSnapshotSlot(reference: reference, data: data)
            )
            return reference
        }

        let localSnapshotReference = try reference(
            for: state.localSnapshot,
            preferredSlot: .local
        )
        let pendingForcedUploadReference = try reference(
            for: state.pendingForcedUploadSnapshot,
            preferredSlot: .pendingForcedUpload
        )
        let pendingCloudReference = try reference(
            for: state.pendingCloudSnapshot,
            preferredSlot: .pendingCloud
        )
        let pendingConflictWorkingReference = try reference(
            for: state.pendingConflictWorkingSnapshot,
            preferredSlot: .pendingConflictWorking
        )
        let manifest = SyncConflictStateManifest(
            state: state,
            localSnapshot: localSnapshotReference,
            pendingForcedUploadSnapshot: pendingForcedUploadReference,
            pendingCloudSnapshot: pendingCloudReference,
            pendingConflictWorkingSnapshot: pendingConflictWorkingReference
        )
        let data = try Self.sortedJSONEncoder().encode(manifest)
        guard data.count <= localStateByteLimits.maximumStateFileByteCount else {
            throw SyncConflictLocalStateWriteError.stateExceedsMaximumByteCount(
                actualByteCount: data.count,
                maximumByteCount: localStateByteLimits.maximumStateFileByteCount
            )
        }
        return PreparedSyncConflictStateManifestWrite(
            data: data,
            manifest: manifest,
            snapshotSlots: preparedSlots
        )
    }

    func writeSnapshotSlotsWithoutLock(
        _ slots: [PreparedSyncConflictSnapshotSlot]
    ) throws {
        for slot in slots {
            let url = try conflictSnapshotURL(for: slot.reference)
            try localStateFile.write(
                slot.data,
                to: url,
                durableRootURL: stateDurableRootURL(for: url)
            )
        }
    }

    func loadState(from manifest: SyncConflictStateManifest) throws -> SyncConflictState {
        var loadedSnapshots: [SyncConflictSnapshotReference: SyncDataSnapshot] = [:]

        func snapshot(
            for reference: SyncConflictSnapshotReference?
        ) throws -> SyncDataSnapshot? {
            guard let reference else { return nil }
            if let cached = loadedSnapshots[reference] {
                return cached
            }
            let url = try conflictSnapshotURL(for: reference)
            do {
                let data = try Self.boundedData(
                    at: url,
                    maximumByteCount: localStateByteLimits.maximumRecoverySnapshotFileByteCount
                )
                guard data.count == reference.byteCount else {
                    throw SyncConflictStateFileError.corruptStateQuarantined
                }
                guard SyncDataSnapshot.fingerprint(serializedData: data) == reference.sha256 else {
                    throw SyncConflictStateFileError.corruptStateQuarantined
                }
                let decoded = try JSONDecoder().decode(SyncDataSnapshot.self, from: data)
                loadedSnapshots[reference] = decoded
                return decoded
            } catch {
                _ = try? quarantineCorruptFile(
                    at: url,
                    prefix: reference.slot.corruptFilePrefix
                )
                throw SyncConflictStateFileError.corruptStateQuarantined
            }
        }

        return try manifest.state(
            localSnapshot: snapshot(for: manifest.localSnapshot),
            pendingForcedUploadSnapshot: snapshot(for: manifest.pendingForcedUploadSnapshot),
            pendingCloudSnapshot: snapshot(for: manifest.pendingCloudSnapshot),
            pendingConflictWorkingSnapshot: snapshot(
                for: manifest.pendingConflictWorkingSnapshot
            )
        )
    }

    func removeUnreferencedSnapshotSlotsWithoutLock(
        retaining references: Set<SyncConflictSnapshotReference>
    ) throws {
        let resolvedStateURL = try stateURL()
        let directory = resolvedStateURL.deletingLastPathComponent()
        let protectedFileNames = Set(references.map {
            Self.conflictSnapshotURL(
                for: $0,
                stateURL: resolvedStateURL
            ).lastPathComponent
        })
        let fileNames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        for fileName in fileNames
            where Self.isConflictSnapshotSlotFileName(fileName)
            && protectedFileNames.contains(fileName) == false
        {
            // Directory enumeration may return a physical `/private/var` URL
            // even when the state location was obtained as logical `/var`.
            // Rebuild the managed target from the same directory spelling used
            // for the durable root; the controlled filename is its identity.
            let url = directory.appendingPathComponent(fileName)
            try localStateFile.removeIfPresent(
                at: url,
                durableRootURL: stateDurableRootURL(for: url)
            )
        }
    }
}
