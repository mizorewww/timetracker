import Foundation

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
        guard let task = task(for: selectedTaskID), isTaskAvailableForTracking(task) else {
            errorMessage = AppStrings.localized("systemAction.error.taskNotFound")
            return
        }
        perform(event: .pomodoroChanged(runID: nil, sessionID: nil, taskID: selectedTaskID)) {
            _ = try pomodoroCommandHandler.start(
                taskID: selectedTaskID,
                focusSeconds: focusSeconds,
                breakSeconds: breakSeconds,
                longBreakSeconds: longBreakSeconds,
                targetRounds: targetRounds,
                allowParallelTimers: preferences.allowParallelTimers,
                activeSegments: activeSegments,
                pomodoroRuns: pomodoroRuns,
                timeRepository: requiredTimeRepository(),
                pomodoroRepository: requiredPomodoroRepository(),
                context: modelContext
            )
        }
    }

    @discardableResult
    func completeActivePomodoroFocus() -> Bool {
        guard let run = activePomodoroRun,
              run.state == .focusing || run.state == .interrupted else {
            return false
        }
        let expectedState = run.state
        var didComplete = false
        let succeeded = perform(
            event: .pomodoroChanged(runID: run.id, sessionID: run.sessionID, taskID: run.taskID)
        ) {
            didComplete = try pomodoroCommandHandler.completeFocus(
                runID: run.id,
                expectedState: expectedState,
                repository: requiredPomodoroRepository()
            )
        }
        return succeeded && didComplete
    }

    @discardableResult
    func resumeActivePomodoroAfterBreak(
        runID: UUID,
        expectedState: PomodoroState
    ) -> Bool {
        guard let run = activePomodoroRun,
              run.id == runID,
              run.state == expectedState,
              expectedState == .shortBreak || expectedState == .longBreak else {
            return false
        }
        var didResume = false
        let succeeded = perform(
            events: pomodoroResumeMutationEvents(run: run)
        ) {
            guard let modelContext else { throw StoreError.notConfigured }
            didResume = try pomodoroCommandHandler.resumeFocusAfterBreak(
                runID: run.id,
                expectedState: expectedState,
                allowParallelTimers: preferences.allowParallelTimers,
                timeRepository: requiredTimeRepository(),
                repository: requiredPomodoroRepository(),
                context: modelContext
            )
        }
        return succeeded && didResume
    }

    private func pomodoroResumeMutationEvents(run: PomodoroRun) -> Set<StoreDomainEvent> {
        [
            .pomodoroChanged(runID: run.id, sessionID: run.sessionID, taskID: run.taskID)
        ]
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
}
