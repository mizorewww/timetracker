import Foundation
import SwiftData

@MainActor
struct TimerRapidRestartMutation {
    let replacement: TimeSegment
    let tombstonedSegment: LedgerSegmentMutationSnapshot
}

extension SwiftDataTimeTrackingRepository {
    /// Replaces a recently closed ordinary timer with a new active segment in
    /// the same session. The new identity keeps stale exact-stop commands from
    /// closing the restarted timer, while the tombstone prevents iCloud from
    /// reviving the superseded segment.
    func startByCoalescingRapidRestart(
        taskID: UUID,
        source: TimeSessionSource,
        hasActiveSegmentForTask: Bool
    ) throws -> TimerRapidRestartMutation? {
        let policy = TimerRapidRestartPolicy()
        guard policy.supportsCoalescing(source),
              hasActiveSegmentForTask == false else {
            return nil
        }

        let resumedAt = nowProvider()
        let cutoff = resumedAt.addingTimeInterval(-TimerRapidRestartPolicy.maximumGap)
        let targetTaskID = taskID
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate {
                $0.taskID == targetTaskID &&
                    $0.startedAt < resumedAt &&
                    ($0.endedAt ?? cutoff) > cutoff &&
                    ($0.endedAt ?? resumedAt) <= resumedAt
            }
        )
        let candidateIDs = Set(try context.fetch(descriptor).map(\.id))
        let candidates = try canonicalSegments(ids: candidateIDs)
            .filter { $0.taskID == taskID }
            .sorted(by: rapidRestartCandidateOrder)
        guard let predecessor = candidates.first,
              let predecessorSource = TimeSessionSource(rawValue: predecessor.sourceRaw),
              policy.shouldCoalesce(
                previousTaskID: predecessor.taskID,
                previousSource: predecessorSource,
                previousStartedAt: predecessor.startedAt,
                previousEndedAt: predecessor.endedAt,
                nextTaskID: taskID,
                nextSource: source,
                nextStartedAt: resumedAt
              ),
              let predecessorEnd = predecessor.endedAt else {
            return nil
        }
        let replacementID = policy.replacementSegmentID(
            predecessorSegmentID: predecessor.id
        )
        let targetReplacementID = replacementID
        let replacementDescriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.id == targetReplacementID }
        )
        // A stable identity may already exist after partial CloudKit delivery
        // or an older restart generation. Never overwrite that independent LWW
        // history; fall back to a new ordinary session instead.
        guard try context.fetch(replacementDescriptor).isEmpty else {
            return nil
        }

        let interveningSegments = try segments(
            from: predecessorEnd,
            to: resumedAt,
            now: resumedAt
        )
        let sessionSegments = try segments(sessionIDs: [predecessor.sessionID])
        let hasLinkedPomodoro = try hasVisiblePomodoroRun(
            sessionID: predecessor.sessionID
        )
        guard interveningSegments.isEmpty,
              sessionSegments.map(\.id) == [predecessor.id],
              let session = try sessions(ids: [predecessor.sessionID]).first,
              session.taskID == taskID,
              session.startedAt == predecessor.startedAt,
              session.endedAt == predecessorEnd,
              session.sourceRaw == predecessor.sourceRaw,
              TimeSessionSource(rawValue: session.sourceRaw) == predecessorSource,
              hasLinkedPomodoro == false else {
            return nil
        }

        let predecessorSnapshot = LedgerSegmentMutationSnapshot(
            segment: predecessor
        )
        let mutationDate = PersistentLWWMutationDate.strictlyDominating(
            preferred: resumedAt,
            observed: predecessor.updatedAt,
            session.updatedAt
        )
        return try context.performAtomicMutation {
            let replacement = TimeSegment(
                sessionID: session.id,
                taskID: taskID,
                source: predecessorSource,
                deviceID: deviceID,
                startedAt: predecessor.startedAt
            )
            replacement.id = replacementID
            replacement.createdAt = mutationDate
            replacement.updatedAt = mutationDate

            predecessor.deletedAt = mutationDate
            predecessor.updatedAt = mutationDate
            predecessor.deviceID = deviceID

            session.endedAt = nil
            session.markMutated(at: mutationDate, deviceID: deviceID)

            context.insert(replacement)
            return TimerRapidRestartMutation(
                replacement: replacement,
                tombstonedSegment: predecessorSnapshot
            )
        }
    }

    private func hasVisiblePomodoroRun(sessionID: UUID) throws -> Bool {
        let targetSessionID = sessionID
        let descriptor = FetchDescriptor<PomodoroRun>(
            predicate: #Predicate { $0.sessionID == targetSessionID }
        )
        let candidateIDs = Set(try context.fetch(descriptor).map(\.id))
        guard candidateIDs.isEmpty == false else { return false }
        let requestedIDs = Array(candidateIDs)
        let duplicateDescriptor = FetchDescriptor<PomodoroRun>(
            predicate: #Predicate { requestedIDs.contains($0.id) }
        )
        return try context.fetch(duplicateDescriptor)
            .visibleDeduplicatedByID()
            .contains { $0.sessionID == targetSessionID }
    }

    private func rapidRestartCandidateOrder(
        _ lhs: TimeSegment,
        _ rhs: TimeSegment
    ) -> Bool {
        let lhsEnd = lhs.endedAt ?? .distantPast
        let rhsEnd = rhs.endedAt ?? .distantPast
        if lhsEnd != rhsEnd {
            return lhsEnd > rhsEnd
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
