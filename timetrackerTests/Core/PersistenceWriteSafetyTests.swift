import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct PersistenceWriteSafetyTests {
    @Test @MainActor
    func isolatedStoreDoesNotInheritOrObserveApplicationRecoveryState() throws {
        let defaults = UserDefaults.standard
        let key = AppCloudSync.activeCloudReconciliationKey
        let previousValue = defaults.object(forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.set(true, forKey: key)

        let isolatedStore = makeTestStore()
        isolatedStore.configureIfNeeded(context: try makeTestContext())
        let applicationStore = TimeTrackerStore()

        #expect(isolatedStore.effectivePersistenceWriteSafety == .ready)
        #expect(isolatedStore.syncObservers.isEmpty)
        #expect(isolatedStore.cloudAccountCheckRequestID == nil)
        #expect(applicationStore.effectivePersistenceWriteSafety != .ready)
    }

    @Test
    func recoveryDiagnosticsDescribeTheSelectedStoreWithoutChangingRecoveryState() {
        let safety = PersistenceWriteSafety.ephemeral("The database could not be opened.")
        let storeURL = URL(fileURLWithPath: "/tmp/TimeTracker/persistence.store")

        let report = safety.diagnosticReport(
            persistenceMode: AppCloudSync.modeInMemoryFallback,
            storeURL: storeURL
        )

        #expect(report.contains(safety.title))
        #expect(report.contains(safety.message))
        #expect(report.contains(AppCloudSync.modeInMemoryFallback))
        #expect(report.contains(storeURL.path))
    }

    @Test
    func recoveryScreenOffersOnlySafeLifecycleActions() throws {
        let source = try sourceText("timetracker/App/PersistenceRecoveryView.swift")

        #expect(source.contains("didCopyDiagnostics = NSPasteboard.general.setString"))
        #expect(source.contains("UIPasteboard.general.string = text"))
        #expect(source.contains("NSWorkspace.shared.open(directory)"))
        #expect(source.contains("NSApplication.shared.terminate(nil)"))
        #expect(source.contains("UIApplication.openSettingsURLString"))
        #expect(source.contains("requestCloudRetryAfterRecovery()") == false)
        #expect(source.contains("removePersistentStoreFiles") == false)
    }

    @Test @MainActor
    func standaloneRepositorySaveFailureRollsBackPendingChanges() throws {
        let directory = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "persistence.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        let taskID = UUID()
        let originalDate = Date(timeIntervalSinceReferenceDate: 50_000)
        let originalMutationID = UUID()

        try initializeWritableStore(at: storeURL, schema: schema) { context in
            let task = TaskNode(
                title: "Original task",
                parentID: nil,
                deviceID: "remote-device",
                colorHex: "112233",
                iconName: "circle"
            )
            task.id = taskID
            task.createdAt = originalDate
            task.updatedAt = originalDate
            task.clientMutationID = originalMutationID
            context.insert(task)
        }

        let context = ModelContext(try makeReadOnlyContainer(at: storeURL, schema: schema))
        let repository = SwiftDataTaskRepository(context: context, deviceID: "local-device")

        #expect(throws: (any Error).self) {
            try repository.updateTask(
                taskID: taskID,
                title: "Unsaved replacement",
                parentID: nil,
                categoryID: nil,
                colorHex: "AABBCC",
                iconName: "star",
                notes: "This mutation must be rolled back.",
                estimatedSeconds: 3_600,
                dueAt: originalDate.addingTimeInterval(86_400)
            )
        }

        let restored = try #require(
            context.fetch(FetchDescriptor<TaskNode>()).first { $0.id == taskID }
        )
        #expect(restored.title == "Original task")
        #expect(restored.statusRaw == LegacyTaskStatusRaw.active)
        #expect(restored.colorHex == "112233")
        #expect(restored.iconName == "circle")
        #expect(restored.notes == nil)
        #expect(restored.estimatedSeconds == nil)
        #expect(restored.dueAt == nil)
        #expect(restored.updatedAt == originalDate)
        #expect(restored.deviceID == "remote-device")
        #expect(restored.clientMutationID == originalMutationID)
        #expect(context.hasChanges == false)
    }

    @Test @MainActor
    func rapidRestartSaveFailureRollsBackTheWholeCanonicalization() throws {
        let directory = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "persistence.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        let taskID = UUID()
        let sessionID = UUID()
        let predecessorID = UUID()
        let startedAt = Date(timeIntervalSinceReferenceDate: 75_000)
        let stoppedAt = startedAt.addingTimeInterval(120)
        let restartedAt = stoppedAt.addingTimeInterval(30)

        try initializeWritableStore(at: storeURL, schema: schema) { context in
            let task = TaskNode(
                title: "Rollback rapid restart",
                parentID: nil,
                deviceID: "seed",
                colorHex: nil,
                iconName: nil
            )
            task.id = taskID
            task.createdAt = startedAt
            task.updatedAt = startedAt

            let session = TimeSession(
                taskID: taskID,
                source: .timer,
                deviceID: "seed",
                startedAt: startedAt,
                titleSnapshot: task.title
            )
            session.id = sessionID
            session.endedAt = stoppedAt
            session.createdAt = startedAt
            session.updatedAt = stoppedAt

            let predecessor = TimeSegment(
                sessionID: sessionID,
                taskID: taskID,
                source: .timer,
                deviceID: "seed",
                startedAt: startedAt,
                endedAt: stoppedAt
            )
            predecessor.id = predecessorID
            predecessor.createdAt = startedAt
            predecessor.updatedAt = stoppedAt

            context.insert(task)
            context.insert(session)
            context.insert(predecessor)
        }

        let readOnlyContainer = try makeReadOnlyContainer(
            at: storeURL,
            schema: schema
        )
        let coordinator = StoreScopedTimerCommandCoordinator(
            container: readOnlyContainer,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "restart",
            nowProvider: { restartedAt }
        )

        #expect(throws: (any Error).self) {
            try coordinator.start(taskID: taskID, source: .watch)
        }

        let verificationContext = ModelContext(readOnlyContainer)
        let sessions = try verificationContext.fetch(
            FetchDescriptor<TimeSession>()
        )
        let segments = try verificationContext.fetch(
            FetchDescriptor<TimeSegment>()
        )
        let session = try #require(
            sessions.deduplicatedByID().first { $0.id == sessionID }
        )
        let predecessor = try #require(
            segments.deduplicatedByID().first { $0.id == predecessorID }
        )
        let replacementID = TimerRapidRestartPolicy().replacementSegmentID(
            predecessorSegmentID: predecessorID
        )

        #expect(sessions.count == 1)
        #expect(segments.count == 1)
        #expect(session.endedAt == stoppedAt)
        #expect(session.updatedAt == stoppedAt)
        #expect(predecessor.endedAt == stoppedAt)
        #expect(predecessor.deletedAt == nil)
        #expect(predecessor.updatedAt == stoppedAt)
        #expect(segments.contains { $0.id == replacementID } == false)
        #expect(verificationContext.hasChanges == false)
    }

    @MainActor
    private func initializeWritableStore(
        at url: URL,
        schema: Schema,
        seed: (ModelContext) throws -> Void
    ) throws {
        let configuration = ModelConfiguration(
            "WritablePersistenceWriteSafetyTests-\(UUID().uuidString)",
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
    private func makeReadOnlyContainer(at url: URL, schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "ReadOnlyPersistenceWriteSafetyTests-\(UUID().uuidString)",
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

    private func makeStoreDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "PersistenceWriteSafetyTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
