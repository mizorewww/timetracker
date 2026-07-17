import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreSyncConflictStateWriteTests {
    @Test @MainActor
    func pendingLocalIntentRoundTripsAndLegacyStateStillDecodes() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        let service = SyncConflictService(stateURL: stateURL)
        var state = SyncConflictState()
        state.pendingForcedUploadSnapshot = snapshot(title: "Protected branch")
        state.pendingLocalIntent = .reconcileWithCloud

        try service.saveState(state)
        #expect(try service.loadState().pendingLocalIntent == .reconcileWithCloud)

        var legacyObject = try #require(
            JSONSerialization.jsonObject(with: sortedJSON(state)) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "pendingLocalIntent")
        try JSONSerialization.data(withJSONObject: legacyObject).write(
            to: stateURL,
            options: [.atomic]
        )
        let legacyState = try service.loadState()
        #expect(legacyState.pendingForcedUploadSnapshot != nil)
        #expect(legacyState.pendingLocalIntent == nil)
        #expect(service.pendingLocalIntent(from: legacyState) == .reconcileWithCloud)
        let migratedManifest = try JSONDecoder().decode(
            SyncConflictStateManifest.self,
            from: Data(contentsOf: stateURL)
        )
        #expect(migratedManifest.formatVersion == SyncConflictStateManifest.currentFormatVersion)
    }

    @Test @MainActor
    func oversizedStateWriteKeepsExistingStateAndMirrorUnchanged() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        let existing = try seedExistingPair(at: stateURL)

        var oversizedState = SyncConflictState()
        oversizedState.localSnapshot = snapshot(
            title: String(repeating: "state", count: 512)
        )
        let oversizedSnapshot = try #require(oversizedState.localSnapshot)
        let snapshotData = try sortedJSON(oversizedSnapshot)
        let expectedReference = SyncConflictSnapshotReference(
            slot: .local,
            generation: 0,
            byteCount: snapshotData.count,
            sha256: try oversizedSnapshot.fingerprint()
        )
        let encodedManifest = try sortedJSON(
            SyncConflictStateManifest(
                state: oversizedState,
                localSnapshot: expectedReference,
                pendingForcedUploadSnapshot: nil,
                pendingCloudSnapshot: nil,
                pendingConflictWorkingSnapshot: nil
            )
        )
        let maximumStateBytes = encodedManifest.count - 1
        let service = SyncConflictService(
            stateURL: stateURL,
            localStateByteLimits: .init(
                maximumStateFileByteCount: maximumStateBytes,
                maximumRecoverySnapshotFileByteCount: 4_096
            )
        )

        try expectWriteError(
            .stateExceedsMaximumByteCount(
                actualByteCount: encodedManifest.count,
                maximumByteCount: maximumStateBytes
            )
        ) {
            try service.saveState(oversizedState)
        }
        #expect(try Data(contentsOf: stateURL) == existing.state)
        #expect(try Data(contentsOf: mirrorURL(for: stateURL)) == existing.mirror)
    }

    @Test @MainActor
    func oversizedRecoveryMirrorKeepsExistingStateAndMirrorUnchanged() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        let existing = try seedExistingPair(at: stateURL)

        let oversizedSnapshot = snapshot(
            title: String(repeating: "mirror", count: 512)
        )
        var newState = SyncConflictState()
        newState.pendingForcedUploadSnapshot = oversizedSnapshot
        let encodedMirror = try sortedJSON(oversizedSnapshot)
        let maximumMirrorBytes = encodedMirror.count - 1
        let service = SyncConflictService(
            stateURL: stateURL,
            localStateByteLimits: .init(
                maximumStateFileByteCount: 16_384,
                maximumRecoverySnapshotFileByteCount: maximumMirrorBytes
            )
        )

        try expectWriteError(
            .recoverySnapshotExceedsMaximumByteCount(
                actualByteCount: encodedMirror.count,
                maximumByteCount: maximumMirrorBytes
            )
        ) {
            try service.saveState(newState)
        }
        #expect(try Data(contentsOf: stateURL) == existing.state)
        #expect(try Data(contentsOf: mirrorURL(for: stateURL)) == existing.mirror)
    }

    @Test @MainActor
    func payloadsExactlyAtInjectedWriteLimitsArePersisted() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        let newSnapshot = snapshot(title: "Exact boundary")
        var newState = SyncConflictState()
        newState.pendingForcedUploadSnapshot = newSnapshot
        let encodedMirror = try sortedJSON(newSnapshot)
        let expectedReference = SyncConflictSnapshotReference(
            slot: .pendingForcedUpload,
            generation: 0,
            byteCount: encodedMirror.count,
            sha256: try newSnapshot.fingerprint()
        )
        let encodedManifest = try sortedJSON(
            SyncConflictStateManifest(
                state: newState,
                localSnapshot: nil,
                pendingForcedUploadSnapshot: expectedReference,
                pendingCloudSnapshot: nil,
                pendingConflictWorkingSnapshot: nil
            )
        )
        let service = SyncConflictService(
            stateURL: stateURL,
            localStateByteLimits: .init(
                maximumStateFileByteCount: encodedManifest.count,
                maximumRecoverySnapshotFileByteCount: encodedMirror.count
            )
        )

        try service.saveState(newState)

        #expect(try Data(contentsOf: stateURL) == encodedManifest)
        #expect(try Data(contentsOf: mirrorURL(for: stateURL)) == encodedMirror)
        #expect(
            try Data(contentsOf: service.conflictSnapshotURL(for: expectedReference)) == encodedMirror
        )
        #expect(try service.loadState().pendingForcedUploadSnapshot == newSnapshot)
    }

    @Test @MainActor
    func largeSnapshotsStayOutsideTheBoundedStateManifest() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        let localSnapshot = snapshot(title: String(repeating: "local", count: 1_024))
        let cloudSnapshot = snapshot(title: String(repeating: "cloud", count: 1_024))
        let workingSnapshot = snapshot(title: String(repeating: "working", count: 1_024))
        var state = SyncConflictState()
        state.localSnapshot = localSnapshot
        state.pendingCloudSnapshot = cloudSnapshot
        state.pendingConflictWorkingSnapshot = workingSnapshot

        let localData = try sortedJSON(localSnapshot)
        let cloudData = try sortedJSON(cloudSnapshot)
        let workingData = try sortedJSON(workingSnapshot)
        let localReference = SyncConflictSnapshotReference(
            slot: .local,
            generation: 0,
            byteCount: localData.count,
            sha256: try localSnapshot.fingerprint()
        )
        let cloudReference = SyncConflictSnapshotReference(
            slot: .pendingCloud,
            generation: 0,
            byteCount: cloudData.count,
            sha256: try cloudSnapshot.fingerprint()
        )
        let workingReference = SyncConflictSnapshotReference(
            slot: .pendingConflictWorking,
            generation: 0,
            byteCount: workingData.count,
            sha256: try workingSnapshot.fingerprint()
        )
        let manifestData = try sortedJSON(
            SyncConflictStateManifest(
                state: state,
                localSnapshot: localReference,
                pendingForcedUploadSnapshot: nil,
                pendingCloudSnapshot: cloudReference,
                pendingConflictWorkingSnapshot: workingReference
            )
        )
        #expect(try sortedJSON(state).count > manifestData.count)

        let service = SyncConflictService(
            stateURL: stateURL,
            localStateByteLimits: .init(
                maximumStateFileByteCount: manifestData.count,
                maximumRecoverySnapshotFileByteCount: max(
                    localData.count,
                    cloudData.count,
                    workingData.count
                )
            )
        )
        try service.saveState(state)

        #expect(try Data(contentsOf: stateURL) == manifestData)
        #expect(try Data(contentsOf: service.conflictSnapshotURL(for: localReference)) == localData)
        #expect(try Data(contentsOf: service.conflictSnapshotURL(for: cloudReference)) == cloudData)
        #expect(try Data(contentsOf: service.conflictSnapshotURL(for: workingReference)) == workingData)
        #expect(try service.loadState().localSnapshot == localSnapshot)
        #expect(try service.loadState().pendingCloudSnapshot == cloudSnapshot)
        #expect(try service.loadState().pendingConflictWorkingSnapshot == workingSnapshot)
    }

    @Test @MainActor
    func corruptReferencedSnapshotQuarantinesTheManifestAuthority() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        let localSnapshot = snapshot(title: "Referenced local snapshot")
        var state = SyncConflictState()
        state.localSnapshot = localSnapshot
        let service = SyncConflictService(stateURL: stateURL)
        try service.saveState(state)

        let manifest = try JSONDecoder().decode(
            SyncConflictStateManifest.self,
            from: Data(contentsOf: stateURL)
        )
        let reference = try #require(manifest.localSnapshot)
        let snapshotURL = try service.conflictSnapshotURL(for: reference)
        try Data("corrupt snapshot".utf8).write(to: snapshotURL, options: [.atomic])

        #expect(throws: SyncConflictStateFileError.self) {
            try service.loadState()
        }
        #expect(FileManager.default.fileExists(atPath: snapshotURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: stateURL.path) == false)
    }

    @Test @MainActor
    func invalidSnapshotReferenceQuarantinesTheManifestAuthority() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        var state = SyncConflictState()
        state.localSnapshot = snapshot(title: "Referenced local snapshot")
        let service = SyncConflictService(stateURL: stateURL)
        try service.saveState(state)

        var manifestObject = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        var referenceObject = try #require(
            manifestObject["localSnapshot"] as? [String: Any]
        )
        referenceObject["generation"] = 2
        manifestObject["localSnapshot"] = referenceObject
        try JSONSerialization.data(withJSONObject: manifestObject, options: [.sortedKeys]).write(
            to: stateURL,
            options: [.atomic]
        )

        #expect(throws: SyncConflictStateFileError.self) {
            try service.loadState()
        }
        #expect(FileManager.default.fileExists(atPath: stateURL.path) == false)
    }

    @Test @MainActor
    func independentRecoveryMirrorRewriteChecksLimitBeforeChangingFiles() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        let mirrorURL = mirrorURL(for: stateURL)
        let excludedPreference = SyncedPreference(
            key: SyncedPreferenceService.legacyLLMAPIKey,
            valueJSON: PreferenceJSON.encode("secret"),
            deviceID: "test"
        )
        var legacySnapshot = snapshot(title: "Protected local task")
        legacySnapshot.syncedPreferences = [SyncedPreferenceRecord(excludedPreference)]
        let legacyMirrorData = try sortedJSON(legacySnapshot)
        try FileManager.default.createDirectory(
            at: mirrorURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try legacyMirrorData.write(to: mirrorURL, options: [.atomic])

        var scrubbedSnapshot = legacySnapshot
        let removedExcludedPreferences = scrubbedSnapshot.removeExcludedPreferences()
        #expect(removedExcludedPreferences)
        let scrubbedData = try sortedJSON(scrubbedSnapshot)
        let maximumMirrorBytes = scrubbedData.count - 1
        let service = SyncConflictService(
            stateURL: stateURL,
            localStateByteLimits: .init(
                maximumStateFileByteCount: 16_384,
                maximumRecoverySnapshotFileByteCount: maximumMirrorBytes
            )
        )

        try expectWriteError(
            .recoverySnapshotExceedsMaximumByteCount(
                actualByteCount: scrubbedData.count,
                maximumByteCount: maximumMirrorBytes
            )
        ) {
            _ = try service.loadState()
        }
        #expect(FileManager.default.fileExists(atPath: stateURL.path) == false)
        #expect(try Data(contentsOf: mirrorURL) == legacyMirrorData)
    }

    @Test @MainActor
    func durableStateWriteFailureKeepsTheLastCommittedStateAndMirror() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        let existing = try seedExistingPair(at: stateURL)
        let service = SyncConflictService(
            stateURL: stateURL,
            localStateFile: DurableLocalFile(injectFault: { point in
                if point == .afterAtomicWriteBeforeFileSync {
                    throw InjectedDurableWriteFailure()
                }
            })
        )
        var replacement = SyncConflictState()
        replacement.pendingForcedUploadSnapshot = snapshot(title: "Replacement")

        #expect(throws: InjectedDurableWriteFailure.self) {
            try service.saveState(replacement)
        }

        #expect(try Data(contentsOf: stateURL) == existing.state)
        #expect(try Data(contentsOf: mirrorURL(for: stateURL)) == existing.mirror)
        let temporaryFiles = try FileManager.default.contentsOfDirectory(
            at: stateURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".TimeTrackerWrite-") }
        #expect(temporaryFiles.isEmpty)
    }

    @Test @MainActor
    func durableQuarantineFailureRestoresTheCanonicalStateFile() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        let corruptData = Data("not JSON".utf8)
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try corruptData.write(to: stateURL)
        let service = SyncConflictService(
            stateURL: stateURL,
            localStateFile: DurableLocalFile(injectFault: { point in
                if point == .afterQuarantineMoveBeforeFileSync {
                    throw InjectedDurableWriteFailure()
                }
            })
        )

        #expect(throws: InjectedDurableWriteFailure.self) {
            _ = try service.loadState()
        }

        #expect(try Data(contentsOf: stateURL) == corruptData)
        let quarantineDirectory = stateURL.deletingLastPathComponent()
            .appendingPathComponent(".TimeTrackerQuarantine", isDirectory: true)
        let retainedQuarantines = (try? FileManager.default.contentsOfDirectory(
            at: quarantineDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        #expect(retainedQuarantines.isEmpty)
    }

    @MainActor
    private func expectWriteError(
        _ expected: SyncConflictLocalStateWriteError,
        operation: () throws -> Void
    ) throws {
        do {
            try operation()
            Issue.record("Expected local sync state write to be rejected")
        } catch let error as SyncConflictLocalStateWriteError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected local sync state write error: \(error)")
        }
    }

    @MainActor
    private func seedExistingPair(at stateURL: URL) throws -> (state: Data, mirror: Data) {
        let existingSnapshot = snapshot(title: "Existing protected snapshot")
        var existingState = SyncConflictState()
        existingState.pendingForcedUploadSnapshot = existingSnapshot
        let stateData = try sortedJSON(existingState)
        let mirrorData = try sortedJSON(existingSnapshot)
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try stateData.write(to: stateURL, options: [.atomic])
        try mirrorData.write(to: mirrorURL(for: stateURL), options: [.atomic])
        return (stateData, mirrorData)
    }

    @MainActor
    private func snapshot(title: String) -> SyncDataSnapshot {
        SyncDataSnapshot(
            tasks: [TaskRecord(TaskNode(title: title, parentID: nil, deviceID: "test"))]
        )
    }

    private func sortedJSON<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func temporaryStateURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TimeTrackerSyncStateWriteTests-\(UUID().uuidString)",
                isDirectory: true
            )
            .appendingPathComponent("state.json")
    }

    private func mirrorURL(for stateURL: URL) -> URL {
        stateURL.deletingLastPathComponent().appendingPathComponent(
            SyncConflictService.pendingForcedUploadSnapshotFileName
        )
    }

    private struct InjectedDurableWriteFailure: Error {}
}
