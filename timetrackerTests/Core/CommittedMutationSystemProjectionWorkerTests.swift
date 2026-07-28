import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CommittedMutationSystemProjectionWorkerTests {
    @Test @MainActor
    func schedulerSharesOneMaterializationAcrossAllSinks() async {
        let probe = SystemProjectionWorkerProbe()
        let worker = probe.makeWorker()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await worker.perform(sink: sink, work: work)
        }

        scheduler.enqueue(CommittedMutationSystemProjectionReceipt(
            events: [.fullSync]
        ))
        await scheduler.waitUntilIdle()

        #expect(probe.materializationCount == 1)
        #expect(
            Set(probe.publications.map(\.sink)) ==
                Set(
                    CommittedMutationSystemProjectionSink
                        .systemSurfaceCases
                )
        )
        #expect(Set(probe.publications.map(\.generatedAt)).count == 1)
    }

    @Test @MainActor
    func schedulerRecordsSyncEventsWithoutMaterializingASurface() async {
        let probe = SystemProjectionWorkerProbe()
        let worker = probe.makeWorker()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await worker.perform(sink: sink, work: work)
        }
        let events: Set<StoreDomainEvent> = [
            .taskChanged(
                taskID: UUID(),
                affectedAncestorIDs: []
            ),
            .checklistChanged(
                taskID: UUID(),
                affectedAncestorIDs: []
            ),
        ]

        scheduler.enqueue(CommittedMutationSystemProjectionReceipt(
            events: events
        ))
        await scheduler.waitUntilIdle()

        #expect(probe.recordedSyncEvents == [events])
        #expect(probe.materializationCount == 1)
        #expect(
            Set(probe.publications.map(\.sink)) ==
                Set(
                    CommittedMutationSystemProjectionSink
                        .systemSurfaceCases
                )
        )
    }

    @Test @MainActor
    func failedSinkRetriesTheSameMaterializationWithoutRepeatingSiblings() async {
        let probe = SystemProjectionWorkerProbe(
            failuresRemaining: [.widget: 1]
        )
        let worker = probe.makeWorker()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await worker.perform(sink: sink, work: work)
        }

        scheduler.enqueue(CommittedMutationSystemProjectionReceipt(
            events: [.ledgerChanged(
                taskID: UUID(),
                dateInterval: nil,
                isVisible: true
            )]
        ))
        await scheduler.waitUntilIdle()

        #expect(probe.materializationCount == 1)
        #expect(scheduler.failedSinks == [.widget])
        #expect(probe.publicationCount(for: .widget) == 1)
        #expect(probe.publicationCount(for: .watch) == 1)
        #expect(probe.publicationCount(for: .liveActivity) == 1)

        scheduler.retryFailedSinks()
        await scheduler.waitUntilIdle()

        #expect(probe.materializationCount == 1)
        #expect(scheduler.failedSinks.isEmpty)
        #expect(probe.publicationCount(for: .widget) == 2)
        #expect(probe.publicationCount(for: .watch) == 1)
        #expect(probe.publicationCount(for: .liveActivity) == 1)
        #expect(Set(probe.publications.map(\.generatedAt)).count == 1)
    }

    @Test @MainActor
    func materializationFailureIsSharedThenRetryReadsAgainAndRecovers() async {
        let probe = SystemProjectionWorkerProbe(
            materializationFailuresRemaining: 1
        )
        let worker = probe.makeWorker()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await worker.perform(sink: sink, work: work)
        }

        scheduler.enqueue(CommittedMutationSystemProjectionReceipt(
            events: [.fullSync]
        ))
        await scheduler.waitUntilIdle()

        #expect(probe.materializationCount == 1)
        #expect(
            scheduler.failedSinks ==
                Set(
                    CommittedMutationSystemProjectionSink
                        .systemSurfaceCases
                )
        )
        #expect(probe.publications.isEmpty)

        scheduler.retryFailedSinks()
        await scheduler.waitUntilIdle()

        #expect(probe.materializationCount == 2)
        #expect(scheduler.failedSinks.isEmpty)
        #expect(
            Set(probe.publications.map(\.sink)) ==
                Set(
                    CommittedMutationSystemProjectionSink
                        .systemSurfaceCases
                )
        )
    }

    @Test @MainActor
    func preferenceOnlyRetryFreshReadsAfterPartialFullSyncFailure() async throws {
        let probe = SystemProjectionWorkerProbe(
            materializationFailuresRemaining: 2
        )
        let worker = probe.makeWorker()
        let fullSyncWork = CommittedMutationSystemProjectionWork(
            generation: 1,
            targetSinks: Set(
                CommittedMutationSystemProjectionSink.allCases
            ),
            receiptIDs: [UUID()],
            events: [.fullSync]
        )
        let preferenceWork = CommittedMutationSystemProjectionWork(
            generation: 2,
            targetSinks: [.watch],
            receiptIDs: [UUID()],
            events: [.preferenceChanged(key: "quickStart")]
        )

        let fullSyncDidFail = await consumesMaterializationFailure(
            worker: worker,
            sink: .widget,
            work: fullSyncWork
        )
        #expect(fullSyncDidFail)
        #expect(probe.materializationCount == 1)

        let preferenceDidFail = await consumesMaterializationFailure(
            worker: worker,
            sink: .watch,
            work: preferenceWork
        )
        #expect(preferenceDidFail)
        #expect(probe.materializationCount == 2)

        try await worker.perform(
            sink: .watch,
            work: preferenceWork
        )

        #expect(probe.materializationCount == 3)
        #expect(probe.publicationCount(for: .watch) == 1)
        #expect(
            Set(probe.publications.map(\.sink)) == [.watch]
        )
    }

    @Test @MainActor
    func cachedMaterializationFailureDoesNotRetainErrorReference() async {
        weak var retainedReference: MaterializationFailureReference?
        let worker = CommittedMutationSystemProjectionWorker(
            materializer: { _ in
                let reference = MaterializationFailureReference()
                retainedReference = reference
                throw ReferenceHoldingMaterializationError(
                    reference: reference
                )
            },
            publisher: { _, _ in
                Issue.record(
                    "A failed materialization must not publish."
                )
            }
        )
        let work = CommittedMutationSystemProjectionWork(
            generation: 1,
            targetSinks: Set(
                CommittedMutationSystemProjectionSink.allCases
            ),
            receiptIDs: [UUID()],
            events: [.fullSync]
        )

        let didThrow = await consumesMaterializationFailure(
            worker: worker,
            sink: .widget,
            work: work
        )

        #expect(didThrow)
        #expect(retainedReference == nil)
    }

    @Test @MainActor
    func newerGenerationEvictsAnIncompleteOlderMaterialization() async {
        let probe = SystemProjectionWorkerProbe(
            failuresRemaining: [.widget: 1]
        )
        let worker = probe.makeWorker()
        let olderWork = CommittedMutationSystemProjectionWork(
            generation: 1,
            targetSinks: [.widget],
            receiptIDs: [UUID()],
            events: [.fullSync]
        )
        let newerWork = CommittedMutationSystemProjectionWork(
            generation: 2,
            targetSinks: [.watch],
            receiptIDs: [UUID()],
            events: [.preferenceChanged(key: "quickStart")]
        )

        await #expect(throws: SystemProjectionWorkerProbeError.expected) {
            try await worker.perform(sink: .widget, work: olderWork)
        }
        try? await worker.perform(sink: .watch, work: newerWork)
        #expect(probe.materializationCount == 2)

        try? await worker.perform(sink: .widget, work: olderWork)
        #expect(probe.materializationCount == 3)
    }

    @Test @MainActor
    func productionMaterializerReadsCompleteCurrentSurfaceFacts() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "projection-worker-test"
        )
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "projection-worker-test"
        )
        let task = try taskRepository.createTask(
            title: "Current committed timer",
            parentID: nil,
            colorHex: "#0A84FF",
            iconName: "timer"
        )
        let segment = try timeRepository.startTask(
            taskID: task.id,
            source: .timer
        )
        let now = segment.startedAt.addingTimeInterval(30)

        let materialization =
            try CommittedMutationSystemProjectionWorker
                .materializeCurrentFacts(
                    context: context,
                    now: now
                )

        #expect(materialization.generatedAt == now)
        #expect(
            materialization.widgetSnapshot.activeTimers.map(\.id) ==
                [segment.id]
        )
        #expect(
            materialization.watchSnapshot.activeTimers.map(\.id) ==
                [segment.id]
        )
        guard case let .active(liveActivity) =
            materialization.liveActivity
        else {
            Issue.record("Expected an active Live Activity projection.")
            return
        }
        #expect(liveActivity.segmentID == segment.id.uuidString)
        #expect(liveActivity.taskID == task.id.uuidString)
        #expect(liveActivity.taskTitle == "Current committed timer")
    }

    @Test @MainActor
    func registryReusesOneSchedulerForAStoreScope() throws {
        let context = try makeTestContext()
        let registry =
            CommittedMutationSystemProjectionSchedulerRegistry()

        let first = try registry.scheduler(for: context.container)
        let second = try registry.scheduler(for: context.container)

        #expect(first === second)
    }

    @Test @MainActor
    func registrySharesSchedulerAcrossContainersForOnePersistentStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CommittedMutationProjectionRegistry-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let storeURL = directory.appendingPathComponent(
            "timetracker.store"
        )
        let schema = TimeTrackerModelRegistry.currentSchema
        let firstContainer = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [
                ModelConfiguration(
                    "ProjectionRegistryFirst",
                    schema: schema,
                    url: storeURL,
                    cloudKitDatabase: .none
                ),
            ]
        )
        let secondContainer = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [
                ModelConfiguration(
                    "ProjectionRegistrySecond",
                    schema: schema,
                    url: storeURL,
                    cloudKitDatabase: .none
                ),
            ]
        )
        let registry =
            CommittedMutationSystemProjectionSchedulerRegistry()

        let first = try registry.scheduler(for: firstContainer)
        let second = try registry.scheduler(for: secondContainer)

        #expect(first === second)
    }
}

@MainActor
private final class SystemProjectionWorkerProbe {
    struct Publication {
        let sink: CommittedMutationSystemProjectionSink
        let generatedAt: Date
    }

    private(set) var materializationCount = 0
    private(set) var publications: [Publication] = []
    private(set) var recordedSyncEvents: [Set<StoreDomainEvent>] = []
    private var failuresRemaining: [
        CommittedMutationSystemProjectionSink: Int
    ]
    private var materializationFailuresRemaining: Int

    init(
        failuresRemaining: [CommittedMutationSystemProjectionSink: Int] = [:],
        materializationFailuresRemaining: Int = 0
    ) {
        self.failuresRemaining = failuresRemaining
        self.materializationFailuresRemaining =
            materializationFailuresRemaining
    }

    func makeWorker() -> CommittedMutationSystemProjectionWorker {
        CommittedMutationSystemProjectionWorker(
            syncRecorder: { [weak self] events in
                guard let self else {
                    throw SystemProjectionWorkerProbeError.deallocated
                }
                recordedSyncEvents.append(events)
            },
            materializer: { [weak self] work in
                guard let self else {
                    throw SystemProjectionWorkerProbeError.deallocated
                }
                return try materialize(work)
            },
            publisher: { [weak self] sink, materialization in
                guard let self else {
                    throw SystemProjectionWorkerProbeError.deallocated
                }
                try publish(
                    sink: sink,
                    materialization: materialization
                )
            }
        )
    }

    func publicationCount(
        for sink: CommittedMutationSystemProjectionSink
    ) -> Int {
        publications.count { $0.sink == sink }
    }

    private func materialize(
        _ work: CommittedMutationSystemProjectionWork
    ) throws -> CommittedMutationSystemProjectionMaterialization {
        materializationCount += 1
        if materializationFailuresRemaining > 0 {
            materializationFailuresRemaining -= 1
            throw SystemProjectionWorkerProbeError.expected
        }
        let generatedAt = Date(
            timeIntervalSinceReferenceDate: TimeInterval(work.generation)
        )
        return CommittedMutationSystemProjectionMaterialization(
            widgetSnapshot: WidgetSnapshot(
                generatedAt: generatedAt,
                todayGrossSeconds: 0,
                todayWallSeconds: 0,
                activeTimers: [],
                recentTasks: []
            ),
            watchSnapshot: WatchStateSnapshot(
                generatedAt: generatedAt,
                todayGrossSeconds: 0,
                todayWallSeconds: 0,
                activeTimers: [],
                recentTasks: []
            ),
            liveActivity: .inactive,
            generatedAt: generatedAt
        )
    }

    private func publish(
        sink: CommittedMutationSystemProjectionSink,
        materialization: CommittedMutationSystemProjectionMaterialization
    ) throws {
        publications.append(Publication(
            sink: sink,
            generatedAt: materialization.generatedAt
        ))
        if let remaining = failuresRemaining[sink], remaining > 0 {
            failuresRemaining[sink] = remaining - 1
            throw SystemProjectionWorkerProbeError.expected
        }
    }
}

private nonisolated enum SystemProjectionWorkerProbeError: Error {
    case deallocated
    case expected
}

private final nonisolated class MaterializationFailureReference:
    @unchecked Sendable
{}

private nonisolated struct ReferenceHoldingMaterializationError:
    Error,
    @unchecked Sendable
{
    let reference: MaterializationFailureReference
}

@MainActor
private func consumesMaterializationFailure(
    worker: CommittedMutationSystemProjectionWorker,
    sink: CommittedMutationSystemProjectionSink,
    work: CommittedMutationSystemProjectionWork
) async -> Bool {
    do {
        try await worker.perform(sink: sink, work: work)
        return false
    } catch {
        return true
    }
}
