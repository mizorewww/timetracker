import SwiftData

/// Owns the synchronous SwiftData snapshot and sync sidecar transaction away
/// from MainActor. The store lock is acquired before the fresh read context,
/// and the sync-state lock is acquired only after both.
actor PersistentHistorySyncSnapshotWorker {
    private let container: ModelContainer
    private let scope: TimerStoreScope
    private let syncConflictService: SyncConflictService
    private let policySource: SyncLocalMutationRecordingPolicySource
    private let mutationLock = StoreScopedTimerMutationLock()

    @MainActor
    init(
        container: ModelContainer,
        syncConflictService: SyncConflictService = SyncConflictService()
    ) throws {
        self.container = container
        scope = try TimerStoreScope(container: container)
        self.syncConflictService = syncConflictService
        policySource = .appDefaults()
    }

    func record(
        events: Set<StoreDomainEvent>
    ) async throws -> SyncLocalMutationSnapshotResult {
        // Keep disabled sync at zero store and sidecar reads.
        guard policySource.current().shouldRecordSnapshot else {
            return .notRecorded
        }

        let outcome = try mutationLock.withExclusiveAccess(
            for: scope
        ) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            return try syncConflictService.withExclusiveStateAccess {
                try syncConflictService
                    .recordLocalMutationWithLockedState(
                        context: context,
                        events: events,
                        policySource: policySource
                    )
            }
        }

        if let expectedPolicy =
            outcome.cloudReconciliationResetPolicy
        {
            _ = await AppCloudSync
                .requestCloudReconciliationReset(
                    ifCurrentPolicyMatches: expectedPolicy
                )
        }
        return outcome.result
    }
}
