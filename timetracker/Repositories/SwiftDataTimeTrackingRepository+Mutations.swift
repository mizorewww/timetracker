import Foundation
import SwiftData

extension SwiftDataTimeTrackingRepository {
    func stopSegment(segmentID: UUID) throws {
        guard let segment = try segment(id: segmentID), segment.endedAt == nil else { return }
        let now = nowProvider()
        let endedAt = max(now, segment.startedAt)
        try context.performAtomicMutation {
            segment.endedAt = endedAt
            segment.updatedAt = now
            segment.deviceID = deviceID

            if let session = try session(id: segment.sessionID),
               try activeSegments(in: session.id).isEmpty {
                session.endedAt = max(
                    session.startedAt,
                    try latestEndedAt(for: session.id) ?? endedAt
                )
                session.markMutated(at: now, deviceID: deviceID)
            }
        }
    }

    func updateSegment(segmentID: UUID, taskID: UUID, startedAt: Date, endedAt: Date?, note: String?) throws {
        let now = nowProvider()
        switch TrackedTimePolicy.validateWrite(startedAt: startedAt, endedAt: endedAt, now: now) {
        case .valid:
            break
        case .invalidRange:
            throw TimeTrackingRepositoryError.invalidTimeRange
        case .futureTime:
            throw TimeTrackingRepositoryError.futureTime
        }
        let preparedNote = try LedgerPersistencePolicy.prepareNote(note)
        guard let segment = try segment(id: segmentID) else { return }
        guard segment.endedAt == nil || endedAt != nil else {
            throw TimeTrackingRepositoryError.closedSegmentCannotReopen
        }
        let linkedSession = try session(id: segment.sessionID)
        let liveSessionSegments = try segments(in: segment.sessionID).filter {
            $0.deletedAt == nil
        }
        let isRebindingTask = liveSessionSegments.contains { $0.taskID != taskID } ||
            linkedSession.map { $0.taskID != taskID } == true
        let reboundTitleSnapshot: String?
        if isRebindingTask {
            reboundTitleSnapshot = try preparedTrackableTitleSnapshot(for: taskID)
        } else {
            reboundTitleSnapshot = nil
        }

        try context.performAtomicMutation {
            for sessionSegment in liveSessionSegments where
                sessionSegment.id == segment.id || sessionSegment.taskID != taskID {
                sessionSegment.taskID = taskID
                sessionSegment.updatedAt = now
                sessionSegment.deviceID = deviceID
            }
            segment.startedAt = startedAt
            segment.endedAt = endedAt

            if let linkedSession {
                linkedSession.taskID = taskID
                if let reboundTitleSnapshot {
                    linkedSession.titleSnapshot = reboundTitleSnapshot
                }
                linkedSession.startedAt = liveSessionSegments.map(\.startedAt).min() ?? startedAt
                linkedSession.endedAt = liveSessionSegments.contains { $0.endedAt == nil }
                    ? nil
                    : max(
                        linkedSession.startedAt,
                        liveSessionSegments.compactMap(\.endedAt).max() ?? linkedSession.startedAt
                    )
                linkedSession.note = preparedNote
                linkedSession.markMutated(at: now, deviceID: deviceID)
            }
        }
    }

    func softDeleteSegment(segmentID: UUID) throws {
        guard let segment = try segment(id: segmentID) else { return }
        let now = nowProvider()
        try context.performAtomicMutation {
            segment.deletedAt = now
            segment.updatedAt = now
            segment.deviceID = deviceID

            if let session = try session(id: segment.sessionID) {
                let remaining = try segments(in: session.id).filter { $0.id != segment.id && $0.deletedAt == nil }
                if remaining.isEmpty {
                    session.deletedAt = now
                } else {
                    session.taskID = remaining[0].taskID
                    session.startedAt = remaining.map(\.startedAt).min() ?? session.startedAt
                    session.endedAt = remaining.contains { $0.endedAt == nil }
                        ? nil
                        : max(session.startedAt, remaining.compactMap(\.endedAt).max() ?? session.startedAt)
                }
                session.markMutated(at: now, deviceID: deviceID)
            }
        }
    }

    func stopSession(sessionID: UUID) throws {
        guard let session = try session(id: sessionID), session.deletedAt == nil else { return }
        let now = nowProvider()
        try context.performAtomicMutation {
            for segment in try activeSegments(in: sessionID) {
                segment.endedAt = max(now, segment.startedAt)
                segment.updatedAt = now
                segment.deviceID = deviceID
            }
            session.endedAt = max(
                session.startedAt,
                try latestEndedAt(for: sessionID) ?? now
            )
            session.markMutated(at: now, deviceID: deviceID)
        }
    }

    private func segment(id: UUID) throws -> TimeSegment? {
        try canonicalSegments(ids: [id]).first
    }

    private func segments(in sessionID: UUID) throws -> [TimeSegment] {
        let targetSessionID = sessionID
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.sessionID == targetSessionID }
        )
        let candidateIDs = Set(try context.fetch(descriptor).map(\.id))
        return try canonicalSegments(ids: candidateIDs)
            .filter { $0.sessionID == targetSessionID }
            .sorted { lhs, rhs in
                if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func activeSegments(in sessionID: UUID) throws -> [TimeSegment] {
        try segments(in: sessionID).filter { $0.endedAt == nil }
    }

    private func latestEndedAt(for sessionID: UUID) throws -> Date? {
        let sessionSegments = try segments(in: sessionID).filter { $0.deletedAt == nil }
        if sessionSegments.contains(where: { $0.endedAt == nil }) {
            return nil
        }
        return sessionSegments.compactMap(\.endedAt).max()
    }

    private func earliestStartedAt(for sessionID: UUID) throws -> Date? {
        try segments(in: sessionID)
            .filter { $0.deletedAt == nil }
            .map(\.startedAt)
            .min()
    }

    private func session(id: UUID) throws -> TimeSession? {
        try canonicalSessions(ids: [id]).first
    }
}
