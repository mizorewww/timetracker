import Foundation
import SwiftData

@MainActor
extension SyncDataSnapshot {
    func restoreSessions(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = try context.fetch(FetchDescriptor<TimeSession>())
            .latestByIDMarkingDuplicatesDeleted(now: now, deviceID: deviceID)
        let snapshotIDs = Set(sessions.map(\.id))
        for session in existing.values where !snapshotIDs.contains(session.id) {
            let mutationDate = PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: session.updatedAt
            )
            session.deletedAt = mutationDate
            session.updatedAt = mutationDate
            session.deviceID = deviceID
            session.clientMutationID = UUID()
        }
        for record in sessions {
            let source = TimeSessionSource(rawValue: record.sourceRaw) ?? .timer
            let existingModel = existing[record.id]
            let model = existingModel ?? TimeSession(
                taskID: record.taskID,
                source: source,
                deviceID: deviceID,
                startedAt: record.startedAt
            )
            if existingModel == nil {
                context.insert(model)
                existing[record.id] = model
            }
            let mutationDate = PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: [record.updatedAt] +
                    [existingModel?.updatedAt].compactMap { $0 }
            )
            model.id = record.id
            model.taskID = record.taskID
            model.titleSnapshot = record.titleSnapshot
            model.sourceRaw = record.sourceRaw
            model.startedAt = record.startedAt
            model.endedAt = record.endedAt
            model.note = record.note
            model.deviceID = deviceID
            model.clientMutationID = UUID()
            model.createdAt = record.createdAt
            model.updatedAt = mutationDate
            model.deletedAt = record.deletedAt
        }
    }

    func restoreSegments(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = try context.fetch(FetchDescriptor<TimeSegment>())
            .latestByIDMarkingDuplicatesDeleted(now: now, deviceID: deviceID)
        let snapshotIDs = Set(segments.map(\.id))
        for segment in existing.values where !snapshotIDs.contains(segment.id) {
            let mutationDate = PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: segment.updatedAt
            )
            segment.deletedAt = mutationDate
            segment.updatedAt = mutationDate
            segment.deviceID = deviceID
        }
        for record in segments {
            let source = TimeSessionSource(rawValue: record.sourceRaw) ?? .timer
            let existingModel = existing[record.id]
            let model = existingModel ?? TimeSegment(
                sessionID: record.sessionID,
                taskID: record.taskID,
                source: source,
                deviceID: deviceID,
                startedAt: record.startedAt,
                endedAt: record.endedAt
            )
            if existingModel == nil {
                context.insert(model)
                existing[record.id] = model
            }
            let mutationDate = PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: [record.updatedAt] +
                    [existingModel?.updatedAt].compactMap { $0 }
            )
            model.id = record.id
            model.sessionID = record.sessionID
            model.taskID = record.taskID
            model.startedAt = record.startedAt
            model.endedAt = record.endedAt
            model.sourceRaw = record.sourceRaw
            model.deviceID = deviceID
            model.createdAt = record.createdAt
            model.updatedAt = mutationDate
            model.deletedAt = record.deletedAt
        }
    }
}
