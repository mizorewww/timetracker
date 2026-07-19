import Foundation

/// Treats a short stop followed by a restart as one continuous ordinary timer.
///
/// Manual, imported, and Pomodoro records retain their explicit boundaries.
/// The persistence owner separately verifies canonical session relationships
/// and that no other visible work occupies the gap.
nonisolated struct TimerRapidRestartPolicy {
    static let maximumGap: TimeInterval = 60

    func shouldCoalesce(
        previousTaskID: UUID,
        previousSource: TimeSessionSource,
        previousStartedAt: Date,
        previousEndedAt: Date?,
        nextTaskID: UUID,
        nextSource: TimeSessionSource,
        nextStartedAt: Date
    ) -> Bool {
        guard previousTaskID == nextTaskID,
              supportsCoalescing(previousSource),
              supportsCoalescing(nextSource),
              let previousEndedAt,
              previousEndedAt > previousStartedAt else {
            return false
        }

        let gap = nextStartedAt.timeIntervalSince(previousEndedAt)
        return gap >= 0 && gap < Self.maximumGap
    }

    func supportsCoalescing(_ source: TimeSessionSource) -> Bool {
        switch source {
        case .timer, .shortcut, .watch, .widget, .liveActivity:
            true
        case .manual, .pomodoro, .importCalendar:
            false
        }
    }
}
