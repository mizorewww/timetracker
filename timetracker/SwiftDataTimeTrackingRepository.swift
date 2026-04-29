import Foundation
import SwiftData

@MainActor
final class SwiftDataTimeTrackingRepository: TimeTrackingRepository {
    private let context: ModelContext
    private let deviceID: String

    init(context: ModelContext, deviceID: String? = nil) {
        self.context = context
        self.deviceID = deviceID ?? DeviceIdentity.current
    }

    func activeSegments() throws -> [TimeSegment] {
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.deletedAt == nil && $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try context.fetch(descriptor)
    }

    func pausedSessions() throws -> [TimeSession] {
        let descriptor = FetchDescriptor<TimeSession>(
            predicate: #Predicate { $0.deletedAt == nil && $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let activeSessionIDs = Set(try activeSegments().map(\.sessionID))
        return try context.fetch(descriptor).filter { !activeSessionIDs.contains($0.id) }
    }

    func sessions() throws -> [TimeSession] {
        let descriptor = FetchDescriptor<TimeSession>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func segments(from: Date, to: Date) throws -> [TimeSegment] {
        try segments(from: from, to: to, now: Date())
    }

    func segments(from: Date, to: Date, now: Date) throws -> [TimeSegment] {
        let upperBound = to
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.deletedAt == nil && $0.startedAt < upperBound },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try context.fetch(descriptor).filter { segment in
            let end = min(segment.endedAt ?? now, upperBound)
            return end > from
        }
    }

    func allSegments() throws -> [TimeSegment] {
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try context.fetch(descriptor)
    }

    @discardableResult
    func startTask(taskID: UUID, source: TimeSessionSource) throws -> TimeSegment {
        let session = TimeSession(taskID: taskID, source: source, deviceID: deviceID, titleSnapshot: try titleSnapshot(for: taskID))
        let segment = TimeSegment(sessionID: session.id, taskID: taskID, source: source, deviceID: deviceID)
        context.insert(session)
        context.insert(segment)
        try context.save()
        return segment
    }

    func stopSegment(segmentID: UUID) throws {
        guard let segment = try segment(id: segmentID), segment.endedAt == nil else { return }
        let now = Date()
        segment.endedAt = now
        segment.updatedAt = now

        if let session = try session(id: segment.sessionID),
           try activeSegments().contains(where: { $0.sessionID == session.id }) == false {
            session.endedAt = now
            session.updatedAt = now
        }

        try context.save()
    }

    func updateSegment(segmentID: UUID, taskID: UUID, startedAt: Date, endedAt: Date?, note: String?) throws {
        guard let segment = try segment(id: segmentID) else { return }
        let now = Date()
        segment.taskID = taskID
        segment.startedAt = startedAt
        segment.endedAt = endedAt
        segment.updatedAt = now

        if let session = try session(id: segment.sessionID) {
            session.taskID = taskID
            session.startedAt = try earliestStartedAt(for: session.id) ?? startedAt
            session.endedAt = endedAt == nil ? nil : try latestEndedAt(for: session.id)
            session.note = note
            session.updatedAt = now
        }

        try context.save()
    }

    func softDeleteSegment(segmentID: UUID) throws {
        guard let segment = try segment(id: segmentID) else { return }
        let now = Date()
        segment.deletedAt = now
        segment.updatedAt = now

        if let session = try session(id: segment.sessionID) {
            let remaining = try segments(in: session.id).filter { $0.id != segment.id && $0.deletedAt == nil }
            if remaining.isEmpty {
                session.deletedAt = now
                session.updatedAt = now
            } else {
                session.endedAt = remaining.contains { $0.endedAt == nil } ? nil : remaining.compactMap(\.endedAt).max()
                session.updatedAt = now
            }
        }

        try context.save()
    }

    func stopSession(sessionID: UUID) throws {
        guard let session = try session(id: sessionID), session.deletedAt == nil else { return }
        let now = Date()
        for segment in try activeSegments().filter({ $0.sessionID == sessionID }) {
            segment.endedAt = now
            segment.updatedAt = now
        }
        session.endedAt = now
        session.updatedAt = now
        try context.save()
    }

    func pauseSession(sessionID: UUID) throws {
        let now = Date()
        for segment in try activeSegments().filter({ $0.sessionID == sessionID }) {
            segment.endedAt = now
            segment.updatedAt = now
        }
        try context.save()
    }

    @discardableResult
    func resumeSession(sessionID: UUID) throws -> TimeSegment? {
        guard let session = try session(id: sessionID), session.deletedAt == nil else { return nil }
        let segment = TimeSegment(sessionID: session.id, taskID: session.taskID, source: TimeSessionSource(rawValue: session.sourceRaw) ?? .timer, deviceID: deviceID)
        session.endedAt = nil
        session.updatedAt = Date()
        context.insert(segment)
        try context.save()
        return segment
    }

    @discardableResult
    func addManualSegment(taskID: UUID, startedAt: Date, endedAt: Date, note: String?) throws -> TimeSegment {
        let session = TimeSession(taskID: taskID, source: .manual, deviceID: deviceID, startedAt: startedAt, titleSnapshot: try titleSnapshot(for: taskID))
        session.endedAt = endedAt
        session.note = note
        let segment = TimeSegment(sessionID: session.id, taskID: taskID, source: .manual, deviceID: deviceID, startedAt: startedAt, endedAt: endedAt)
        context.insert(session)
        context.insert(segment)
        try context.save()
        return segment
    }

    private func segment(id: UUID) throws -> TimeSegment? {
        let segmentID = id
        var descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.id == segmentID && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func segments(in sessionID: UUID) throws -> [TimeSegment] {
        let targetSessionID = sessionID
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.sessionID == targetSessionID },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try context.fetch(descriptor)
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
        let sessionID = id
        var descriptor = FetchDescriptor<TimeSession>(
            predicate: #Predicate { $0.id == sessionID && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func titleSnapshot(for taskID: UUID) throws -> String? {
        let id = taskID
        var descriptor = FetchDescriptor<TaskNode>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.title
    }
}
