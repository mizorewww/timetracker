import Foundation
import SwiftData

extension TimeTrackerStore {
    func startPomodoroForSelectedTask(
        focusSeconds: Int = 25 * 60,
        breakSeconds: Int = 5 * 60,
        longBreakSeconds: Int? = nil,
        targetRounds: Int = 1
    ) {
        guard let selectedTaskID else {
            fail(.pomodoroTaskSelectionRequired)
            return
        }
        _ = startPomodoro(
            taskID: selectedTaskID,
            focusSeconds: focusSeconds,
            breakSeconds: breakSeconds,
            longBreakSeconds: longBreakSeconds,
            targetRounds: targetRounds
        )
    }

    @discardableResult
    func startPomodoro(
        taskID: UUID,
        focusSeconds: Int = 25 * 60,
        breakSeconds: Int = 5 * 60,
        longBreakSeconds: Int? = nil,
        targetRounds: Int = 1
    ) -> Bool {
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try StoreScopedPomodoroCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).start(
                taskID: taskID,
                focusSeconds: focusSeconds,
                breakSeconds: breakSeconds,
                longBreakSeconds: longBreakSeconds,
                targetRounds: targetRounds,
                allowParallelTimers: preferences.allowParallelTimers
            )
            finishStoreScopedPomodoroMutation(
                events: outcome.events,
                referencedTaskIDs: outcome.referencedTaskIDs
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func completeActivePomodoroFocus() -> Bool {
        guard let run = activePomodoroRun,
              run.state == .focusing || run.state == .interrupted else {
            return false
        }
        let expectedState = run.state
        let completion: Bool? = performMutation(
            eventsForOutcome: { _ in
                [.pomodoroChanged(runID: run.id, sessionID: run.sessionID, taskID: run.taskID)]
            }
        ) {
            let didComplete = try pomodoroCommandHandler.completeFocus(
                runID: run.id,
                expectedState: expectedState,
                repository: requiredPomodoroRepository()
            )
            return didComplete ? true : nil
        }
        return completion == true
    }

    @discardableResult
    func resumeActivePomodoroAfterBreak(
        phase: PomodoroPhaseToken
    ) -> Bool {
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try StoreScopedPomodoroCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).resume(
                phase: phase,
                allowParallelTimers: preferences.allowParallelTimers
            )
            switch outcome {
            case .resumed(let mutation):
                finishStoreScopedPomodoroMutation(
                    events: mutation.events,
                    referencedTaskIDs: mutation.referencedTaskIDs
                )
                return true
            case .rejected:
                refreshStoreScopedPomodoroAdmissionReadModels()
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func cancelActivePomodoro() {
        guard let run = activePomodoroRun else { return }
        let discardRecord = shouldDiscardCancelledPomodoro(run)
        perform(event: .pomodoroChanged(runID: run.id, sessionID: run.sessionID, taskID: run.taskID)) {
            try pomodoroCommandHandler.cancel(
                run: run,
                discardRecord: discardRecord,
                repository: requiredPomodoroRepository()
            )
        }
    }

    /// Reconciles every expired focus phase from any lifecycle entry point.
    /// Multiple active runs can temporarily coexist after a cross-device merge,
    /// so processing only the newest run can leave older ledger sessions open.
    /// Break completion deliberately remains a user action so returning from a
    /// long suspension never backdates a new focus segment.
    @discardableResult
    func reconcileActivePomodoro(now: Date = Date()) -> Bool {
        let expiredRuns = activeFocusPomodoroRuns.filter { $0.phaseHasExpired(at: now) }
        guard expiredRuns.isEmpty == false else {
            schedulePomodoroReconciliation(now: now)
            return false
        }

        let events = Set(expiredRuns.map { run in
            StoreDomainEvent.pomodoroChanged(
                runID: run.id,
                sessionID: run.sessionID,
                taskID: run.taskID
            )
        })
        var didReconcile = false
        let succeeded = perform(events: events) {
            let repository = try requiredPomodoroRepository()
            for run in expiredRuns {
                let reconciled = try pomodoroCommandHandler.reconcile(
                    run: run,
                    now: now,
                    repository: repository
                )
                didReconcile = reconciled || didReconcile
            }
        }
        return succeeded && didReconcile
    }

    func schedulePomodoroReconciliation(now: Date = Date()) {
        pomodoroReconciliationTask?.cancel()
        pomodoroReconciliationTask = nil

        guard let deadline = activeFocusPomodoroRuns
            .compactMap(\.phaseDeadline)
            .min() else {
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

    private func shouldDiscardCancelledPomodoro(_ run: PomodoroRun, now: Date = Date()) -> Bool {
        guard run.completedFocusRounds == 0,
              run.state == .focusing || run.state == .interrupted else {
            return false
        }
        let segmentSeconds = pomodoroElapsedFocusSeconds(for: run, now: now)
        let fallbackSeconds = run.startedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
        let effectiveSeconds = max(segmentSeconds, fallbackSeconds)
        return effectiveSeconds < Int(Double(max(1, run.focusSecondsPlanned)) * 0.2)
    }

    private var activeFocusPomodoroRuns: [PomodoroRun] {
        pomodoroRuns.filter { run in
            run.deletedAt == nil &&
            run.endedAt == nil &&
            (run.state == .focusing || run.state == .interrupted)
        }
    }

    private func finishStoreScopedPomodoroMutation(
        events: Set<StoreDomainEvent>,
        referencedTaskIDs: Set<UUID>
    ) {
        var missingTaskRefreshError: Error?
        if referencedTaskIDs.contains(where: { taskByID[$0] == nil }) {
            do {
                try refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
            } catch {
                missingTaskRefreshError = error
            }
        }
        finishStoreScopedMutation(events: events)
        if let missingTaskRefreshError {
            errorMessage = String(
                format: AppStrings.localized("error.savedRefreshFailed"),
                missingTaskRefreshError.localizedDescription
            )
        }
    }

    private func refreshStoreScopedPomodoroAdmissionReadModels() {
        do {
            try refresh(
                plan: StoreRefreshPlan(
                    scopes: [.tasks, .ledgerVisible, .pomodoro]
                )
            )
        } catch {
            errorMessage = String(
                format: AppStrings.localized("error.savedRefreshFailed"),
                error.localizedDescription
            )
        }
    }
}
