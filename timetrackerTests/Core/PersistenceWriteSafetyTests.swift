import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct PersistenceWriteSafetyTests {
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
        #expect(source.contains("requestCloudRetryAfterRecovery()") == false)
        #expect(source.contains("removePersistentStoreFiles") == false)
    }

    @Test @MainActor
    func standaloneRepositorySaveFailureRollsBackPendingChanges() throws {
        let directory = try makeStoreDirectory()
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
                status: .completed,
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
        #expect(restored.status == .active)
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
