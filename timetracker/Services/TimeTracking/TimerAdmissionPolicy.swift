import Foundation

/// Produces deterministic mutation plans from an already-fetched active set.
/// Persistence, locking, and side effects belong to the coordinator that applies
/// these plans.
nonisolated enum TimerAdmissionPolicy {
    static func startPlan(
        taskID: UUID,
        mode: TimerAdmissionMode,
        sameTaskBehavior: TimerSameTaskStartBehavior = .reuseOldest,
        activeSegments: [TimerActiveSegmentSnapshot]
    ) -> TimerStartPlan {
        let activeSegments = canonicalSegments(activeSegments)
        let matchingSegments = activeSegments.filter { $0.taskID == taskID }
        let survivor = sameTaskBehavior == .reuseOldest ? matchingSegments.first : nil

        var segmentsToStop = survivor == nil
            ? matchingSegments
            : Array(matchingSegments.dropFirst())
        if mode == .exclusive {
            segmentsToStop.append(contentsOf: activeSegments.filter { $0.taskID != taskID })
        }

        return TimerStartPlan(
            decision: survivor.map(TimerStartDecision.reuse) ?? .createNew,
            segmentsToStop: canonicalSegments(segmentsToStop)
        )
    }

    static func stopPlan(
        target: TimerStopTarget,
        activeSegments: [TimerActiveSegmentSnapshot]
    ) -> TimerStopPlan {
        let activeSegments = canonicalSegments(activeSegments)
        let matches: [TimerActiveSegmentSnapshot] = switch target {
        case let .segment(segmentID):
            activeSegments.filter { $0.segmentID == segmentID }
        case let .task(taskID):
            activeSegments.filter { $0.taskID == taskID }
        }

        return TimerStopPlan(segmentsToStop: matches)
    }

    /// Keeps one logical row per segment ID and orders it oldest first. This
    /// makes the oldest matching task segment the reusable survivor. UUID
    /// ordering is the stable tie-break when start timestamps match.
    private static func canonicalSegments(
        _ segments: [TimerActiveSegmentSnapshot]
    ) -> [TimerActiveSegmentSnapshot] {
        var seenSegmentIDs: Set<UUID> = []
        return segments
            .sorted(by: segmentOrder)
            .filter { seenSegmentIDs.insert($0.segmentID).inserted }
    }

    private static func segmentOrder(
        _ lhs: TimerActiveSegmentSnapshot,
        _ rhs: TimerActiveSegmentSnapshot
    ) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt < rhs.startedAt
        }
        if lhs.segmentID != rhs.segmentID {
            return lhs.segmentID < rhs.segmentID
        }
        if lhs.taskID != rhs.taskID {
            return lhs.taskID < rhs.taskID
        }
        return lhs.sessionID < rhs.sessionID
    }
}
