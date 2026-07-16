import Foundation
import SwiftData

extension SyncConflictService {
    func recordLocalMutation(context: ModelContext) throws {
        try recordLocalMutation(context: context, events: [.fullSync])
    }

    func recordLocalMutation(context: ModelContext, events: Set<StoreDomainEvent>) throws {
        guard shouldRecordLocalMutationSnapshot else { return }
        try withLockedFreshStoreContext(context: context) { lockedContext in
            try withExclusiveStateAccess {
                try recordLocalMutationWithLockedState(
                    context: lockedContext,
                    events: events
                )
            }
        }
    }

    private func recordLocalMutationWithLockedState(
        context: ModelContext,
        events: Set<StoreDomainEvent>
    ) throws {
        let isCloudActive = AppCloudSync.persistenceMode == AppCloudSync.modeICloud
        let shouldStageForCloudRecovery = AppCloudSync.shouldStageLocalMutationsForCloudRecovery
        let hasPendingUploadRecovery = UserDefaults.standard.bool(
            forKey: AppCloudSync.pendingCloudUploadResetKey
        )
        guard isCloudActive || shouldStageForCloudRecovery || hasPendingUploadRecovery else { return }

        var state = try loadState()
        let previousLocalFingerprint = state.localFingerprint
        let baseline: SyncDataSnapshot?
        if state.pendingConflictID != nil {
            baseline = state.pendingConflictWorkingSnapshot ??
                state.pendingCloudSnapshot ??
                state.localSnapshot
        } else {
            baseline = state.localSnapshot ?? state.pendingForcedUploadSnapshot
        }
        let snapshot = try SyncDataSnapshot.capture(
            context: context,
            updating: baseline,
            domains: snapshotDomains(for: events)
        )

        if isCloudActive {
            if state.pendingConflictID != nil,
               var localSnapshot = state.localSnapshot,
               let workingSnapshot = state.pendingConflictWorkingSnapshot ?? state.pendingCloudSnapshot {
                localSnapshot.applyChanges(from: workingSnapshot, to: snapshot)
                state.localSnapshot = localSnapshot
                state.localFingerprint = try localSnapshot.fingerprint()
                state.pendingConflictWorkingSnapshot = snapshot
                if state.localFingerprint != previousLocalFingerprint {
                    state.rotatePendingConflictIdentity()
                }
            } else {
                state.localSnapshot = snapshot
                state.localFingerprint = try snapshot.fingerprint()
            }
            if state.pendingLocalIntent == .explicitlyReplaceCloud {
                state.pendingForcedUploadSnapshot = snapshot
            }
            state.advanceLocalGeneration()
            try saveState(state)
            return
        }

        if snapshot.hasProtectableUserContent {
            if shouldStageForCloudRecovery && !hasPendingUploadRecovery {
                state.advanceSyncEpoch()
            }
            state.localSnapshot = snapshot
            state.localFingerprint = try snapshot.fingerprint()
            state.advanceLocalGeneration()
            state.pendingForcedUploadSnapshot = snapshot
            if state.pendingLocalIntent != .explicitlyReplaceCloud {
                state.pendingLocalIntent = .reconcileWithCloud
            }
            try saveState(state)
            if shouldStageForCloudRecovery && !hasPendingUploadRecovery {
                AppCloudSync.requestCloudReconciliationReset()
            }
        }
    }

    private var shouldRecordLocalMutationSnapshot: Bool {
        AppCloudSync.persistenceMode == AppCloudSync.modeICloud ||
            AppCloudSync.shouldStageLocalMutationsForCloudRecovery ||
            UserDefaults.standard.bool(
                forKey: AppCloudSync.pendingCloudUploadResetKey
            )
    }

    private func snapshotDomains(for events: Set<StoreDomainEvent>) -> Set<SyncSnapshotDomain> {
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
