import Foundation

/// Produces deterministic mutation plans from an already-fetched active set.
/// Persistence, locking, and side effects belong to the coordinator that applies
/// these plans.
nonisolated struct TimerAdmissionPolicy {
    func startPlan(
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

    func stopPlan(
        target: TimerStopTarget,
        activeSegments: [TimerActiveSegmentSnapshot]
    ) -> TimerStopPlan {
        let activeSegments = canonicalSegments(activeSegments)
        let matches: [TimerActiveSegmentSnapshot]

        switch target {
        case .segment(let segmentID):
            matches = activeSegments.filter { $0.segmentID == segmentID }
        case .task(let taskID):
            matches = activeSegments.filter { $0.taskID == taskID }
        }

        return TimerStopPlan(segmentsToStop: matches)
    }

    /// Keeps one logical row per segment ID and orders it oldest first. This
    /// makes the oldest matching task segment the reusable survivor. UUID
    /// ordering is the stable tie-break when start timestamps match.
    private func canonicalSegments(
        _ segments: [TimerActiveSegmentSnapshot]
    ) -> [TimerActiveSegmentSnapshot] {
        var seenSegmentIDs: Set<UUID> = []
        return segments
            .sorted(by: segmentOrder)
            .filter { seenSegmentIDs.insert($0.segmentID).inserted }
    }

    private func segmentOrder(
        _ lhs: TimerActiveSegmentSnapshot,
        _ rhs: TimerActiveSegmentSnapshot
    ) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt < rhs.startedAt
        }
        if lhs.segmentID != rhs.segmentID {
            return uuidOrder(lhs.segmentID, rhs.segmentID)
        }
        if lhs.taskID != rhs.taskID {
            return uuidOrder(lhs.taskID, rhs.taskID)
        }
        return uuidOrder(lhs.sessionID, rhs.sessionID)
    }

    private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
