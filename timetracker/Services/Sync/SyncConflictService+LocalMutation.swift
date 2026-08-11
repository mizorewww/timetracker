import Foundation
import SwiftData

nonisolated enum SyncLocalMutationSnapshotResult: Sendable {
    case notRecorded
    case recorded(prompt: SyncConflictPrompt?)
}

nonisolated struct SyncLocalMutationPolicyState:
    Equatable,
    Sendable
{
    let isSyncEnabled: Bool
    let persistenceMode: String
    let hasPendingUploadRecovery: Bool
    let hasPendingDownloadRecovery: Bool
    let hasQueuedCloudReconciliation: Bool
    let hasActiveCloudReconciliation: Bool
    let hasCloudRecoveryStoreReset: Bool
    let hasActiveCloudDownloadRecovery: Bool

    init(
        isSyncEnabled: Bool,
        persistenceMode: String,
        hasPendingUploadRecovery: Bool = false,
        hasPendingDownloadRecovery: Bool = false,
        hasQueuedCloudReconciliation: Bool = false,
        hasActiveCloudReconciliation: Bool = false,
        hasCloudRecoveryStoreReset: Bool = false,
        hasActiveCloudDownloadRecovery: Bool = false
    ) {
        self.isSyncEnabled = isSyncEnabled
        self.persistenceMode = persistenceMode
        self.hasPendingUploadRecovery =
            hasPendingUploadRecovery
        self.hasPendingDownloadRecovery =
            hasPendingDownloadRecovery
        self.hasQueuedCloudReconciliation =
            hasQueuedCloudReconciliation
        self.hasActiveCloudReconciliation =
            hasActiveCloudReconciliation
        self.hasCloudRecoveryStoreReset =
            hasCloudRecoveryStoreReset
        self.hasActiveCloudDownloadRecovery =
            hasActiveCloudDownloadRecovery
    }
}

nonisolated struct SyncLocalMutationRecordingPolicy:
    Equatable,
    Sendable
{
    let state: SyncLocalMutationPolicyState
    private let cloudMode: String
    private let localMode: String
    private let localFallbackMode: String

    init(
        state: SyncLocalMutationPolicyState,
        cloudMode: String,
        localMode: String,
        localFallbackMode: String
    ) {
        self.state = state
        self.cloudMode = cloudMode
        self.localMode = localMode
        self.localFallbackMode = localFallbackMode
    }

    var isCloudActive: Bool {
        state.persistenceMode == cloudMode
    }

    var shouldStageForCloudRecovery: Bool {
        guard state.isSyncEnabled else { return false }
        return state.persistenceMode == localMode ||
            state.persistenceMode == localFallbackMode
    }

    var hasPendingUploadRecovery: Bool {
        state.hasPendingUploadRecovery
    }

    var recoveryMirrorIntent: SyncPendingLocalIntent {
        if state.hasQueuedCloudReconciliation ||
            state.hasActiveCloudReconciliation
        {
            return .reconcileWithCloud
        }
        if state.hasPendingUploadRecovery ||
            state.hasCloudRecoveryStoreReset
        {
            return .explicitlyReplaceCloud
        }
        return .reconcileWithCloud
    }

    var shouldRecordSnapshot: Bool {
        isCloudActive ||
            shouldStageForCloudRecovery ||
            hasPendingUploadRecovery
    }

    var shouldRequestCloudReconciliationReset: Bool {
        shouldStageForCloudRecovery &&
            !state.hasPendingUploadRecovery &&
            !state.hasPendingDownloadRecovery &&
            !state.hasActiveCloudDownloadRecovery
    }

    @MainActor
    static func current() -> Self {
        SyncLocalMutationRecordingPolicySource
            .appDefaults()
            .current()
    }
}

nonisolated struct SyncLocalMutationRecordingPolicySource:
    Sendable
{
    private let readCurrent:
        @Sendable () -> SyncLocalMutationRecordingPolicy

    init(
        current:
        @escaping @Sendable () -> SyncLocalMutationRecordingPolicy
    ) {
        readCurrent = current
    }

    func current() -> SyncLocalMutationRecordingPolicy {
        readCurrent()
    }

    @MainActor
    static func appDefaults() -> Self {
        let defaultsReference =
            SyncLocalMutationUserDefaultsReference(
                AppDefaults.shared
            )
        let enabledKey = AppCloudSync.enabledKey
        let modeKey = AppCloudSync.modeKey
        let pendingUploadKey =
            AppCloudSync.pendingCloudUploadResetKey
        let pendingDownloadKey =
            AppCloudSync.pendingCloudDownloadResetKey
        let queuedReconciliationKey =
            AppCloudSync.queuedCloudReconciliationKey
        let activeReconciliationKey =
            AppCloudSync.activeCloudReconciliationKey
        let recoveryStoreResetKey =
            AppCloudSync.cloudRecoveryStoreResetKey
        let activeDownloadKey =
            AppCloudSync.activeCloudDownloadRecoveryKey
        let cloudMode = AppCloudSync.modeICloud
        let localMode = AppCloudSync.modeLocal
        let localFallbackMode = AppCloudSync.modeLocalFallback

        return Self {
            let defaults = defaultsReference.value
            let isEnabled =
                defaults.object(forKey: enabledKey) == nil ||
                defaults.bool(forKey: enabledKey)
            return SyncLocalMutationRecordingPolicy(
                state: SyncLocalMutationPolicyState(
                    isSyncEnabled: isEnabled,
                    persistenceMode:
                    defaults.string(forKey: modeKey) ??
                        localMode,
                    hasPendingUploadRecovery:
                    defaults.bool(forKey: pendingUploadKey),
                    hasPendingDownloadRecovery:
                    defaults.bool(forKey: pendingDownloadKey),
                    hasQueuedCloudReconciliation:
                    defaults.bool(
                        forKey: queuedReconciliationKey
                    ),
                    hasActiveCloudReconciliation:
                    defaults.bool(
                        forKey: activeReconciliationKey
                    ),
                    hasCloudRecoveryStoreReset:
                    defaults.bool(
                        forKey: recoveryStoreResetKey
                    ),
                    hasActiveCloudDownloadRecovery:
                    defaults.bool(forKey: activeDownloadKey)
                ),
                cloudMode: cloudMode,
                localMode: localMode,
                localFallbackMode: localFallbackMode
            )
        }
    }
}

/// `UserDefaults` supports concurrent reads and writes but Foundation does not
/// yet declare the reference type `Sendable`.
private final nonisolated class
SyncLocalMutationUserDefaultsReference: @unchecked Sendable {
    let value: UserDefaults

    init(_ value: UserDefaults) {
        self.value = value
    }
}

nonisolated enum SyncLocalMutationRecordingError:
    Error,
    Equatable,
    Sendable
{
    case policyChanged
}

nonisolated enum PersistentHistorySyncSnapshotCheckpoint:
    Equatable,
    Sendable
{
    case beforeFreshContext
    case beforeStateRead
    case beforeCapture
    case beforeFingerprint
    case beforeStateWrite
    case afterStateWriteBeforeReset
}

nonisolated struct PersistentHistorySyncSnapshotWorkerHooks: Sendable {
    let reach: @Sendable (
        PersistentHistorySyncSnapshotCheckpoint
    ) -> Void

    init(
        reach: @escaping @Sendable (
            PersistentHistorySyncSnapshotCheckpoint
        ) -> Void = { _ in }
    ) {
        self.reach = reach
    }
}

nonisolated struct SyncLocalMutationRecordingOutcome: Sendable {
    let result: SyncLocalMutationSnapshotResult
    let cloudReconciliationResetPolicy:
        SyncLocalMutationRecordingPolicy?
}

extension SyncConflictService {
    @discardableResult
    func recordLocalMutation(context: ModelContext) throws -> SyncLocalMutationSnapshotResult {
        try recordLocalMutation(context: context, events: [.fullSync])
    }

    @discardableResult
    func recordLocalMutation(context: ModelContext, events: Set<StoreDomainEvent>) throws -> SyncLocalMutationSnapshotResult {
        let policySource =
            SyncLocalMutationRecordingPolicySource.appDefaults()
        guard policySource.current().shouldRecordSnapshot else {
            return .notRecorded
        }
        let outcome = try withLockedFreshStoreContext(context: context) { lockedContext in
            try withExclusiveStateAccess {
                try recordLocalMutationWithLockedState(
                    context: lockedContext,
                    events: events,
                    policySource: policySource,
                    hooks: .init()
                )
            }
        }
        if let expectedPolicy =
            outcome.cloudReconciliationResetPolicy
        {
            _ = AppCloudSync
                .requestCloudReconciliationReset(
                    ifCurrentPolicyMatches: expectedPolicy
                )
        }
        return outcome.result
    }

    nonisolated func recordLocalMutationWithLockedState(
        context: ModelContext,
        events: Set<StoreDomainEvent>,
        policySource: SyncLocalMutationRecordingPolicySource,
        hooks: PersistentHistorySyncSnapshotWorkerHooks
    ) throws -> SyncLocalMutationRecordingOutcome {
        hooks.reach(.beforeStateRead)
        let policy = policySource.current()
        guard policy.shouldRecordSnapshot else {
            return SyncLocalMutationRecordingOutcome(
                result: .notRecorded,
                cloudReconciliationResetPolicy: nil
            )
        }
        var state = try loadStateWithLockedState(
            recoveryMirrorIntent: policy.recoveryMirrorIntent
        )
        let stateBeforeRecording = state
        let previousLocalFingerprint = state.localFingerprint
        let baseline: SyncDataSnapshot? = if state.pendingConflictID != nil {
            state.pendingConflictWorkingSnapshot ??
                state.pendingCloudSnapshot ??
                state.localSnapshot
        } else {
            state.localSnapshot ?? state.pendingForcedUploadSnapshot
        }
        hooks.reach(.beforeCapture)
        let snapshot = try SyncDataSnapshot.capture(
            context: context,
            updating: baseline,
            domains: snapshotDomains(for: events)
        )

        if policy.isCloudActive {
            if state.pendingConflictID != nil,
               var localSnapshot = state.localSnapshot,
               let workingSnapshot = state.pendingConflictWorkingSnapshot ?? state.pendingCloudSnapshot
            {
                localSnapshot.applyChanges(from: workingSnapshot, to: snapshot)
                state.localSnapshot = localSnapshot
                state.localFingerprint = try fingerprint(
                    localSnapshot,
                    hooks: hooks
                )
                state.pendingConflictWorkingSnapshot = snapshot
                if state.localFingerprint != previousLocalFingerprint {
                    state.rotatePendingConflictIdentity()
                }
            } else {
                state.localSnapshot = snapshot
                state.localFingerprint = try fingerprint(
                    snapshot,
                    hooks: hooks
                )
            }
            if state.pendingLocalIntent == .explicitlyReplaceCloud {
                state.pendingForcedUploadSnapshot = snapshot
            }
            guard state != stateBeforeRecording else {
                try requireCurrentPolicy(
                    policy,
                    from: policySource
                )
                return SyncLocalMutationRecordingOutcome(
                    result: .recorded(prompt: prompt(from: state)),
                    cloudReconciliationResetPolicy: nil
                )
            }
            state.advanceLocalGeneration()
            hooks.reach(.beforeStateWrite)
            try requireCurrentPolicy(
                policy,
                from: policySource
            )
            try saveStateWithoutLock(state)
            // A policy transition can race the durable write from another
            // executor. The sidecar remains a safe recovery snapshot, but the
            // history cursor must not acknowledge the old policy branch.
            try requireCurrentPolicy(
                policy,
                from: policySource
            )
            return SyncLocalMutationRecordingOutcome(
                result: .recorded(prompt: prompt(from: state)),
                cloudReconciliationResetPolicy: nil
            )
        }

        if snapshot.hasProtectableUserContent {
            if policy.shouldStageForCloudRecovery,
               !policy.hasPendingUploadRecovery
            {
                state.advanceSyncEpoch()
            }
            state.localSnapshot = snapshot
            state.localFingerprint = try fingerprint(
                snapshot,
                hooks: hooks
            )
            state.pendingForcedUploadSnapshot = snapshot
            if state.pendingLocalIntent != .explicitlyReplaceCloud {
                state.pendingLocalIntent = .reconcileWithCloud
            }
            guard state != stateBeforeRecording else {
                try requireCurrentPolicy(
                    policy,
                    from: policySource
                )
                return SyncLocalMutationRecordingOutcome(
                    result: .recorded(prompt: prompt(from: state)),
                    cloudReconciliationResetPolicy: nil
                )
            }
            state.advanceLocalGeneration()
            hooks.reach(.beforeStateWrite)
            try requireCurrentPolicy(
                policy,
                from: policySource
            )
            try saveStateWithoutLock(state)
        }
        try requireCurrentPolicy(
            policy,
            from: policySource
        )
        return SyncLocalMutationRecordingOutcome(
            result: .recorded(prompt: prompt(from: state)),
            cloudReconciliationResetPolicy:
            snapshot.hasProtectableUserContent &&
                policy.shouldRequestCloudReconciliationReset
                ? policy
                : nil
        )
    }

    private nonisolated func requireCurrentPolicy(
        _ expected: SyncLocalMutationRecordingPolicy,
        from source: SyncLocalMutationRecordingPolicySource
    ) throws {
        guard source.current() == expected else {
            throw SyncLocalMutationRecordingError.policyChanged
        }
    }

    private nonisolated func fingerprint(
        _ snapshot: SyncDataSnapshot,
        hooks: PersistentHistorySyncSnapshotWorkerHooks
    ) throws -> String {
        hooks.reach(.beforeFingerprint)
        return try snapshot.fingerprint()
    }

    private nonisolated func snapshotDomains(
        for events: Set<StoreDomainEvent>
    ) -> Set<SyncSnapshotDomain> {
        guard events.isEmpty == false else { return Set(SyncSnapshotDomain.allCases) }
        if events.contains(.fullSync) || events.contains(.remoteImportCompleted) {
            return Set(SyncSnapshotDomain.allCases)
        }

        return events.reduce(into: Set<SyncSnapshotDomain>()) { domains, event in
            switch event {
            case .taskChanged:
                domains.insert(.tasks)
            case .ledgerChanged:
                domains.insert(.ledger)
            case .pomodoroChanged:
                domains.formUnion([.ledger, .pomodoro])
            case .preferenceChanged:
                domains.insert(.preferences)
            case .countdownChanged:
                domains.insert(.countdown)
            case .checklistChanged:
                domains.insert(.checklist)
            case .inboxChanged:
                domains.insert(.inbox)
            case .remoteImportCompleted, .fullSync:
                domains.formUnion(SyncSnapshotDomain.allCases)
            }
        }
    }
}
