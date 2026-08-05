import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func completeActivePomodoroFocus(
        phase: PomodoroPhaseToken
    ) -> Bool {
        performStoreScopedPomodoroPhaseMutation { coordinator in
            try coordinator.complete(phase: phase)
        }
    }

    @discardableResult
    func cancelActivePomodoro(
        phase: PomodoroPhaseToken
    ) -> Bool {
        performStoreScopedPomodoroPhaseMutation { coordinator in
            try coordinator.cancel(phase: phase)
        }
    }

    /// Reconciles every expired focus phase from canonical store state.
    /// Break completion remains a user action so returning from suspension
    /// never backdates a new focus segment.
    @discardableResult
    func reconcileActivePomodoro(now: Date = Date()) -> Bool {
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try StoreScopedPomodoroCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).reconcileExpiredFocuses(observedAt: now)
            if outcome.didMutate {
                finishStoreScopedPomodoroMutation(
                    events: outcome.events,
                    referencedTaskIDs: outcome.referencedTaskIDs
                )
            } else {
                // No expired focus needed fixing: converge only the live timer
                // read models instead of running the full refresh pipeline.
                // The full pipeline invalidates analytics caches and
                // re-projects rollups, so every Pomodoro page appear used to
                // pay that cost (visible as tab-switch latency).
                try convergeLiveTimerReadModels()
            }
            return outcome.didMutate
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Lightweight convergence for page-appear paths: re-fetches pomodoro
    /// runs and the active/today segment read models only, without touching
    /// analytics revisions, rollups, or the timeline snapshot cache. The full
    /// refresh pipeline still runs for actual mutations.
    func convergeLiveTimerReadModels() throws {
        guard let timeRepository, let pomodoroRepository else { return }
        pomodoroRuns = try pomodoroRepository.runs().deduplicatedByID()
        try ledgerDomainStore.refreshVisible(repository: timeRepository)
        try refreshLedgerRelationshipVisibility()
        schedulePomodoroReconciliation(now: Date())
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

        let delay = max(0, deadline.timeIntervalSince(now))
        let nanoseconds = UInt64(min(delay, 24 * 60 * 60) * 1_000_000_000)
        pomodoroReconciliationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
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
    ) -> Bool {
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try mutation(
                StoreScopedPomodoroCommandCoordinator(
                    container: modelContext.container,
                    writeAuthorization: writeAuthorization
                )
            )
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
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
