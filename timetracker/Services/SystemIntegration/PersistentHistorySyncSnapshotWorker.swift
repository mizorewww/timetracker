import SwiftData

/// Owns the synchronous SwiftData snapshot and sync sidecar transaction away
/// from MainActor. The store lock is acquired before the fresh read context,
/// and the sync-state lock is acquired only after both.
actor PersistentHistorySyncSnapshotWorker {
    typealias ResetRequester =
        @MainActor @Sendable (
            SyncLocalMutationRecordingPolicy
        ) -> Bool

    private let container: ModelContainer
    private let scope: TimerStoreScope
    private let syncConflictService: SyncConflictService
    private let hooks: PersistentHistorySyncSnapshotWorkerHooks
    private let policySource: SyncLocalMutationRecordingPolicySource
    private let resetRequester: ResetRequester
    private let mutationLock = StoreScopedTimerMutationLock()

    @MainActor
    init(
        container: ModelContainer,
        syncConflictService: SyncConflictService = SyncConflictService(),
        hooks: PersistentHistorySyncSnapshotWorkerHooks = .init(),
        policySource: SyncLocalMutationRecordingPolicySource? = nil,
        resetRequester: ResetRequester? = nil
    ) throws {
        self.container = container
        scope = try TimerStoreScope(container: container)
        self.syncConflictService = syncConflictService
        self.hooks = hooks
        self.policySource = policySource ?? .appDefaults()
        self.resetRequester = resetRequester ?? { expectedPolicy in
            AppCloudSync.requestCloudReconciliationReset(
                ifCurrentPolicyMatches: expectedPolicy
            )
        }
    }

    func record(
        events: Set<StoreDomainEvent>
    ) async throws -> SyncLocalMutationSnapshotResult {
        try await record(
            events: events,
            policySource: policySource
        )
    }

    func record(
        events: Set<StoreDomainEvent>,
        policy: SyncLocalMutationRecordingPolicy
    ) async throws -> SyncLocalMutationSnapshotResult {
        try await record(
            events: events,
            policySource: SyncLocalMutationRecordingPolicySource {
                policy
            }
        )
    }

    private func record(
        events: Set<StoreDomainEvent>,
        policySource: SyncLocalMutationRecordingPolicySource
    ) async throws -> SyncLocalMutationSnapshotResult {
        // Keep disabled sync at zero store and sidecar reads.
        guard policySource.current().shouldRecordSnapshot else {
            return .notRecorded
        }

        let outcome = try mutationLock.withExclusiveAccess(
            for: scope
        ) {
            hooks.reach(.beforeFreshContext)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            return try syncConflictService.withExclusiveStateAccess {
                try syncConflictService
                    .recordLocalMutationWithLockedState(
                        context: context,
                        events: events,
                        policySource: policySource,
                        hooks: hooks
                    )
            }
        }

        if let expectedPolicy =
            outcome.cloudReconciliationResetPolicy
        {
            hooks.reach(.afterStateWriteBeforeReset)
            _ = await resetRequester(expectedPolicy)
        }
        return outcome.result
    }
}
