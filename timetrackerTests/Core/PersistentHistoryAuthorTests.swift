import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct PersistentHistoryAuthorTests {
    @Test @MainActor
    func atomicMutationPersistsExplicitAuthorAndRestoresContextAuthor() throws {
        let fixture = try PersistentHistoryAuthorFixture(
            name: #function
        )
        defer { fixture.remove() }
        try fixture.withContext { context in
            context.author = "preexisting-author"

            try context.performAtomicMutation(author: .localMutation) {
                context.insert(TaskNode(
                    title: "Explicitly authored",
                    parentID: nil,
                    deviceID: "history-author-test"
                ))
            }

            #expect(context.author == "preexisting-author")
        }

        #expect(
            try fixture.historyAuthors().contains(
                TimeTrackerHistoryAuthor.localMutation.rawValue
            )
        )
    }

    @Test @MainActor
    func failedAtomicMutationRestoresAuthorAndRollsBackChanges() throws {
        enum InjectedFailure: Error {
            case failure
        }

        let context = try makeTestContext()
        context.author = "preexisting-author"

        #expect(throws: InjectedFailure.self) {
            try context.performAtomicMutation(author: .localMutation) {
                context.insert(TaskNode(
                    title: "Rolled back",
                    parentID: nil,
                    deviceID: "history-author-test"
                ))
                throw InjectedFailure.failure
            }
        }

        #expect(context.author == "preexisting-author")
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).isEmpty)
    }

    @Test @MainActor
    func sceneAndFreshCoordinatorWritesUseLocalMutationAuthor() async throws {
        let fixture = try PersistentHistoryAuthorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let scheduler = CommittedMutationSystemProjectionScheduler {
            _,
            _ in
        }
        let stateURL = fixture.directory.appendingPathComponent(
            SyncConflictService.stateFileName
        )
        let sceneTaskID = UUID()
        try fixture.withContainer { container in
            let store = TimeTrackerStore(
                appleHealthDataReader: UnavailableAppleHealthDataReader(),
                appleHealthTimelinePreferenceStore:
                TestAppleHealthTimelinePreferenceStore(),
                writeAuthorization: .isolatedTestHarness,
                syncConflictService: SyncConflictService(stateURL: stateURL),
                committedMutationSystemProjectionScheduler: scheduler
            )
            let sceneContext = ModelContext(container)
            store.configureRepositoriesIfNeeded(context: sceneContext)

            let didCommit = store.perform(
                events: [
                    .taskChanged(
                        taskID: sceneTaskID,
                        affectedAncestorIDs: []
                    ),
                ]
            ) {
                let task = TaskNode(
                    title: "Scene-authored",
                    parentID: nil,
                    deviceID: "history-author-test"
                )
                task.id = sceneTaskID
                sceneContext.insert(task)
            }
            #expect(didCommit)

            _ = try StoreScopedTimerCommandCoordinator(
                container: container,
                writeAuthorization: .isolatedTestHarness,
                deviceID: "history-author-test"
            ).start(taskID: sceneTaskID)
        }
        await scheduler.waitUntilIdle()
        await StoreMutationBroadcaster.waitUntilIdle()

        let localTransactions = try fixture.historyTransactions().filter {
            $0.author == TimeTrackerHistoryAuthor.localMutation.rawValue
        }
        #expect(localTransactions.count == 2)
        #expect(localTransactions.allSatisfy { $0.changes.isEmpty == false })
    }

    @Test @MainActor
    func syncRestoreIsNeverClassifiedAsLocalMutation() throws {
        let fixture = try PersistentHistoryAuthorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let snapshot = try fixture.withContext { context in
            let task = TaskNode(
                title: "Protected branch",
                parentID: nil,
                deviceID: "history-author-test"
            )
            try context.performAtomicMutation(author: .bootstrapMaintenance) {
                context.insert(task)
            }
            return try SyncDataSnapshot.capture(context: context)
        }
        let baselineTransactionIDs = try Set(
            fixture.historyTransactions().map(\.transactionIdentifier)
        )

        try fixture.withContext { context in
            try snapshot.restoreAsLocalWinner(context: context)
        }

        let restoreTransactions = try fixture.historyTransactions().filter {
            baselineTransactionIDs.contains($0.transactionIdentifier) == false
        }
        #expect(
            restoreTransactions.contains {
                $0.author ==
                    TimeTrackerHistoryAuthor.syncReconciliation.rawValue
            }
        )
        #expect(
            restoreTransactions.allSatisfy {
                $0.author != TimeTrackerHistoryAuthor.localMutation.rawValue
            }
        )
    }

    @Test @MainActor
    func startupConfigurationWritesUseBootstrapMaintenanceAuthor() async throws {
        let fixture = try PersistentHistoryAuthorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let defaults = AppDefaults.shared
        let migrationKey = LegacyCountdownMigrationPolicy.migrationKey
        let payloadKey = LegacyCountdownMigrationPolicy.payloadKey
        let previousMigration = defaults.object(forKey: migrationKey)
        let previousPayload = defaults.object(forKey: payloadKey)
        defer {
            if let previousMigration {
                defaults.set(previousMigration, forKey: migrationKey)
            } else {
                defaults.removeObject(forKey: migrationKey)
            }
            if let previousPayload {
                defaults.set(previousPayload, forKey: payloadKey)
            } else {
                defaults.removeObject(forKey: payloadKey)
            }
        }
        defaults.set(false, forKey: migrationKey)
        defaults.set(
            """
            [{"title":"Startup migration","date":"2030-01-01T00:00:00Z"}]
            """,
            forKey: payloadKey
        )
        let scheduler = CommittedMutationSystemProjectionScheduler {
            _,
            _ in
        }
        try fixture.withContainer { container in
            let store = TimeTrackerStore(
                appleHealthDataReader: UnavailableAppleHealthDataReader(),
                appleHealthTimelinePreferenceStore:
                TestAppleHealthTimelinePreferenceStore(),
                writeAuthorization: .isolatedTestHarness,
                syncConflictService: SyncConflictService(
                    stateURL: fixture.directory.appendingPathComponent(
                        SyncConflictService.stateFileName
                    )
                ),
                committedMutationSystemProjectionScheduler: scheduler
            )

            store.configureIfNeeded(context: ModelContext(container))
        }
        await scheduler.waitUntilIdle()

        let transactions = try fixture.historyTransactions()
        #expect(transactions.isEmpty == false)
        #expect(
            transactions.allSatisfy {
                $0.author ==
                    TimeTrackerHistoryAuthor.bootstrapMaintenance.rawValue
            }
        )
    }
}

@MainActor
private struct PersistentHistoryAuthorFixture {
    let directory: URL

    init(name: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PersistentHistoryAuthorTests-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func withContainer<Result>(
        _ operation: (ModelContainer) throws -> Result
    ) throws -> Result {
        try autoreleasepool {
            try operation(makeContainer())
        }
    }

    func withContext<Result>(
        _ operation: (ModelContext) throws -> Result
    ) throws -> Result {
        try withContainer { container in
            try operation(ModelContext(container))
        }
    }

    func historyTransactions() throws -> [DefaultHistoryTransaction] {
        try withContext { context in
            context.autosaveEnabled = false
            return try context.fetchHistory(
                HistoryDescriptor<DefaultHistoryTransaction>()
            )
        }
    }

    func historyAuthors() throws -> [String?] {
        try historyTransactions().map(\.author)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = TimeTrackerModelRegistry.currentSchema
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [
                ModelConfiguration(
                    "PersistentHistoryAuthor",
                    schema: schema,
                    url: directory.appendingPathComponent(
                        "timetracker.store"
                    ),
                    cloudKitDatabase: .none
                ),
            ]
        )
    }
}
