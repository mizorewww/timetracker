import Foundation

extension TimeTrackerStore {
    var cancelledPomodoroSessionIDs: Set<UUID> {
        Set(pomodoroRuns.compactMap { run in
            guard run.deletedAt == nil,
                  run.state == .cancelled
            else {
                return nil
            }
            return run.sessionID
        })
    }

    var activePomodoroRun: PomodoroRun? {
        pomodoroRuns.first { run in
            run.deletedAt == nil &&
                run.endedAt == nil &&
                [.planned, .focusing, .shortBreak, .longBreak, .interrupted].contains(run.state)
        }
    }

    var completedPomodoroCount: Int {
        let today = Calendar.current.dateInterval(of: .day, for: Date())
        return pomodoroRuns.filter { run in
            run.state == .completed &&
                run.deletedAt == nil &&
                today?.contains(run.endedAt ?? run.updatedAt) == true
        }.count
    }

    var averageFocusSeconds: Int {
        averageFocusSeconds(now: Date())
    }

    func averageFocusSeconds(now: Date, calendar: Calendar = .current) -> Int {
        guard let interval = calendar.dateInterval(of: .day, for: now) else { return 0 }
        let focus = visibleSegments(overlapping: interval, now: now)
            .filter { $0.source == .pomodoro }
        guard !focus.isEmpty else { return 0 }
        let seconds = ledgerSummaryService.secondsInInterval(
            taskIDs: Set(focus.map(\.taskID)),
            segments: focus,
            interval: interval,
            mode: .gross,
            now: now
        )
        return seconds / focus.count
    }

    func activePomodoroRun(for taskID: UUID) -> PomodoroRun? {
        pomodoroRuns.first { run in
            run.taskID == taskID &&
                run.deletedAt == nil &&
                run.endedAt == nil &&
                [.planned, .focusing, .shortBreak, .longBreak, .interrupted].contains(run.state)
        }
    }

    func taskTitle(for run: PomodoroRun) -> String {
        task(for: run.taskID)?.title ?? AppStrings.localized("task.unavailable")
    }

    func pomodoroRemainingSeconds(for run: PomodoroRun, now: Date = Date()) -> Int {
        guard let deadline = run.phaseDeadline else {
            return pomodoroPlannedSeconds(for: run)
        }
        return max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    func pomodoroProgress(for run: PomodoroRun, now: Date = Date()) -> Double {
        let plannedSeconds = pomodoroPlannedSeconds(for: run)
        guard plannedSeconds > 0 else { return 0 }
        let remaining = pomodoroRemainingSeconds(for: run, now: now)
        return min(1, max(0, 1 - Double(remaining) / Double(plannedSeconds)))
    }

    func pomodoroStateLabel(for run: PomodoroRun) -> String {
        switch run.state {
        case .planned:
            AppStrings.localized("pomodoro.state.ready")
        case .focusing:
            AppStrings.localized("pomodoro.state.focus")
        case .shortBreak:
            AppStrings.localized("pomodoro.state.shortBreak")
        case .longBreak:
            AppStrings.localized("pomodoro.state.longBreak")
        case .completed:
            AppStrings.localized("pomodoro.state.completed")
        case .cancelled:
            AppStrings.localized("pomodoro.state.cancelled")
        case .interrupted:
            AppStrings.localized("pomodoro.state.interrupted")
        }
    }

    func pomodoroElapsedFocusSeconds(for run: PomodoroRun, now: Date = Date()) -> Int {
        guard let sessionID = run.sessionID else { return 0 }
        let usesRelationshipIndex = ledgerDomainStore.hasIndexedSegmentHistory
        let candidates = usesRelationshipIndex
            ? ledgerDomainStore.segments(forSessionID: sessionID)
            : allSegments.visibleDeduplicatedByID()
        let segments = candidates.filter { segment in
            (!usesRelationshipIndex || isReadableLedgerSegment(segment)) &&
                segment.sessionID == sessionID &&
                segment.source == .pomodoro &&
                segment.deletedAt == nil
        }
        return aggregationService.grossSeconds(segments, now: now)
    }

    private func pomodoroPlannedSeconds(for run: PomodoroRun) -> Int {
        switch run.state {
        case .shortBreak:
            run.breakSecondsPlanned
        case .longBreak:
            run.longBreakSecondsPlanned ?? run.breakSecondsPlanned
        case .planned, .focusing, .completed, .cancelled, .interrupted:
            run.focusSecondsPlanned
        }
    }
}
