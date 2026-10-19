import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func cancelActivePomodoro(
        phase: PomodoroPhaseToken
    ) throws -> Bool {
        try performStoreScopedPomodoroPhaseMutation { coordinator in
            try coordinator.cancel(phase: phase)
        }
    }

    /// Reconciles every expired focus phase from canonical store state.
    /// Break completion remains a user action so returning from suspension
    /// never backdates a new focus segment. Runs from lifecycle and timer
    /// paths with no initiating view, so a failure is logged and retried on
    /// the next reconciliation.
    @discardableResult
    func reconcileActivePomodoro(now: Date = Date()) -> Bool {
        do {
            return try reconcileActivePomodoroThrowing(now: now)
        } catch {
            logUnpresentedFailure("Pomodoro reconciliation", error)
            return false
        }
    }

    private func reconcileActivePomodoroThrowing(now: Date) throws -> Bool {
        try performStoreCommand(
            command: { session in
                try StoreScopedPomodoroCommandCoordinator(
                    session: session
                ).reconcileExpiredFocuses(observedAt: now)
            },
            finish: { outcome in
                if outcome.didMutate {
                    finishStoreScopedPomodoroMutation(
                        events: outcome.events,
                        referencedTaskIDs: outcome.referencedTaskIDs
                    )
                } else {
                    // No expired focus needed fixing: converge only the live
                    // timer read models instead of running the full refresh
                    // pipeline. The full pipeline invalidates analytics caches
                    // and re-projects rollups, so every Pomodoro page appear
                    // used to pay that cost (visible as tab-switch latency).
                    try convergeLiveTimerReadModels()
                }
            }
        ).didMutate
    }

    /// Lightweight convergence for page-appear paths: re-fetches pomodoro
    /// runs and the active/today segment read models only. Rollups consume
    /// the resulting segment deltas; analytics caches are invalidated only
    /// when another writer actually changed a visible segment.
    func convergeLiveTimerReadModels() throws {
        guard let timeRepository else { return }
        try refreshPomodoroDomain()
        ledgerDomainStore.resetRollupChanges()
        try ledgerDomainStore.refreshVisible(repository: timeRepository)
        try refreshLedgerRelationshipVisibility()
        let segmentChanges = ledgerDomainStore.rollupChanges
        if segmentChanges.isEmpty == false {
            rollupDomainStore.refreshAffected(
                directTaskIDs: [],
                explicitAncestorTaskIDs: [],
                segmentChanges: segmentChanges,
                checklistItemsByTaskID: [:],
                forecastEligibleTaskIDs: forecastEligibleTaskIDs(),
                now: Date()
            )
        }
        if segmentChanges.contains(where: { $0.before != $0.after }) {
            refreshAnalyticsDomain()
        }
        // This path changes the visible ledger without bumping
        // analyticsRevision, so the revision-keyed Today read model would
        // serve stale active segments. Invalidate it explicitly.
        todayReadModelCache = TodayReadModelCache()
    }

    func schedulePomodoroReconciliation(now: Date = Date()) {
        pomodoroReconciliationTask?.cancel()
        pomodoroReconciliationTask = nil

        guard let deadline = activeFocusPomodoroRuns
            .compactMap(\.phaseDeadline)
            .min()
        else {
            return
        }

        // Re-arm at least daily so a far deadline never needs one huge sleep.
        let delay = min(max(0, deadline.timeIntervalSince(now)), 24 * 60 * 60)
        pomodoroReconciliationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.reconcileActivePomodoro(now: Date())
        }
    }

    private var activeFocusPomodoroRuns: [PomodoroRun] {
        pomodoroRuns.filter { run in
            run.deletedAt == nil &&
                run.endedAt == nil &&
                (run.state == .focusing || run.state == .interrupted)
        }
    }

    private func performStoreScopedPomodoroPhaseMutation(
        _ mutation: (
            StoreScopedPomodoroCommandCoordinator
        ) throws -> StoreScopedPomodoroPhaseMutationOutcome
    ) throws -> Bool {
        try performStoreCommand(
            command: { session in
                try mutation(
                    StoreScopedPomodoroCommandCoordinator(
                        session: session
                    )
                )
            },
            finishResult: { outcome in
                switch outcome {
                case let .mutated(snapshot):
                    finishStoreScopedPomodoroMutation(
                        events: snapshot.events,
                        referencedTaskIDs: snapshot.referencedTaskIDs
                    )
                    return true
                case .rejected:
                    refreshStoreScopedTimerReadModels()
                    return false
                }
            }
        )
    }
}
