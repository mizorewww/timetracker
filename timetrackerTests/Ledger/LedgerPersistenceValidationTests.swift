import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct LedgerPersistenceValidationTests {
    @Test @MainActor
    func exactMultibyteBoundariesAndMultilineNotePersistWithLocalWriter() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let title = Self.exactUTF8String(
            prefix: "边界任务：",
            byteCount: LedgerPersistencePolicy.maximumTitleSnapshotByteCount
        )
        let note = Self.exactUTF8String(
            prefix: "第一行\t标签\n第二行\r第三行：",
            byteCount: LedgerPersistencePolicy.maximumNoteByteCount
        )
        #expect(title.utf8.count == SyncDataSnapshotRestoreLimits.maximumTitleByteCount)
        #expect(note.utf8.count == SyncDataSnapshotRestoreLimits.maximumNoteByteCount)

        let task = TaskNode(title: title, parentID: nil, deviceID: "task-device")
        context.insert(task)
        try context.save()
        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "ledger-device",
            nowProvider: { now }
        )

        let segment = try repository.addManualSegment(
            taskID: task.id,
            startedAt: now.addingTimeInterval(-120),
            endedAt: now.addingTimeInterval(-60),
            note: note
        )
        let session = try #require(try repository.sessions().first { $0.id == segment.sessionID })

        #expect(session.titleSnapshot == title)
        #expect(session.note == note)
        #expect(session.deviceID == "ledger-device")
        #expect(segment.deviceID == "ledger-device")
    }

    @Test @MainActor
    func oversizedManualNoteIsRejectedWithoutInsertingLedgerRows() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let task = TaskNode(title: "Validated task", parentID: nil, deviceID: "task-device")
        context.insert(task)
        try context.save()
        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "ledger-device",
            nowProvider: { now }
        )
        let oversizedNote = Self.exactUTF8String(
            prefix: "备注：",
            byteCount: LedgerPersistencePolicy.maximumNoteByteCount
        ) + "x"

        #expect(throws: LedgerPersistenceValidationError.byteLimitExceeded(
            field: .note,
            actual: LedgerPersistencePolicy.maximumNoteByteCount + 1,
            maximum: LedgerPersistencePolicy.maximumNoteByteCount
        )) {
            try repository.addManualSegment(
                taskID: task.id,
                startedAt: now.addingTimeInterval(-120),
                endedAt: now.addingTimeInterval(-60),
                note: oversizedNote
            )
        }

        #expect(try context.fetch(FetchDescriptor<TimeSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).isEmpty)
    }

    @Test @MainActor
    func invalidEditTextLeavesSegmentSessionAndAuditMetadataUnchanged() throws {
        let context = try makeTestContext()
        let mutationDate = Date(timeIntervalSinceReferenceDate: 3_000_000)
        let originalAuditDate = mutationDate.addingTimeInterval(-1000)
        let sourceTask = TaskNode(title: "Source task", parentID: nil, deviceID: "task-device")
        let targetTask = TaskNode(title: "Target task", parentID: nil, deviceID: "task-device")
        context.insert(sourceTask)
        context.insert(targetTask)
        try context.save()
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
        segment.deviceID = "remote-segment-device"
        session.updatedAt = originalAuditDate
        session.deviceID = "remote-session-device"
        session.clientMutationID = originalMutationID
        try context.save()
        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "local-device",
            nowProvider: { mutationDate }
        )

        #expect(throws: LedgerPersistenceValidationError.controlCharacter(field: .note)) {
            try repository.updateSegment(
                segmentID: segment.id,
                taskID: targetTask.id,
                startedAt: start.addingTimeInterval(60),
                endedAt: start.addingTimeInterval(420),
                note: "Invalid\u{0000}note"
            )
        }

        targetTask.title = "Invalid\nTitle"
        try context.save()
        #expect(throws: LedgerPersistenceValidationError.controlCharacter(field: .titleSnapshot)) {
            try repository.updateSegment(
                segmentID: segment.id,
                taskID: targetTask.id,
                startedAt: start.addingTimeInterval(60),
                endedAt: start.addingTimeInterval(420),
                note: "Valid note"
            )
        }

        #expect(segment.taskID == sourceTask.id)
        #expect(segment.startedAt == start)
        #expect(segment.endedAt == start.addingTimeInterval(300))
        #expect(segment.updatedAt == originalAuditDate)
        #expect(segment.deviceID == "remote-segment-device")
        #expect(session.taskID == sourceTask.id)
        #expect(session.titleSnapshot == sourceTask.title)
        #expect(session.note == "Original note")
        #expect(session.updatedAt == originalAuditDate)
        #expect(session.deviceID == "remote-session-device")
        #expect(session.clientMutationID == originalMutationID)
    }

    @Test @MainActor
    func invalidTitleSnapshotsAreRejectedBeforeStartingSessions() throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Invalid\nTitle", parentID: nil, deviceID: "task-device")
        context.insert(task)
        try context.save()
        let repository = SwiftDataTimeTrackingRepository(context: context, deviceID: "ledger-device")

        #expect(throws: LedgerPersistenceValidationError.controlCharacter(field: .titleSnapshot)) {
            try repository.startTask(taskID: task.id, source: .timer)
        }

        task.title = Self.exactUTF8String(
            prefix: "任务：",
            byteCount: LedgerPersistencePolicy.maximumTitleSnapshotByteCount
        ) + "x"
        try context.save()
        #expect(throws: LedgerPersistenceValidationError.byteLimitExceeded(
            field: .titleSnapshot,
            actual: LedgerPersistencePolicy.maximumTitleSnapshotByteCount + 1,
            maximum: LedgerPersistencePolicy.maximumTitleSnapshotByteCount
        )) {
            try repository.startTask(taskID: task.id, source: .timer)
        }

        #expect(try context.fetch(FetchDescriptor<TimeSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).isEmpty)
    }

    @Test @MainActor
    func failedManualInsertRollsBackBothNewRows() throws {
        let storeDirectory = try Self.makeStoreDirectory()
        let storeURL = storeDirectory.appending(path: "manual-insert.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        let taskID = UUID()
        let now = Date(timeIntervalSinceReferenceDate: 4_000_000)
        try Self.initializeWritableStore(at: storeURL, schema: schema) { context in
            let task = TaskNode(title: "Read-only task", parentID: nil, deviceID: "seed-device")
            task.id = taskID
            context.insert(task)
        }

        try autoreleasepool {
            let context = try ModelContext(Self.makeReadOnlyContainer(at: storeURL, schema: schema))
            let repository = SwiftDataTimeTrackingRepository(
                context: context,
                deviceID: "local-device",
                nowProvider: { now }
            )
            do {
                try repository.addManualSegment(
                    taskID: taskID,
                    startedAt: now.addingTimeInterval(-120),
                    endedAt: now.addingTimeInterval(-60),
                    note: "Must roll back"
                )
                Issue.record("Expected the read-only store to reject the manual insert")
            } catch let error as LedgerPersistenceValidationError {
                Issue.record("Expected a persistence failure, got validation error: \(error)")
            } catch {
                // The concrete SwiftData save error is intentionally not part of the repository API.
            }

            #expect(try context.fetch(FetchDescriptor<TimeSession>()).isEmpty)
            #expect(try context.fetch(FetchDescriptor<TimeSegment>()).isEmpty)
        }
    }

    @Test @MainActor
    func failedSessionStopRollsBackEverySegmentAndSessionMutation() throws {
        let storeDirectory = try Self.makeStoreDirectory()
        let storeURL = storeDirectory.appending(path: "session-stop.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        let taskID = UUID()
        let sessionID = UUID()
        let segmentIDs = [UUID(), UUID()]
        let originalMutationID = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 5_000_000)
        let mutationDate = start.addingTimeInterval(600)
        try Self.initializeWritableStore(at: storeURL, schema: schema) { context in
            let task = TaskNode(title: "Atomic stop", parentID: nil, deviceID: "seed-device")
            task.id = taskID
            let session = TimeSession(
                taskID: taskID,
                source: .timer,
                deviceID: "remote-session-device",
                startedAt: start,
                titleSnapshot: task.title
            )
            session.id = sessionID
            session.updatedAt = start
            session.clientMutationID = originalMutationID
            context.insert(task)
            context.insert(session)
            for (index, segmentID) in segmentIDs.enumerated() {
                let segment = TimeSegment(
                    sessionID: sessionID,
                    taskID: taskID,
                    source: .timer,
                    deviceID: "remote-segment-device",
                    startedAt: start.addingTimeInterval(Double(index * 60))
                )
                segment.id = segmentID
                segment.updatedAt = start
                context.insert(segment)
            }
        }

        try autoreleasepool {
            let context = try ModelContext(Self.makeReadOnlyContainer(at: storeURL, schema: schema))
            let repository = SwiftDataTimeTrackingRepository(
                context: context,
                deviceID: "local-device",
                nowProvider: { mutationDate }
            )
            do {
                try repository.stopSession(sessionID: sessionID)
                Issue.record("Expected the read-only store to reject the session stop")
            } catch {
                // The concrete SwiftData save error is intentionally not part of the repository API.
            }

            let session = try #require(
                try context.fetch(FetchDescriptor<TimeSession>()).first { $0.id == sessionID }
            )
            let segments = try context.fetch(FetchDescriptor<TimeSegment>())
                .filter { segmentIDs.contains($0.id) }
            #expect(session.endedAt == nil)
            #expect(session.updatedAt == start)
            #expect(session.deviceID == "remote-session-device")
            #expect(session.clientMutationID == originalMutationID)
            #expect(segments.count == segmentIDs.count)
            #expect(segments.allSatisfy { $0.endedAt == nil })
            #expect(segments.allSatisfy { $0.updatedAt == start })
            #expect(segments.allSatisfy { $0.deviceID == "remote-segment-device" })
        }
    }

    private static func exactUTF8String(prefix: String, byteCount: Int) -> String {
        precondition(prefix.utf8.count <= byteCount)
        let remaining = byteCount - prefix.utf8.count
        return prefix
            + String(repeating: "🧭", count: remaining / 4)
            + String(repeating: "x", count: remaining % 4)
    }

    @MainActor
    private static func initializeWritableStore(
        at url: URL,
        schema: Schema,
        seed: (ModelContext) throws -> Void
    ) throws {
        let configuration = ModelConfiguration(
            "WritableLedgerPersistenceTests-\(UUID().uuidString)",
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
            "ReadOnlyLedgerPersistenceTests-\(UUID().uuidString)",
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
        // SwiftData can close SQLite sidecar descriptors asynchronously. Keep these
        // unique stores in the sandbox temp directory and let the OS clean them up.
        let url = FileManager.default.temporaryDirectory.appending(
            path: "LedgerPersistenceValidationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
