import Foundation

/// Treats a short stop followed by a restart as one continuous ordinary timer.
///
/// Manual, imported, and Pomodoro records retain their explicit boundaries.
/// The persistence owner separately verifies canonical session relationships
/// and that no other visible work occupies the gap.
nonisolated struct TimerRapidRestartPolicy {
    static let maximumGap: TimeInterval = 60
    private static let replacementIdentityDomain =
        "timetracker.timer-rapid-restart.v1"

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
              previousEndedAt > previousStartedAt
        else {
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

    /// One predecessor can be restarted concurrently on multiple devices.
    /// Deriving the replacement identity from that persisted predecessor makes
    /// those writes physical duplicates, so the existing per-ID LWW contract
    /// can select one winner instead of publishing sibling active segments.
    ///
    /// This is a persistence identity contract. Changing the domain or byte
    /// layout would make different app versions derive different records.
    func replacementSegmentID(predecessorSegmentID: UUID) -> UUID {
        DeterministicUUID.version8(
            domain: Self.replacementIdentityDomain,
            components: [
                predecessorSegmentID.uuidString.lowercased(),
            ]
        )
    }
}
