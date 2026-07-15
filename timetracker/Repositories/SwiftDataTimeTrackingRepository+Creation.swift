import Foundation
import SwiftData

extension SwiftDataTimeTrackingRepository {
    @discardableResult
    func startTask(taskID: UUID, source: TimeSessionSource) throws -> TimeSegment {
        let now = nowProvider()
        let titleSnapshot = try preparedTrackableTitleSnapshot(for: taskID)
        return try context.performAtomicMutation {
            let session = TimeSession(
                taskID: taskID,
                source: source,
                deviceID: deviceID,
                startedAt: now,
                titleSnapshot: titleSnapshot
            )
            let segment = TimeSegment(
                sessionID: session.id,
                taskID: taskID,
                source: source,
                deviceID: deviceID,
                startedAt: now
            )
            context.insert(session)
            context.insert(segment)
            return segment
        }
    }

    @discardableResult
    func addManualSegment(taskID: UUID, startedAt: Date, endedAt: Date, note: String?) throws -> TimeSegment {
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
        let titleSnapshot = try preparedTrackableTitleSnapshot(for: taskID)
        return try context.performAtomicMutation {
            let session = TimeSession(
                taskID: taskID,
                source: .manual,
                deviceID: deviceID,
                startedAt: startedAt,
                titleSnapshot: titleSnapshot
            )
            session.endedAt = endedAt
            session.note = preparedNote
            let segment = TimeSegment(
                sessionID: session.id,
                taskID: taskID,
                source: .manual,
                deviceID: deviceID,
                startedAt: startedAt,
                endedAt: endedAt
            )
            context.insert(session)
            context.insert(segment)
            return segment
        }
    }
}
