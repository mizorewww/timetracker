import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreSyncConflictResolutionIdentityTests {
    @Test @MainActor
    func matchingExpectedConflictIDResolvesTheRequestedConflict() throws {
        try withICloudSyncMode {
            let fixture = try makeConflictFixture()
            defer { fixture.removeTemporaryFiles() }

            let result = try fixture.service.resolveSyncConflict(
                expectedConflictID: fixture.prompt.id,
                resolution: .uploadLocal,
                context: fixture.context
            )

            #expect(result == .appliedImmediately)
            #expect(fixture.service.prompt() == nil)
            #expect(try currentTaskTitle(in: fixture.context) == "Local plan")
        }
    }

    @Test @MainActor
    func staleExpectedConflictIDRejectsWithoutMutatingConflictStateOrUserData() throws {
        try withICloudSyncMode {
            let fixture = try makeConflictFixture()
            defer { fixture.removeTemporaryFiles() }
            let replacementConflictID = try replacePendingConflictID(
                for: fixture.service,
                replacing: fixture.prompt.id
            )
            let stateBytesBeforeResolution = try Data(contentsOf: fixture.stateURL)
            let stateBeforeResolution = try fixture.service.loadState()
            let localSnapshotBeforeResolution = try #require(stateBeforeResolution.localSnapshot)
            let localSnapshotFingerprintBeforeResolution = try localSnapshotBeforeResolution.fingerprint()
            let cloudSnapshotBeforeResolution = try #require(stateBeforeResolution.pendingCloudSnapshot)
            let cloudSnapshotFingerprintBeforeResolution = try cloudSnapshotBeforeResolution.fingerprint()
            let dataFingerprintBeforeResolution = try SyncDataSnapshot
                .capture(context: fixture.context)
                .fingerprint()

            let result = try fixture.service.resolveSyncConflict(
                expectedConflictID: fixture.prompt.id,
                resolution: .uploadLocal,
                context: fixture.context
            )

            #expect(result == .conflictChanged)
            #expect(fixture.service.prompt()?.id == replacementConflictID)
            #expect(try Data(contentsOf: fixture.stateURL) == stateBytesBeforeResolution)
            let stateAfterResolution = try fixture.service.loadState()
            #expect(stateAfterResolution.syncEpoch == stateBeforeResolution.syncEpoch)
            #expect(
                try stateAfterResolution.localSnapshot?.fingerprint()
                    == localSnapshotFingerprintBeforeResolution
            )
            #expect(
                try stateAfterResolution.pendingCloudSnapshot?.fingerprint()
                    == cloudSnapshotFingerprintBeforeResolution
            )
            #expect(
                try SyncDataSnapshot.capture(context: fixture.context).fingerprint()
                    == dataFingerprintBeforeResolution
            )
            #expect(try currentTaskTitle(in: fixture.context) == "Cloud plan")
        }
    }

    @Test @MainActor
    func expectingNoConflictRejectsOneThatArrivedBeforeConfirmation() throws {
        try withICloudSyncMode {
            let fixture = try makeConflictFixture()
            defer { fixture.removeTemporaryFiles() }
            let stateBytesBeforeResolution = try Data(contentsOf: fixture.stateURL)
            let dataFingerprintBeforeResolution = try SyncDataSnapshot
                .capture(context: fixture.context)
                .fingerprint()

            let result = try fixture.service.resolveSyncConflict(
                expectedConflictID: nil,
                resolution: .downloadCloud,
                context: fixture.context
            )

            #expect(result == .conflictChanged)
            #expect(fixture.service.prompt()?.id == fixture.prompt.id)
            #expect(try Data(contentsOf: fixture.stateURL) == stateBytesBeforeResolution)
            #expect(
                try SyncDataSnapshot.capture(context: fixture.context).fingerprint()
                    == dataFingerprintBeforeResolution
            )
            #expect(try currentTaskTitle(in: fixture.context) == "Cloud plan")
        }
    }

    @Test @MainActor
    func storeFacadeRejectsAStaleExpectedConflictIDWithoutResolvingTheReplacement() throws {
        try withICloudSyncMode {
            let fixture = try makeConflictFixture()
            defer { fixture.removeTemporaryFiles() }
            let replacementConflictID = try replacePendingConflictID(
                for: fixture.service,
                replacing: fixture.prompt.id
            )
            let replacementPrompt = try #require(fixture.service.prompt())
            let store = TimeTrackerStore(
                writeAuthorization: .isolatedTestHarness,
                syncConflictService: fixture.service
            )
            store.configureRepositoriesIfNeeded(context: fixture.context)
            store.pendingSyncConflict = replacementPrompt
            let stateBytesBeforeResolution = try Data(contentsOf: fixture.stateURL)
            let dataFingerprintBeforeResolution = try SyncDataSnapshot
                .capture(context: fixture.context)
                .fingerprint()

            let result = store.resolveSyncConflict(
                expectedConflictID: fixture.prompt.id,
                resolution: .downloadCloud
            )

            #expect(result == .conflictChanged)
            #expect(store.pendingSyncConflict?.id == replacementConflictID)
            #expect(fixture.service.prompt()?.id == replacementConflictID)
            #expect(try Data(contentsOf: fixture.stateURL) == stateBytesBeforeResolution)
            #expect(
                try SyncDataSnapshot.capture(context: fixture.context).fingerprint()
                    == dataFingerprintBeforeResolution
            )
            #expect(try currentTaskTitle(in: fixture.context) == "Cloud plan")
        }
    }

    @MainActor
    private func makeConflictFixture() throws -> ConflictFixture {
        let context = try makeTestContext()
        let task = TaskNode(title: "Local plan", parentID: nil, deviceID: "test")
        context.insert(task)
        try context.save()

        let stateURL = temporaryStateURL()
        let service = SyncConflictService(stateURL: stateURL)
        #expect(try service.bootstrap(context: context) == nil)

        task.title = "Cloud plan"
        task.updatedAt = Date().addingTimeInterval(60)
        try context.save()
        let prompt = try #require(try service.handleCloudImport(context: context))

        return ConflictFixture(
            context: context,
            service: service,
            stateURL: stateURL,
            prompt: prompt
        )
    }

    @MainActor
    private func replacePendingConflictID(
        for service: SyncConflictService,
        replacing originalConflictID: UUID
    ) throws -> UUID {
        var state = try service.loadState()
        #expect(state.pendingConflictID == originalConflictID)
        let replacementConflictID = UUID()
        state.pendingConflictID = replacementConflictID
        state.pendingDetectedAt = Date().addingTimeInterval(1)
        try service.saveState(state)
        return replacementConflictID
    }

    @MainActor
    private func currentTaskTitle(in context: ModelContext) throws -> String? {
        try context.fetch(FetchDescriptor<TaskNode>())
            .visibleDeduplicatedByID()
            .first?
            .title
    }

    private func temporaryStateURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "TimeTrackerConflictIdentityTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try? FileManager.default.removeItem(at: directory)
        return directory.appending(path: "state.json")
    }

    private func withICloudSyncMode(_ body: () throws -> Void) throws {
        let defaults = UserDefaults.standard
        let previousMode = defaults.string(forKey: AppCloudSync.modeKey)
        let previousEnabled = defaults.object(forKey: AppCloudSync.enabledKey)
        defaults.set(AppCloudSync.modeICloud, forKey: AppCloudSync.modeKey)
        defer {
            if let previousMode {
                defaults.set(previousMode, forKey: AppCloudSync.modeKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.modeKey)
            }
            if let previousEnabled {
                defaults.set(previousEnabled, forKey: AppCloudSync.enabledKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.enabledKey)
            }
        }
        try body()
    }
}

private struct ConflictFixture {
    let context: ModelContext
    let service: SyncConflictService
    let stateURL: URL
    let prompt: SyncConflictPrompt

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent())
    }
}
