import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct SegmentRebindSnapshotTests {
    @Test @MainActor
    func rebindingSegmentRefreshesSessionSnapshotAndAuditMetadata() throws {
        let context = try makeTestContext()
        let mutationDate = Date(timeIntervalSinceReferenceDate: 200_000)
        let originalAuditDate = mutationDate.addingTimeInterval(-100)
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "task-device")
        let sourceTask = try taskRepository.createTask(
            title: "Original task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let targetTask = try taskRepository.createTask(
            title: "Rebound task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let start = mutationDate.addingTimeInterval(-600)
        let creationRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "creation-device",
            nowProvider: { mutationDate }
        )
        let segment = try creationRepository.addManualSegment(
            taskID: sourceTask.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(300),
            note: "Original note"
        )
        let session = try #require(
            try creationRepository.sessions().first { $0.id == segment.sessionID }
        )
        let originalMutationID = UUID()
        segment.updatedAt = originalAuditDate
        segment.deviceID = "creation-device"
        session.updatedAt = originalAuditDate
        session.deviceID = "creation-device"
        session.clientMutationID = originalMutationID
        try context.save()

        try SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "rebind-device",
            nowProvider: { mutationDate }
        ).updateSegment(
            segmentID: segment.id,
            taskID: targetTask.id,
            startedAt: start.addingTimeInterval(60),
            endedAt: start.addingTimeInterval(420),
            note: "Rebound note"
        )

        #expect(segment.taskID == targetTask.id)
        #expect(segment.updatedAt == mutationDate)
        #expect(segment.deviceID == "rebind-device")
        #expect(session.taskID == targetTask.id)
        #expect(session.titleSnapshot == targetTask.title)
        #expect(session.note == "Rebound note")
        #expect(session.updatedAt == mutationDate)
        #expect(session.deviceID == "rebind-device")
        #expect(session.clientMutationID != originalMutationID)
    }

    @Test @MainActor
    func editingSegmentWithinSameTaskPreservesHistoricalTitleSnapshot() throws {
        let context = try makeTestContext()
        let mutationDate = Date(timeIntervalSinceReferenceDate: 300_000)
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "task-device")
        let task = try taskRepository.createTask(
            title: "Title at creation",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let start = mutationDate.addingTimeInterval(-600)
        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "edit-device",
            nowProvider: { mutationDate }
        )
        let segment = try repository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(300),
            note: "Original note"
        )
        let session = try #require(try repository.sessions().first { $0.id == segment.sessionID })
        task.title = "Title after creation"
        let tombstonedAt = task.updatedAt.addingTimeInterval(1)
        task.deletedAt = tombstonedAt
        task.updatedAt = tombstonedAt
        task.deviceID = "legacy-sync"
        task.clientMutationID = UUID()
        try context.save()

        try repository.updateSegment(
            segmentID: segment.id,
            taskID: task.id,
            startedAt: start.addingTimeInterval(30),
            endedAt: start.addingTimeInterval(360),
            note: "Edited note"
        )

        #expect(session.taskID == task.id)
        #expect(session.titleSnapshot == "Title at creation")
        #expect(session.note == "Edited note")
        #expect(task.deletedAt != nil)
    }

    @Test @MainActor
    func missingOrDeletedRebindTargetLeavesLedgerUnchanged() throws {
        let context = try makeTestContext()
        let mutationDate = Date(timeIntervalSinceReferenceDate: 400_000)
        let originalAuditDate = mutationDate.addingTimeInterval(-100)
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "task-device")
        let sourceTask = try taskRepository.createTask(
            title: "Source task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let deletedTarget = try taskRepository.createTask(
            title: "Deleted target",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let start = mutationDate.addingTimeInterval(-600)
        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "rebind-device",
            nowProvider: { mutationDate }
        )
        let segment = try repository.addManualSegment(
            taskID: sourceTask.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(300),
            note: "Original note"
        )
        let session = try #require(try repository.sessions().first { $0.id == segment.sessionID })
        let originalMutationID = UUID()
        segment.updatedAt = originalAuditDate
        segment.deviceID = "original-segment-device"
        session.updatedAt = originalAuditDate
        session.deviceID = "original-session-device"
        session.clientMutationID = originalMutationID
        let tombstonedAt = deletedTarget.updatedAt.addingTimeInterval(1)
        deletedTarget.deletedAt = tombstonedAt
        deletedTarget.updatedAt = tombstonedAt
        deletedTarget.deviceID = "legacy-sync"
        deletedTarget.clientMutationID = UUID()
        try context.save()

        for unavailableTaskID in [UUID(), deletedTarget.id] {
            #expect(throws: TimeTrackingRepositoryError.taskUnavailable) {
                try repository.updateSegment(
                    segmentID: segment.id,
                    taskID: unavailableTaskID,
                    startedAt: start.addingTimeInterval(60),
                    endedAt: start.addingTimeInterval(420),
                    note: "Must not persist"
                )
            }

            let storedSegment = try #require(
                try context.fetch(FetchDescriptor<TimeSegment>()).first { $0.id == segment.id }
            )
            let storedSession = try #require(
                try context.fetch(FetchDescriptor<TimeSession>()).first { $0.id == session.id }
            )
            #expect(storedSegment.taskID == sourceTask.id)
            #expect(storedSegment.startedAt == start)
            #expect(storedSegment.endedAt == start.addingTimeInterval(300))
            #expect(storedSegment.updatedAt == originalAuditDate)
            #expect(storedSegment.deviceID == "original-segment-device")
            #expect(storedSession.taskID == sourceTask.id)
            #expect(storedSession.titleSnapshot == sourceTask.title)
            #expect(storedSession.note == "Original note")
            #expect(storedSession.updatedAt == originalAuditDate)
            #expect(storedSession.deviceID == "original-session-device")
            #expect(storedSession.clientMutationID == originalMutationID)
        }
    }

    @Test @MainActor
    func rebindRollsBackWhenReadOnlyStoreCannotSave() throws {
        let storeDirectory = try Self.makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let storeURL = storeDirectory.appending(path: "segment-rebind.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        let sourceTaskID = UUID()
        let targetTaskID = UUID()
        let sessionID = UUID()
        let segmentID = UUID()
        let originalMutationID = UUID()
        let originalAuditDate = Date(timeIntervalSinceReferenceDate: 500_000)
        let mutationDate = originalAuditDate.addingTimeInterval(100)
        let start = originalAuditDate.addingTimeInterval(-600)

        try Self.initializeWritableStore(at: storeURL, schema: schema) { context in
            let sourceTask = TaskNode(title: "Source task", parentID: nil, deviceID: "seed-device")
            sourceTask.id = sourceTaskID
            let targetTask = TaskNode(title: "Target task", parentID: nil, deviceID: "seed-device")
            targetTask.id = targetTaskID
            let session = TimeSession(
                taskID: sourceTaskID,
                source: .manual,
                deviceID: "original-session-device",
                startedAt: start,
                titleSnapshot: sourceTask.title
            )
            session.id = sessionID
            session.endedAt = start.addingTimeInterval(300)
            session.note = "Original note"
            session.updatedAt = originalAuditDate
            session.clientMutationID = originalMutationID
            let segment = TimeSegment(
                sessionID: sessionID,
                taskID: sourceTaskID,
                source: .manual,
                deviceID: "original-segment-device",
                startedAt: start,
                endedAt: start.addingTimeInterval(300)
            )
            segment.id = segmentID
            segment.updatedAt = originalAuditDate
            context.insert(sourceTask)
            context.insert(targetTask)
            context.insert(session)
            context.insert(segment)
        }

        let readOnlyContainer = try Self.makeReadOnlyContainer(at: storeURL, schema: schema)
        let context = ModelContext(readOnlyContainer)
        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "rebind-device",
            nowProvider: { mutationDate }
        )

        do {
            try repository.updateSegment(
                segmentID: segmentID,
                taskID: targetTaskID,
                startedAt: start.addingTimeInterval(60),
                endedAt: start.addingTimeInterval(420),
                note: "Must roll back"
            )
            Issue.record("Expected the read-only store to reject the save")
        } catch let error as TimeTrackingRepositoryError {
            Issue.record("Expected a persistence failure, got repository validation error: \(error)")
        } catch {
            // The concrete SwiftData save error is intentionally not part of the repository API.
        }

        let storedSegment = try #require(
            try context.fetch(FetchDescriptor<TimeSegment>()).first { $0.id == segmentID }
        )
        let storedSession = try #require(
            try context.fetch(FetchDescriptor<TimeSession>()).first { $0.id == sessionID }
        )
        #expect(storedSegment.taskID == sourceTaskID)
        #expect(storedSegment.startedAt == start)
        #expect(storedSegment.endedAt == start.addingTimeInterval(300))
        #expect(storedSegment.updatedAt == originalAuditDate)
        #expect(storedSegment.deviceID == "original-segment-device")
        #expect(storedSession.taskID == sourceTaskID)
        #expect(storedSession.titleSnapshot == "Source task")
        #expect(storedSession.note == "Original note")
        #expect(storedSession.updatedAt == originalAuditDate)
        #expect(storedSession.deviceID == "original-session-device")
        #expect(storedSession.clientMutationID == originalMutationID)
    }

    @MainActor
    private static func initializeWritableStore(
        at url: URL,
        schema: Schema,
        seed: (ModelContext) throws -> Void
    ) throws {
        let configuration = ModelConfiguration(
            "WritableSegmentRebindSnapshotTests-\(UUID().uuidString)",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        try seed(context)
        try context.save()
    }

    @MainActor
    private static func makeReadOnlyContainer(at url: URL, schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "ReadOnlySegmentRebindSnapshotTests-\(UUID().uuidString)",
            schema: schema,
            url: url,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static func makeStoreDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "SegmentRebindSnapshotTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
