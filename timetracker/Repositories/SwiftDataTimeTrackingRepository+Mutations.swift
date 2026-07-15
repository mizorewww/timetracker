import Foundation
import SwiftData

extension SwiftDataTimeTrackingRepository {
    @discardableResult
    func startTask(taskID: UUID, source: TimeSessionSource) throws -> TimeSegment {
        let session = TimeSession(taskID: taskID, source: source, deviceID: deviceID, titleSnapshot: try titleSnapshot(for: taskID))
        let segment = TimeSegment(sessionID: session.id, taskID: taskID, source: source, deviceID: deviceID)
        context.insert(session)
        context.insert(segment)
        try context.saveAfterMutationStep()
        return segment
    }

    func stopSegment(segmentID: UUID) throws {
        guard let segment = try segment(id: segmentID), segment.endedAt == nil else { return }
        let now = Date()
        let endedAt = max(now, segment.startedAt)
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

        try context.saveAfterMutationStep()
    }

    func updateSegment(segmentID: UUID, taskID: UUID, startedAt: Date, endedAt: Date?, note: String?) throws {
        if let endedAt, endedAt <= startedAt {
            throw TimeTrackingRepositoryError.invalidTimeRange
        }
        guard let segment = try segment(id: segmentID) else { return }
        let now = Date()
        segment.taskID = taskID
        segment.startedAt = startedAt
        segment.endedAt = endedAt
        segment.updatedAt = now
        segment.deviceID = deviceID

        if let session = try session(id: segment.sessionID) {
            session.taskID = taskID
            session.startedAt = try earliestStartedAt(for: session.id) ?? startedAt
            session.endedAt = endedAt == nil ? nil : try latestEndedAt(for: session.id)
            session.note = note
            session.markMutated(at: now, deviceID: deviceID)
        }

        try context.saveAfterMutationStep()
    }

    func softDeleteSegment(segmentID: UUID) throws {
        guard let segment = try segment(id: segmentID) else { return }
        let now = Date()
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

        try context.saveAfterMutationStep()
    }

    func stopSession(sessionID: UUID) throws {
        guard let session = try session(id: sessionID), session.deletedAt == nil else { return }
        let now = Date()
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
        try context.saveAfterMutationStep()
    }

    @discardableResult
    func addManualSegment(taskID: UUID, startedAt: Date, endedAt: Date, note: String?) throws -> TimeSegment {
        guard endedAt > startedAt else {
            throw TimeTrackingRepositoryError.invalidTimeRange
        }
        let session = TimeSession(taskID: taskID, source: .manual, deviceID: deviceID, startedAt: startedAt, titleSnapshot: try titleSnapshot(for: taskID))
        session.endedAt = endedAt
        session.note = note
        let segment = TimeSegment(sessionID: session.id, taskID: taskID, source: .manual, deviceID: deviceID, startedAt: startedAt, endedAt: endedAt)
        context.insert(session)
        context.insert(segment)
        try context.saveAfterMutationStep()
        return segment
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

    private func titleSnapshot(for taskID: UUID) throws -> String? {
        let id = taskID
        let descriptor = FetchDescriptor<TaskNode>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).visibleDeduplicatedByID().first?.title
    }
}
