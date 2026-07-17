import Foundation

extension SyncConflictService {
    nonisolated func conflictSnapshotURL(
        for reference: SyncConflictSnapshotReference
    ) throws -> URL {
        Self.conflictSnapshotURL(for: reference, stateURL: try stateURL())
    }

    nonisolated static func conflictSnapshotURL(
        for reference: SyncConflictSnapshotReference,
        stateURL: URL
    ) -> URL {
        stateURL.deletingLastPathComponent().appendingPathComponent(
            "\(reference.slot.fileStem)-\(reference.generation).json"
        )
    }

    nonisolated static func allConflictSnapshotSlotURLs(for stateURL: URL) -> [URL] {
        SyncConflictSnapshotStorageSlot.allCases.flatMap { slot in
            (0...1).map { generation in
                conflictSnapshotURL(
                    for: SyncConflictSnapshotReference(
                        slot: slot,
                        generation: generation,
                        byteCount: 0,
                        sha256: ""
                    ),
                    stateURL: stateURL
                )
            }
        }
    }

    nonisolated static func isConflictSnapshotSlotURL(_ url: URL) -> Bool {
        SyncConflictSnapshotStorageSlot.allCases.contains { slot in
            (0...1).contains { generation in
                url.lastPathComponent == "\(slot.fileStem)-\(generation).json"
            }
        }
    }

    func existingManifestForWrite() throws -> SyncConflictStateManifest? {
        let url = try stateURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Self.boundedData(
            at: url,
            maximumByteCount: Self.maximumStateFileByteCount
        )
        return try? JSONDecoder().decode(SyncConflictStateManifest.self, from: data)
    }

    func nextSnapshotReference(
        preferredSlot: SyncConflictSnapshotStorageSlot,
        byteCount: Int,
        sha256: String,
        excluding preparedReferences: Set<SyncConflictSnapshotReference>
    ) throws -> SyncConflictSnapshotReference {
        let usedReferences = try existingManifestForWrite()?.snapshotReferences
            ?? Set<SyncConflictSnapshotReference>()
        let usedLocations = Set(usedReferences.union(preparedReferences).map {
            "\($0.slot.rawValue)-\($0.generation)"
        })
        let slots = [preferredSlot] + SyncConflictSnapshotStorageSlot.allCases.filter {
            $0 != preferredSlot
        }
        for slot in slots {
            for generation in 0...1 where !usedLocations.contains("\(slot.rawValue)-\(generation)") {
                return SyncConflictSnapshotReference(
                    slot: slot,
                    generation: generation,
                    byteCount: byteCount,
                    sha256: sha256
                )
            }
        }
        throw SyncConflictStateFileError.corruptStateQuarantined
    }
}
