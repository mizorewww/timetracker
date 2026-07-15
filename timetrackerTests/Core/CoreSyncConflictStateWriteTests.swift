import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreSyncConflictStateWriteTests {
    @Test @MainActor
    func oversizedStateWriteKeepsExistingStateAndMirrorUnchanged() throws {
        let stateURL = temporaryStateURL()
        defer { try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent()) }
        let existing = try seedExistingPair(at: stateURL)

        var oversizedState = SyncConflictState()
        oversizedState.localSnapshot = snapshot(
            title: String(repeating: "state", count: 512)
        )
        let encodedState = try sortedJSON(oversizedState)
        let maximumStateBytes = encodedState.count - 1
        let service = SyncConflictService(
            stateURL: stateURL,
            localStateByteLimits: .init(
                maximumStateFileByteCount: maximumStateBytes,
                maximumRecoverySnapshotFileByteCount: 4_096
            )
        )

        try expectWriteError(
            .stateExceedsMaximumByteCount(
                actualByteCount: encodedState.count,
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
        let encodedState = try sortedJSON(newState)
        let encodedMirror = try sortedJSON(oversizedSnapshot)
        let maximumMirrorBytes = encodedMirror.count - 1
        let service = SyncConflictService(
            stateURL: stateURL,
            localStateByteLimits: .init(
                maximumStateFileByteCount: encodedState.count,
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
        let encodedState = try sortedJSON(newState)
        let encodedMirror = try sortedJSON(newSnapshot)
        let service = SyncConflictService(
            stateURL: stateURL,
            localStateByteLimits: .init(
                maximumStateFileByteCount: encodedState.count,
                maximumRecoverySnapshotFileByteCount: encodedMirror.count
            )
        )

        try service.saveState(newState)

        #expect(try Data(contentsOf: stateURL) == encodedState)
        #expect(try Data(contentsOf: mirrorURL(for: stateURL)) == encodedMirror)
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
}
