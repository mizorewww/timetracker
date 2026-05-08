import Foundation

extension TimeTrackerStore {
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
        let focus = todaySegments.filter { $0.source == .pomodoro }
        guard !focus.isEmpty else { return 0 }
        return aggregationService.grossSeconds(focus) / focus.count
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
        task(for: run.taskID)?.title ?? AppStrings.localized("task.deleted")
    }

    func pomodoroRemainingSeconds(for run: PomodoroRun, now: Date = Date()) -> Int {
        guard [.focusing, .interrupted].contains(run.state) else {
            return run.focusSecondsPlanned
        }
        return max(0, run.focusSecondsPlanned - pomodoroElapsedFocusSeconds(for: run, now: now))
    }

    func pomodoroProgress(for run: PomodoroRun, now: Date = Date()) -> Double {
        guard run.focusSecondsPlanned > 0 else { return 0 }
        let remaining = pomodoroRemainingSeconds(for: run, now: now)
        return min(1, max(0, 1 - Double(remaining) / Double(run.focusSecondsPlanned)))
    }

    func pomodoroStateLabel(for run: PomodoroRun) -> String {
        switch run.state {
        case .planned:
            return AppStrings.localized("pomodoro.state.ready")
        case .focusing:
            return AppStrings.localized("pomodoro.state.focus")
        case .shortBreak:
            return AppStrings.localized("pomodoro.state.shortBreak")
        case .longBreak:
            return AppStrings.localized("pomodoro.state.longBreak")
        case .completed:
            return AppStrings.localized("pomodoro.state.completed")
        case .cancelled:
            return AppStrings.localized("pomodoro.state.cancelled")
        case .interrupted:
            return AppStrings.localized("pomodoro.state.interrupted")
        }
    }

    func pomodoroElapsedFocusSeconds(for run: PomodoroRun, now: Date = Date()) -> Int {
        guard let sessionID = run.sessionID else { return 0 }
        let segments = allSegments.filter { segment in
            segment.sessionID == sessionID &&
            segment.source == .pomodoro &&
            segment.deletedAt == nil
        }
        return aggregationService.grossSeconds(segments, now: now)
    }
}
