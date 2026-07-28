import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct PersistentHistorySyncSnapshotWorkerTests {
    @Test
    func captureAndFingerprintDoNotBlockMainActorHeartbeat()
        async throws
    {
        for checkpoint in [
            PersistentHistorySyncSnapshotCheckpoint.beforeCapture,
            .beforeFingerprint,
        ] {
            let gate = SyncSnapshotBlockingGate()
            let fixture = try makeFixture(
                name: "\(checkpoint)",
                hooks: .init { reached in
                    if reached == checkpoint {
                        gate.blockFirstEntry()
                    }
                }
            )
            defer { fixture.removeTemporaryState() }
            let worker = fixture.worker
            let policy = SyncLocalMutationRecordingPolicy.cloudActive

            try await expectMainActorHeartbeat(
                while: gate,
                performs: {
                    try await worker.record(
                        events: [.fullSync],
                        policy: policy
                    )
                }
            )
        }
    }

    @Test
    func durableSidecarWriteDoesNotBlockMainActorHeartbeat()
        async throws
    {
        let gate = SyncSnapshotBlockingGate()
        let fixture = try makeFixture(
            name: #function,
            localStateFile: DurableLocalFile(injectFault: { point in
                if point == .afterAtomicWriteBeforeFileSync {
                    gate.blockFirstEntry()
                }
            })
        )
        defer { fixture.removeTemporaryState() }
        let worker = fixture.worker
        let policy = SyncLocalMutationRecordingPolicy.cloudActive

        try await expectMainActorHeartbeat(
            while: gate,
            performs: {
                try await worker.record(
                    events: [.fullSync],
                    policy: policy
                )
            }
        )
    }

    @Test
    func disabledSyncPerformsNoStoreOrSidecarReads() async throws {
        let probe = SyncSnapshotCheckpointProbe()
        let stateURL = temporaryStateURL(name: #function)
        defer {
            try? FileManager.default.removeItem(
                at: stateURL.deletingLastPathComponent()
            )
        }
        let context = try makeTestContext()
        context.insert(
            TaskNode(
                title: "Device-only task",
                parentID: nil,
                deviceID: "device-a"
            )
        )
        try context.save()
        let worker = try PersistentHistorySyncSnapshotWorker(
            container: context.container,
            syncConflictService: SyncConflictService(
                stateURL: stateURL
            ),
            hooks: .init(reach: probe.record)
        )

        let result = try await worker.record(
            events: [.fullSync],
            policy: .disabled
        )

        guard case .notRecorded = result else {
            Issue.record(
                "Disabled sync without recovery must not record a snapshot"
            )
            return
        }
        #expect(probe.checkpoints.isEmpty)
        #expect(
            FileManager.default.fileExists(atPath: stateURL.path) == false
        )
    }

    @Test
    func replayUsesExistingIdempotentGenerationAndWriteRules()
        async throws
    {
        let writeProbe = SyncSnapshotDurableWriteProbe()
        let fixture = try makeFixture(
            name: #function,
            localStateFile: DurableLocalFile(injectFault: { point in
                if point == .afterAtomicWriteBeforeFileSync {
                    writeProbe.record()
                }
            })
        )
        defer { fixture.removeTemporaryState() }

        _ = try await fixture.worker.record(
            events: [.fullSync],
            policy: .cloudActive
        )
        let stateAfterFirstRecord =
            try fixture.syncConflictService.loadState()
        let writesAfterFirstRecord = writeProbe.count

        _ = try await fixture.worker.record(
            events: [.fullSync],
            policy: .cloudActive
        )
        let stateAfterReplay =
            try fixture.syncConflictService.loadState()

        #expect(
            stateAfterReplay.localGeneration ==
                stateAfterFirstRecord.localGeneration
        )
        #expect(
            stateAfterReplay.localFingerprint ==
                stateAfterFirstRecord.localFingerprint
        )
        #expect(writeProbe.count == writesAfterFirstRecord)
    }

    @Test
    func storeLockWaitUsesLatestCloudFallbackOrDisabledPolicy()
        async throws
    {
        let transitions: [(
            name: String,
            initial: SyncLocalMutationRecordingPolicy,
            replacement: SyncLocalMutationRecordingPolicy
        )] = [
            ("cloud-to-fallback", .cloudActive, .fallback),
            ("fallback-to-cloud", .fallback, .cloudActive),
            ("cloud-to-disabled", .cloudActive, .disabled),
        ]

        for transition in transitions {
            let gate = SyncSnapshotBlockingGate()
            let policyProbe = SyncSnapshotPolicyProbe(
                transition.initial
            )
            let resetProbe = SyncSnapshotResetRequestProbe()
            let fixture = try makeFixture(
                name: "\(transition.name)-\(UUID().uuidString)",
                hooks: .init { checkpoint in
                    if checkpoint == .beforeFreshContext {
                        gate.blockFirstEntry()
                    }
                },
                policySource: .init(current: policyProbe.current),
                resetRequester: resetProbe.request
            )
            defer { fixture.removeTemporaryState() }
            let worker = fixture.worker
            let run = Task.detached {
                try await worker.record(events: [.fullSync])
            }

            await gate.waitUntilBlocked()
            policyProbe.set(transition.replacement)
            gate.releaseOnce(from: .test)
            let result = try await run.value

            if transition.replacement == .disabled {
                guard case .notRecorded = result else {
                    Issue.record(
                        "\(transition.name) used the stale recording branch"
                    )
                    continue
                }
                #expect(
                    FileManager.default.fileExists(
                        atPath: fixture.stateURL.path
                    ) == false
                )
                #expect(resetProbe.requests.isEmpty)
            } else {
                guard case .recorded = result else {
                    Issue.record(
                        "\(transition.name) did not record with live policy"
                    )
                    continue
                }
                let state = try fixture.syncConflictService.loadState()
                if transition.replacement == .fallback {
                    #expect(
                        state.pendingForcedUploadSnapshot?
                            .hasProtectableUserContent == true
                    )
                    #expect(
                        state.pendingLocalIntent == .reconcileWithCloud
                    )
                    #expect(resetProbe.requests == [.fallback])
                } else {
                    #expect(state.localSnapshot != nil)
                    #expect(state.pendingForcedUploadSnapshot == nil)
                    #expect(resetProbe.requests.isEmpty)
                }
            }
        }
    }

    @Test
    func policyChangeBeforeStateWriteThrowsWithoutConfirmingOldBranch()
        async throws
    {
        let gate = SyncSnapshotBlockingGate()
        let policyProbe = SyncSnapshotPolicyProbe(.cloudActive)
        let fixture = try makeFixture(
            name: #function,
            hooks: .init { checkpoint in
                if checkpoint == .beforeStateWrite {
                    gate.blockFirstEntry()
                }
            },
            policySource: .init(current: policyProbe.current),
            resetRequester: { _ in true }
        )
        defer { fixture.removeTemporaryState() }
        let worker = fixture.worker
        let run = Task.detached {
            try await worker.record(events: [.fullSync])
        }

        await gate.waitUntilBlocked()
        policyProbe.set(.fallback)
        gate.releaseOnce(from: .test)

        await #expect(
            throws: SyncLocalMutationRecordingError.policyChanged
        ) {
            try await run.value
        }
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.stateURL.path
            ) == false
        )
    }

    @Test
    func policyChangeDuringStateWriteRequiresReplayBeforeAcknowledgement()
        async throws
    {
        let gate = SyncSnapshotBlockingGate()
        let policyProbe = SyncSnapshotPolicyProbe(.cloudActive)
        let fixture = try makeFixture(
            name: #function,
            localStateFile: DurableLocalFile(
                injectFault: { checkpoint in
                    if checkpoint == .afterAtomicWriteBeforeFileSync {
                        gate.blockFirstEntry()
                    }
                }
            ),
            policySource: .init(current: policyProbe.current),
            resetRequester: { _ in true }
        )
        defer { fixture.removeTemporaryState() }
        let worker = fixture.worker
        let run = Task.detached {
            try await worker.record(events: [.fullSync])
        }

        await gate.waitUntilBlocked()
        policyProbe.set(.fallback)
        gate.releaseOnce(from: .test)

        await #expect(
            throws: SyncLocalMutationRecordingError.policyChanged
        ) {
            try await run.value
        }

        let replay = try await worker.record(events: [.fullSync])
        guard case .recorded = replay else {
            Issue.record("The current policy branch was not replayed")
            return
        }
        let state = try fixture.syncConflictService.loadState()
        #expect(
            state.pendingForcedUploadSnapshot?
                .hasProtectableUserContent == true
        )
        #expect(state.pendingLocalIntent == .reconcileWithCloud)
    }

    @Test
    func delayedResetCannotOverrideDisabledOrDownloadIntent()
        async throws
    {
        enum NewerIntent {
            case disabled
            case download
        }

        for newerIntent in [NewerIntent.disabled, .download] {
            let defaultsGuard = SyncSnapshotAppDefaultsGuard()
            defer { defaultsGuard.restore() }
            defaultsGuard.configureFallback()
            let gate = SyncSnapshotBlockingGate()
            let fixture = try makeFixture(
                name: "\(newerIntent)-\(UUID().uuidString)",
                hooks: .init { checkpoint in
                    if checkpoint == .afterStateWriteBeforeReset {
                        gate.blockFirstEntry()
                    }
                }
            )
            defer { fixture.removeTemporaryState() }
            let worker = fixture.worker
            let run = Task.detached {
                try await worker.record(events: [.fullSync])
            }

            await gate.waitUntilBlocked()
            switch newerIntent {
            case .disabled:
                AppDefaults.shared.set(
                    false,
                    forKey: AppCloudSync.enabledKey
                )
                AppDefaults.shared.set(
                    AppCloudSync.modeLocal,
                    forKey: AppCloudSync.modeKey
                )
            case .download:
                AppCloudSync.requestCloudDownloadReset()
            }
            gate.releaseOnce(from: .test)
            _ = try await run.value

            #expect(
                AppDefaults.shared.bool(
                    forKey: AppCloudSync.pendingCloudUploadResetKey
                ) == false
            )
            #expect(
                AppDefaults.shared.bool(
                    forKey: AppCloudSync.queuedCloudReconciliationKey
                ) == false
            )
            switch newerIntent {
            case .disabled:
                #expect(
                    AppDefaults.shared.bool(
                        forKey: AppCloudSync.enabledKey
                    ) == false
                )
            case .download:
                #expect(
                    AppDefaults.shared.bool(
                        forKey:
                        AppCloudSync.pendingCloudDownloadResetKey
                    )
                )
            }
        }
    }

    @Test
    func recoveryMirrorIntentIsReadInsideStateLock()
        async throws
    {
        let gate = SyncSnapshotBlockingGate()
        let policyProbe = SyncSnapshotPolicyProbe(
            .pendingExplicitUpload
        )
        let fixture = try makeFixture(
            name: #function,
            hooks: .init { checkpoint in
                if checkpoint == .beforeStateRead {
                    gate.blockFirstEntry()
                }
            },
            policySource: .init(current: policyProbe.current),
            resetRequester: { _ in true }
        )
        defer { fixture.removeTemporaryState() }
        try fixture.seedRecoveryMirrorWithoutAuthoritativeState(
            intent: .explicitlyReplaceCloud
        )
        let worker = fixture.worker
        let run = Task.detached {
            try await worker.record(events: [.fullSync])
        }

        await gate.waitUntilBlocked()
        policyProbe.set(.pendingReconciliation)
        gate.releaseOnce(from: .test)
        _ = try await run.value

        let recovered = try fixture.syncConflictService.loadState()
        #expect(
            recovered.pendingLocalIntent == .reconcileWithCloud
        )
    }

    private func expectMainActorHeartbeat(
        while gate: SyncSnapshotBlockingGate,
        performs operation: @escaping @Sendable () async throws
            -> SyncLocalMutationSnapshotResult
    ) async throws {
        let coordinator = Task.detached {
            await gate.waitUntilBlocked()
            let safetyRelease = Task.detached {
                try? await Task.sleep(for: .seconds(2))
                gate.releaseOnce(from: .safety)
            }
            await Task { @MainActor in
                gate.releaseOnce(from: .heartbeat)
            }.value
            safetyRelease.cancel()
            _ = await safetyRelease.result
        }
        let run = Task.detached {
            try await operation()
        }

        _ = try await run.value
        await coordinator.value

        #expect(gate.firstRelease == .heartbeat)
    }

    private func makeFixture(
        name: String,
        localStateFile: DurableLocalFile = DurableLocalFile(),
        hooks: PersistentHistorySyncSnapshotWorkerHooks = .init(),
        policySource: SyncLocalMutationRecordingPolicySource? = nil,
        resetRequester:
        PersistentHistorySyncSnapshotWorker.ResetRequester? = nil
    ) throws -> SyncSnapshotWorkerFixture {
        let context = try makeTestContext()
        context.insert(
            TaskNode(
                title: "Captured task",
                parentID: nil,
                deviceID: "device-a"
            )
        )
        try context.save()
        let stateURL = temporaryStateURL(name: name)
        let service = SyncConflictService(
            stateURL: stateURL,
            localStateFile: localStateFile
        )
        return try SyncSnapshotWorkerFixture(
            container: context.container,
            stateURL: stateURL,
            syncConflictService: service,
            worker: PersistentHistorySyncSnapshotWorker(
                container: context.container,
                syncConflictService: service,
                hooks: hooks,
                policySource: policySource,
                resetRequester: resetRequester
            )
        )
    }

    private func temporaryStateURL(name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PersistentHistorySyncSnapshot-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
            .appendingPathComponent("state.json")
    }
}

private struct SyncSnapshotWorkerFixture {
    let container: ModelContainer
    let stateURL: URL
    let syncConflictService: SyncConflictService
    let worker: PersistentHistorySyncSnapshotWorker

    @MainActor
    func seedRecoveryMirrorWithoutAuthoritativeState(
        intent: SyncPendingLocalIntent
    ) throws {
        let context = ModelContext(container)
        let snapshot = try SyncDataSnapshot.capture(context: context)
        var state = SyncConflictState()
        state.pendingForcedUploadSnapshot = snapshot
        state.pendingLocalIntent = intent
        try syncConflictService.saveState(state)

        try FileManager.default.removeItem(at: stateURL)
        for slotURL in SyncConflictService
            .allConflictSnapshotSlotURLs(for: stateURL)
            where FileManager.default.fileExists(
                atPath: slotURL.path
            )
        {
            try FileManager.default.removeItem(at: slotURL)
        }
        #expect(
            try FileManager.default.fileExists(
                atPath:
                syncConflictService
                    .pendingForcedUploadSnapshotURL().path
            )
        )
    }

    func removeTemporaryState() {
        try? FileManager.default.removeItem(
            at: stateURL.deletingLastPathComponent()
        )
    }
}

@MainActor
private extension SyncLocalMutationRecordingPolicy {
    static let cloudActive = Self(testing: .init(
        isSyncEnabled: true,
        persistenceMode: AppCloudSync.modeICloud
    ))

    static let fallback = Self(testing: .init(
        isSyncEnabled: true,
        persistenceMode: AppCloudSync.modeLocalFallback
    ))

    static let disabled = Self(testing: .init(
        isSyncEnabled: false,
        persistenceMode: AppCloudSync.modeLocal
    ))

    static let pendingExplicitUpload = Self(testing: .init(
        isSyncEnabled: true,
        persistenceMode: AppCloudSync.modeLocalFallback,
        hasPendingUploadRecovery: true
    ))

    static let pendingReconciliation = Self(testing: .init(
        isSyncEnabled: true,
        persistenceMode: AppCloudSync.modeLocalFallback,
        hasPendingUploadRecovery: true,
        hasQueuedCloudReconciliation: true
    ))
}

@MainActor
private final class SyncSnapshotResetRequestProbe {
    private(set) var requests: [SyncLocalMutationRecordingPolicy] = []

    func request(
        _ policy: SyncLocalMutationRecordingPolicy
    ) -> Bool {
        requests.append(policy)
        return true
    }
}

private final nonisolated class SyncSnapshotPolicyProbe:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var policy: SyncLocalMutationRecordingPolicy

    init(_ policy: SyncLocalMutationRecordingPolicy) {
        self.policy = policy
    }

    func current() -> SyncLocalMutationRecordingPolicy {
        lock.withLock { policy }
    }

    func set(_ policy: SyncLocalMutationRecordingPolicy) {
        lock.withLock {
            self.policy = policy
        }
    }
}

@MainActor
private final class SyncSnapshotAppDefaultsGuard {
    private let keys = [
        AppCloudSync.enabledKey,
        AppCloudSync.modeKey,
        AppCloudSync.errorKey,
        AppCloudSync.pendingCloudUploadResetKey,
        AppCloudSync.pendingCloudDownloadResetKey,
        AppCloudSync.queuedCloudReconciliationKey,
        AppCloudSync.activeCloudReconciliationKey,
        AppCloudSync.cloudRecoveryStoreResetKey,
        AppCloudSync.activeCloudDownloadRecoveryKey,
    ]
    private let previousValues: [String: Any]

    init() {
        previousValues = Dictionary(
            uniqueKeysWithValues: keys.compactMap { key in
                AppDefaults.shared.object(forKey: key).map {
                    (key, $0)
                }
            }
        )
    }

    func configureFallback() {
        for key in keys {
            AppDefaults.shared.removeObject(forKey: key)
        }
        AppDefaults.shared.set(
            true,
            forKey: AppCloudSync.enabledKey
        )
        AppDefaults.shared.set(
            AppCloudSync.modeLocalFallback,
            forKey: AppCloudSync.modeKey
        )
    }

    func restore() {
        for key in keys {
            if let value = previousValues[key] {
                AppDefaults.shared.set(value, forKey: key)
            } else {
                AppDefaults.shared.removeObject(forKey: key)
            }
        }
    }
}

@MainActor
private extension SyncLocalMutationRecordingPolicy {
    init(testing state: SyncLocalMutationPolicyState) {
        self.init(
            state: state,
            cloudMode: AppCloudSync.modeICloud,
            localMode: AppCloudSync.modeLocal,
            localFallbackMode: AppCloudSync.modeLocalFallback
        )
    }
}

private final nonisolated class SyncSnapshotCheckpointProbe:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var recorded: [PersistentHistorySyncSnapshotCheckpoint] = []

    var checkpoints: [PersistentHistorySyncSnapshotCheckpoint] {
        lock.withLock { recorded }
    }

    func record(_ checkpoint: PersistentHistorySyncSnapshotCheckpoint) {
        lock.withLock {
            recorded.append(checkpoint)
        }
    }
}

private final nonisolated class SyncSnapshotDurableWriteProbe:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var writeCount = 0

    var count: Int {
        lock.withLock { writeCount }
    }

    func record() {
        lock.withLock {
            writeCount += 1
        }
    }
}

private final nonisolated class SyncSnapshotBlockingGate:
    @unchecked Sendable
{
    enum ReleaseSource: Equatable {
        case heartbeat
        case safety
        case test
    }

    private let lock = NSLock()
    private let resume = DispatchSemaphore(value: 0)
    private var didBlock = false
    private var isBlocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var releaseSource: ReleaseSource?

    var firstRelease: ReleaseSource? {
        lock.withLock { releaseSource }
    }

    func blockFirstEntry() {
        let state = lock.withLock {
            () -> (Bool, [CheckedContinuation<Void, Never>]) in
            guard didBlock == false else { return (false, []) }
            didBlock = true
            isBlocked = true
            defer { waiters.removeAll() }
            return (true, waiters)
        }
        state.1.forEach { $0.resume() }
        if state.0 {
            resume.wait()
        }
    }

    func waitUntilBlocked() async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock {
                guard isBlocked == false else { return true }
                waiters.append(continuation)
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    func releaseOnce(from source: ReleaseSource) {
        let shouldSignal = lock.withLock {
            guard releaseSource == nil else { return false }
            releaseSource = source
            return true
        }
        if shouldSignal {
            resume.signal()
        }
    }
}
