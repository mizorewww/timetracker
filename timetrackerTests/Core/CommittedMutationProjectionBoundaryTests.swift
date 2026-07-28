import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CommittedMutationProjectionBoundaryTests {
    @Test @MainActor
    func blockedSystemProjectionsDoNotDelayCommittedMutationVisibilityOrBroadcast() async throws {
        let context = try makeTestContext()
        let gate = BlockingSystemProjectionWorker()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await gate.run(sink: sink, work: work)
        }
        let fixture = makeStoreFixture(
            scheduler: scheduler,
            name: #function
        )
        defer {
            gate.releaseAll()
            fixture.remove()
        }
        let store = fixture.store
        let observingFixture = makeStoreFixture(
            scheduler: scheduler,
            name: "\(#function)-observing"
        )
        defer {
            observingFixture.remove()
        }
        let observingStore = observingFixture.store
        let observingContext = ModelContext(context.container)
        store.configureRepositoriesIfNeeded(context: context)
        observingStore.configureRepositoriesIfNeeded(context: observingContext)
        try store.refreshCoordinator.refreshReadModels(
            store,
            plan: store.refreshPlanner.plan(after: [.fullSync])
        )
        try observingStore.refreshCoordinator.refreshReadModels(
            observingStore,
            plan: observingStore.refreshPlanner.plan(after: [.fullSync])
        )
        observingStore.installStoreMutationObserverIfNeeded()
        defer {
            observingStore.removeStoreMutationObserver()
        }

        scheduler.enqueue(
            CommittedMutationSystemProjectionReceipt(
                events: [.fullSync]
            )
        )
        for sink in CommittedMutationSystemProjectionSink.allCases {
            await gate.waitUntilBlocked(sink)
        }

        let taskID = UUID()
        let events: Set<StoreDomainEvent> = [
            .taskChanged(taskID: taskID, affectedAncestorIDs: []),
        ]
        let didCommit = store.perform(events: events) {
            _ = try SwiftDataTaskRepository(
                context: context,
                deviceID: "test"
            ).createTask(
                proposedID: taskID,
                title: "Visible before projections finish",
                parentID: nil,
                colorHex: nil,
                iconName: nil
            )
        }

        #expect(didCommit)
        #expect(
            try SwiftDataTaskRepository(
                context: ModelContext(context.container),
                deviceID: "verification"
            ).task(id: taskID)?.title == "Visible before projections finish"
        )
        #expect(store.tasks.contains { $0.id == taskID })
        #expect(observingStore.tasks.contains { $0.id == taskID } == false)
        #expect(store.errorMessage == nil)
        for sink in CommittedMutationSystemProjectionSink.allCases {
            #expect(gate.isBlocked(sink))
            #expect(gate.calls(for: sink).count == 1)
        }

        await StoreMutationBroadcaster.waitUntilIdle()

        #expect(observingStore.tasks.contains { $0.id == taskID })
        for sink in CommittedMutationSystemProjectionSink.allCases {
            #expect(gate.isBlocked(sink))
        }

        gate.releaseAll()
        await scheduler.waitUntilIdle()

        for sink in CommittedMutationSystemProjectionSink.allCases {
            let calls = gate.calls(for: sink)
            #expect(calls.count == 2)
            #expect(calls.last?.events == events)
            #expect(calls.last?.receiptIDs.count == 1)
        }
    }

    @Test @MainActor
    func systemProjectionFailureDoesNotReverseMutationOrWriteSharedErrorState() async throws {
        let context = try makeTestContext()
        let failure = FailingSystemProjectionWorker()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try failure.run(sink: sink, work: work)
        }
        let fixture = makeStoreFixture(
            scheduler: scheduler,
            name: #function
        )
        defer {
            fixture.remove()
        }
        let store = fixture.store
        store.configureRepositoriesIfNeeded(context: context)
        try store.refreshCoordinator.refreshReadModels(
            store,
            plan: store.refreshPlanner.plan(after: [.fullSync])
        )
        let existingErrorMessage = "Existing scene feedback"
        store.errorMessage = existingErrorMessage

        let taskID = UUID()
        let events: Set<StoreDomainEvent> = [
            .taskChanged(taskID: taskID, affectedAncestorIDs: []),
        ]
        let didCommit = store.perform(events: events) {
            _ = try SwiftDataTaskRepository(
                context: context,
                deviceID: "test"
            ).createTask(
                proposedID: taskID,
                title: "Committed despite projection failure",
                parentID: nil,
                colorHex: nil,
                iconName: nil
            )
        }
        await scheduler.waitUntilIdle()
        await StoreMutationBroadcaster.waitUntilIdle()

        #expect(didCommit)
        #expect(
            try SwiftDataTaskRepository(
                context: ModelContext(context.container),
                deviceID: "verification"
            ).task(id: taskID)?.title == "Committed despite projection failure"
        )
        #expect(store.tasks.contains { $0.id == taskID })
        #expect(store.errorMessage == existingErrorMessage)
        #expect(
            scheduler.failedSinks ==
                Set(CommittedMutationSystemProjectionSink.allCases)
        )
        for sink in CommittedMutationSystemProjectionSink.allCases {
            #expect(failure.calls(for: sink).count == 1)
            #expect(scheduler.failure(for: sink)?.message.contains(
                FailingSystemProjectionWorker.failureMessage
            ) == true)
        }
    }

    @MainActor
    private func makeStoreFixture(
        scheduler: CommittedMutationSystemProjectionScheduler,
        name: String
    ) -> ProjectionBoundaryStoreFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CommittedMutationProjectionBoundaryTests-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
        let store = TimeTrackerStore(
            appleHealthDataReader: UnavailableAppleHealthDataReader(),
            appleHealthTimelinePreferenceStore:
            TestAppleHealthTimelinePreferenceStore(),
            writeAuthorization: .isolatedTestHarness,
            syncConflictService: SyncConflictService(
                stateURL: directory.appendingPathComponent(
                    SyncConflictService.stateFileName
                )
            ),
            committedMutationSystemProjectionScheduler: scheduler
        )
        return ProjectionBoundaryStoreFixture(
            store: store,
            directory: directory
        )
    }
}

@MainActor
private struct ProjectionBoundaryStoreFixture {
    let store: TimeTrackerStore
    let directory: URL

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class BlockingSystemProjectionWorker {
    private var recorded: [
        CommittedMutationSystemProjectionSink:
            [CommittedMutationSystemProjectionWork]
    ] = [:]
    private var entryWaiters: [
        CommittedMutationSystemProjectionSink:
            [CheckedContinuation<Void, Never>]
    ] = [:]
    private var releaseContinuations: [
        CommittedMutationSystemProjectionSink:
            CheckedContinuation<Void, Never>
    ] = [:]

    func run(
        sink: CommittedMutationSystemProjectionSink,
        work: CommittedMutationSystemProjectionWork
    ) async throws {
        let attempt = recorded[sink, default: []].count
        recorded[sink, default: []].append(work)
        guard attempt == 0 else { return }

        await withCheckedContinuation { continuation in
            releaseContinuations[sink] = continuation
            entryWaiters.removeValue(forKey: sink)?.forEach {
                $0.resume()
            }
        }
    }

    func waitUntilBlocked(
        _ sink: CommittedMutationSystemProjectionSink
    ) async {
        guard releaseContinuations[sink] == nil else { return }
        await withCheckedContinuation { continuation in
            entryWaiters[sink, default: []].append(continuation)
        }
    }

    func isBlocked(
        _ sink: CommittedMutationSystemProjectionSink
    ) -> Bool {
        releaseContinuations[sink] != nil
    }

    func calls(
        for sink: CommittedMutationSystemProjectionSink
    ) -> [CommittedMutationSystemProjectionWork] {
        recorded[sink, default: []]
    }

    func releaseAll() {
        let continuations = Array(releaseContinuations.values)
        releaseContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

@MainActor
private final class FailingSystemProjectionWorker {
    nonisolated static let failureMessage =
        "Injected system projection failure"

    private var recorded: [
        CommittedMutationSystemProjectionSink:
            [CommittedMutationSystemProjectionWork]
    ] = [:]

    func run(
        sink: CommittedMutationSystemProjectionSink,
        work: CommittedMutationSystemProjectionWork
    ) throws {
        recorded[sink, default: []].append(work)
        throw Failure()
    }

    func calls(
        for sink: CommittedMutationSystemProjectionSink
    ) -> [CommittedMutationSystemProjectionWork] {
        recorded[sink, default: []]
    }

    private struct Failure: LocalizedError {
        var errorDescription: String? {
            FailingSystemProjectionWorker.failureMessage
        }
    }
}
