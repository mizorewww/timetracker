import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CommittedMutationProjectionBoundaryTests {
    @Test @MainActor
    func broadcastBurstCollapsesToOneBoundedFullSyncCatchUp() async {
        await StoreMutationBroadcaster.waitUntilIdle()

        for _ in 0 ..< 1000 {
            StoreMutationBroadcaster.publish(
                events: [
                    .taskChanged(
                        taskID: UUID(),
                        affectedAncestorIDs: []
                    ),
                ]
            )
        }

        #expect(StoreMutationBroadcaster.pendingBroadcastCount == 1)
        #expect(StoreMutationBroadcaster.pendingBroadcastEvents == [.fullSync])

        await StoreMutationBroadcaster.waitUntilIdle()
        #expect(StoreMutationBroadcaster.pendingBroadcastCount == 0)

        StoreMutationBroadcaster.publish(
            events: [
                .taskChanged(
                    taskID: UUID(),
                    affectedAncestorIDs: Set(
                        (0 ..< 600).map { _ in UUID() }
                    )
                ),
            ]
        )
        #expect(StoreMutationBroadcaster.pendingBroadcastCount == 1)
        #expect(StoreMutationBroadcaster.pendingBroadcastEvents == [.fullSync])

        await StoreMutationBroadcaster.waitUntilIdle()
        #expect(StoreMutationBroadcaster.pendingBroadcastCount == 0)
    }

    @Test @MainActor
    func reentrantBroadcastIsDrainedWithoutRecursiveDeliveryOrStranding() async {
        await StoreMutationBroadcaster.waitUntilIdle()
        let firstEvent = StoreDomainEvent.taskChanged(
            taskID: UUID(),
            affectedAncestorIDs: []
        )
        let secondEvent = StoreDomainEvent.ledgerChanged(
            taskID: UUID(),
            dateInterval: nil,
            isVisible: true
        )
        let probe = ReentrantBroadcastProbe(
            firstEvent: firstEvent,
            secondEvent: secondEvent
        )
        let token = NotificationCenter.default.addObserver(
            forName: StoreMutationBroadcaster.notification,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                probe.receive(notification)
            }
        }
        defer {
            NotificationCenter.default.removeObserver(token)
        }

        StoreMutationBroadcaster.publish(events: [firstEvent])
        await StoreMutationBroadcaster.waitUntilIdle()

        #expect(probe.receivedEvents == [[firstEvent], [secondEvent]])
        #expect(probe.maximumDeliveryDepth == 1)
        #expect(StoreMutationBroadcaster.pendingBroadcastCount == 0)
    }

    @Test @MainActor
    func ordinarySceneMutationRefreshesAndBroadcastsBeforeQueuedProjectionsWithoutSynchronousSyncStateIO()
        async throws
    {
        let cloudSyncMode = SceneCloudSyncModeLease()
        defer { cloudSyncMode.restore() }
        let syncStateIO = SceneSyncStateIOProbe()
        let context = try makeTestContext()
        let gate = BlockingSystemProjectionWorker()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await gate.run(sink: sink, work: work)
        }
        let fixture = makeStoreFixture(
            scheduler: scheduler,
            name: #function,
            localStateFile: DurableLocalFile(
                injectFault: { point in
                    syncStateIO.record(point)
                }
            )
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
        #expect(syncStateIO.points.isEmpty)
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
            #expect(calls.last?.forceCurrentStateProjection == false)
        }
        #expect(syncStateIO.points.isEmpty)
    }

    @Test @MainActor
    func facadeCanForceOneSystemSurfaceWithoutInventingAMutationEvent()
        async
    {
        let probe = RecordingSystemProjectionWorker()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            probe.record(sink: sink, work: work)
        }
        let fixture = makeStoreFixture(
            scheduler: scheduler,
            name: #function
        )
        defer { fixture.remove() }

        fixture.store.enqueueCommittedMutationSystemProjections(
            events: [],
            forcedSystemSinks: [.watch]
        )
        await scheduler.waitUntilIdle()

        #expect(probe.calls(for: .syncSnapshot).isEmpty)
        #expect(probe.calls(for: .widget).isEmpty)
        #expect(probe.calls(for: .liveActivity).isEmpty)
        let watchCalls = probe.calls(for: .watch)
        #expect(watchCalls.count == 1)
        #expect(watchCalls.first?.events.isEmpty == true)
        #expect(
            watchCalls.first?.forceCurrentStateProjection == true
        )
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
        name: String,
        localStateFile: DurableLocalFile = DurableLocalFile()
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
                ),
                localStateFile: localStateFile
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
private final class ReentrantBroadcastProbe {
    private let firstEvent: StoreDomainEvent
    private let secondEvent: StoreDomainEvent
    private var deliveryDepth = 0
    private var didPublishSecondEvent = false
    private(set) var maximumDeliveryDepth = 0
    private(set) var receivedEvents: [Set<StoreDomainEvent>] = []

    init(
        firstEvent: StoreDomainEvent,
        secondEvent: StoreDomainEvent
    ) {
        self.firstEvent = firstEvent
        self.secondEvent = secondEvent
    }

    func receive(_ notification: Notification) {
        guard let events = StoreMutationBroadcaster.events(
            from: notification
        ) else {
            return
        }

        deliveryDepth += 1
        maximumDeliveryDepth = max(maximumDeliveryDepth, deliveryDepth)
        receivedEvents.append(events)
        if events == [firstEvent], didPublishSecondEvent == false {
            didPublishSecondEvent = true
            StoreMutationBroadcaster.publish(events: [secondEvent])
        }
        deliveryDepth -= 1
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
private final class SceneCloudSyncModeLease {
    private let keys = [
        AppCloudSync.modeKey,
        AppCloudSync.enabledKey,
        AppCloudSync.pendingCloudUploadResetKey,
        AppCloudSync.pendingCloudDownloadResetKey,
        AppCloudSync.queuedCloudReconciliationKey,
        AppCloudSync.activeCloudReconciliationKey,
        AppCloudSync.cloudRecoveryStoreResetKey,
        AppCloudSync.activeCloudDownloadRecoveryKey,
    ]
    private let previousValues: [String: Any]

    init() {
        let defaults = AppDefaults.shared
        previousValues = keys.reduce(into: [:]) { values, key in
            if let value = defaults.object(forKey: key) {
                values[key] = value
            }
        }
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        defaults.set(
            AppCloudSync.modeICloud,
            forKey: AppCloudSync.modeKey
        )
        defaults.set(
            true,
            forKey: AppCloudSync.enabledKey
        )
    }

    func restore() {
        let defaults = AppDefaults.shared
        for key in keys {
            if let value = previousValues[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

private final nonisolated class SceneSyncStateIOProbe:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var recordedPoints: [DurableLocalFileFaultPoint] = []

    var points: [DurableLocalFileFaultPoint] {
        lock.withLock { recordedPoints }
    }

    func record(_ point: DurableLocalFileFaultPoint) {
        lock.withLock {
            recordedPoints.append(point)
        }
    }
}

@MainActor
private final class RecordingSystemProjectionWorker {
    private var recorded: [
        CommittedMutationSystemProjectionSink:
            [CommittedMutationSystemProjectionWork]
    ] = [:]

    func record(
        sink: CommittedMutationSystemProjectionSink,
        work: CommittedMutationSystemProjectionWork
    ) {
        recorded[sink, default: []].append(work)
    }

    func calls(
        for sink: CommittedMutationSystemProjectionSink
    ) -> [CommittedMutationSystemProjectionWork] {
        recorded[sink, default: []]
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
