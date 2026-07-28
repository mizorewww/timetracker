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
            try await worker.perform(
                sink: sink,
                work: work,
                expectedContainerRevision: 1
            )
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
            try await worker.perform(
                sink: sink,
                work: work,
                expectedContainerRevision: 1
            )
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
            try await worker.perform(
                sink: sink,
                work: work,
                expectedContainerRevision: 1
            )
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
            try await worker.perform(
                sink: sink,
                work: work,
                expectedContainerRevision: 1
            )
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
    func threeSurfaceLanesShareOneSuspendedMaterializationAndMainActorHeartbeat()
        async
    {
        let gate = AsyncSystemProjectionMaterializationGate()
        let heartbeat = SystemProjectionMainActorHeartbeat()
        let probe = AsyncSystemProjectionWorkerProbe(
            firstMaterializationGate: gate
        )
        let worker = probe.makeWorker()
        let work = systemSurfaceWork(generation: 1)

        let widget = Task { @MainActor in
            await projectionAttempt(
                worker: worker,
                sink: .widget,
                work: work,
                expectedContainerRevision: 1
            )
        }
        let watch = Task { @MainActor in
            await projectionAttempt(
                worker: worker,
                sink: .watch,
                work: work,
                expectedContainerRevision: 1
            )
        }
        let liveActivity = Task { @MainActor in
            await projectionAttempt(
                worker: worker,
                sink: .liveActivity,
                work: work,
                expectedContainerRevision: 1
            )
        }

        await gate.waitUntilSuspended()
        #expect(probe.materializationCount == 1)

        await Task { @MainActor in
            heartbeat.record()
            await gate.release()
        }.value

        let outcomes = await (
            widget.value,
            watch.value,
            liveActivity.value
        )
        #expect(heartbeat.didRun)
        #expect(outcomes.0 == .succeeded)
        #expect(outcomes.1 == .succeeded)
        #expect(outcomes.2 == .succeeded)
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
    func suspendedMaterializationFailureIsSharedAndRetryReadsFresh()
        async
    {
        let gate = AsyncSystemProjectionMaterializationGate()
        let probe = AsyncSystemProjectionWorkerProbe(
            firstMaterializationGate: gate,
            materializationFailuresRemaining: 1
        )
        let worker = probe.makeWorker()
        let work = systemSurfaceWork(generation: 1)

        let widget = Task { @MainActor in
            await projectionAttempt(
                worker: worker,
                sink: .widget,
                work: work,
                expectedContainerRevision: 1
            )
        }
        let watch = Task { @MainActor in
            await projectionAttempt(
                worker: worker,
                sink: .watch,
                work: work,
                expectedContainerRevision: 1
            )
        }
        let liveActivity = Task { @MainActor in
            await projectionAttempt(
                worker: worker,
                sink: .liveActivity,
                work: work,
                expectedContainerRevision: 1
            )
        }

        await gate.waitUntilSuspended()
        #expect(probe.materializationCount == 1)
        await gate.release()

        let failedOutcomes = await (
            widget.value,
            watch.value,
            liveActivity.value
        )
        #expect(failedOutcomes.0 == .failed)
        #expect(failedOutcomes.1 == .failed)
        #expect(failedOutcomes.2 == .failed)
        #expect(probe.materializationCount == 1)
        #expect(probe.publications.isEmpty)

        let widgetRetry = Task { @MainActor in
            await projectionAttempt(
                worker: worker,
                sink: .widget,
                work: work,
                expectedContainerRevision: 1
            )
        }
        let watchRetry = Task { @MainActor in
            await projectionAttempt(
                worker: worker,
                sink: .watch,
                work: work,
                expectedContainerRevision: 1
            )
        }
        let liveActivityRetry = Task { @MainActor in
            await projectionAttempt(
                worker: worker,
                sink: .liveActivity,
                work: work,
                expectedContainerRevision: 1
            )
        }
        let retryOutcomes = await (
            widgetRetry.value,
            watchRetry.value,
            liveActivityRetry.value
        )

        #expect(retryOutcomes.0 == .succeeded)
        #expect(retryOutcomes.1 == .succeeded)
        #expect(retryOutcomes.2 == .succeeded)
        #expect(probe.materializationCount == 2)
        #expect(
            Set(probe.publications.map(\.sink)) ==
                Set(
                    CommittedMutationSystemProjectionSink
                        .systemSurfaceCases
                )
        )
        #expect(
            Set(probe.publications.map(\.generatedAt)) == [
                Date(timeIntervalSinceReferenceDate: 2),
            ]
        )
    }

    @Test @MainActor
    func containerRevisionChangeDuringMaterializationDropsOldDTOAndRetryReadsFresh()
        async
    {
        let gate = AsyncSystemProjectionMaterializationGate()
        let revision = SystemProjectionContainerRevisionProbe(
            current: 1
        )
        let probe = AsyncSystemProjectionWorkerProbe(
            firstMaterializationGate: gate
        )
        let worker = probe.makeWorker {
            [weak revision] expectedRevision in
            revision?.isCurrent(expectedRevision) == true
        }
        let work = CommittedMutationSystemProjectionWork(
            generation: 1,
            targetSinks: [.widget],
            receiptIDs: [UUID()],
            events: [.fullSync]
        )

        let oldRegistration = Task { @MainActor in
            await projectionAttempt(
                worker: worker,
                sink: .widget,
                work: work,
                expectedContainerRevision: 1
            )
        }
        await gate.waitUntilSuspended()

        revision.replace(with: 2)
        await gate.release()

        #expect(await oldRegistration.value == .failed)
        #expect(probe.materializationCount == 1)
        #expect(probe.publications.isEmpty)

        let freshRegistration = await projectionAttempt(
            worker: worker,
            sink: .widget,
            work: work,
            expectedContainerRevision: 2
        )

        #expect(freshRegistration == .succeeded)
        #expect(probe.materializationCount == 2)
        #expect(probe.publications.map(\.sink) == [.widget])
        #expect(
            probe.publications.map(\.generatedAt) == [
                Date(timeIntervalSinceReferenceDate: 2),
            ]
        )
    }

    @Test @MainActor
    func containerRevisionChangeDiscardsCachedMaterializationFailure()
        async
    {
        let revision = SystemProjectionContainerRevisionProbe(
            current: 1
        )
        let probe = AsyncSystemProjectionWorkerProbe(
            materializationFailuresRemaining: 1
        )
        let worker = probe.makeWorker {
            [weak revision] expectedRevision in
            revision?.isCurrent(expectedRevision) == true
        }
        let work = systemSurfaceWork(generation: 1)

        let oldFailure = await projectionAttempt(
            worker: worker,
            sink: .widget,
            work: work,
            expectedContainerRevision: 1
        )
        #expect(oldFailure == .failed)
        #expect(probe.materializationCount == 1)
        #expect(probe.publications.isEmpty)

        revision.replace(with: 2)

        let widget = Task { @MainActor in
            await projectionAttempt(
                worker: worker,
                sink: .widget,
                work: work,
                expectedContainerRevision: 2
            )
        }
        let watch = Task { @MainActor in
            await projectionAttempt(
                worker: worker,
                sink: .watch,
                work: work,
                expectedContainerRevision: 2
            )
        }
        let liveActivity = Task { @MainActor in
            await projectionAttempt(
                worker: worker,
                sink: .liveActivity,
                work: work,
                expectedContainerRevision: 2
            )
        }
        let outcomes = await (
            widget.value,
            watch.value,
            liveActivity.value
        )

        #expect(outcomes.0 == .succeeded)
        #expect(outcomes.1 == .succeeded)
        #expect(outcomes.2 == .succeeded)
        #expect(probe.materializationCount == 2)
        #expect(
            Set(probe.publications.map(\.sink)) ==
                Set(
                    CommittedMutationSystemProjectionSink
                        .systemSurfaceCases
                )
        )
        #expect(
            Set(probe.publications.map(\.generatedAt)) == [
                Date(timeIntervalSinceReferenceDate: 2),
            ]
        )
    }

    @Test @MainActor
    func blockedWidgetPersistenceKeepsMainActorResponsiveAndOnlyWidgetFails()
        async
    {
        let gate = SystemProjectionBlockingOperationGate()
        let persistence = SystemProjectionThreadSafeInvocationProbe()
        let reload = SystemProjectionThreadSafeInvocationProbe()
        let surfacePublications =
            SystemProjectionSurfacePublicationProbe()
        let writer = WidgetSnapshotProjectionWriter(
            persist: { _ in
                persistence.record()
                gate.blockFirstEntry()
                throw SystemProjectionWorkerProbeError.expected
            },
            reload: {
                reload.record()
            }
        )
        let materialization = systemProjectionMaterialization(
            generatedAt: Date(
                timeIntervalSinceReferenceDate: 1
            )
        )
        let worker = CommittedMutationSystemProjectionWorker(
            materializer: { _ in materialization },
            publisher: { sink, value in
                switch sink {
                case .syncSnapshot:
                    Issue.record(
                        "The sync lane must bypass surface publication."
                    )
                case .widget:
                    try await writer.save(value.widgetSnapshot)
                case .watch, .liveActivity:
                    surfacePublications.record(sink)
                }
            },
            isContainerRegistrationCurrent: { _ in true }
        )
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await worker.perform(
                sink: sink,
                work: work,
                expectedContainerRevision: 1
            )
        }
        let coordinator = Task.detached {
            await gate.waitUntilBlocked()
            let safetyRelease = Task.detached {
                try? await Task.sleep(for: .seconds(2))
                gate.releaseOnce(from: .safety)
            }
            await Task { @MainActor in
                gate.releaseOnce(from: .heartbeat)
            }.value
            safetyRelease.cancel()
            _ = await safetyRelease.result
        }

        scheduler.enqueue(CommittedMutationSystemProjectionReceipt(
            events: [.fullSync]
        ))
        await scheduler.waitUntilIdle()
        await coordinator.value

        #expect(gate.firstRelease == .heartbeat)
        #expect(persistence.count == 1)
        #expect(reload.count == 0)
        #expect(scheduler.failedSinks == [.widget])
        #expect(
            surfacePublications.sinks == [
                .watch,
                .liveActivity,
            ] ||
                surfacePublications.sinks == [
                    .liveActivity,
                    .watch,
                ]
        )
        #expect(
            scheduler.acknowledgedGeneration(for: .watch) == 1
        )
        #expect(
            scheduler.acknowledgedGeneration(for: .liveActivity) ==
                1
        )
        #expect(
            scheduler.acknowledgedGeneration(for: .widget) == nil
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
            work: preferenceWork,
            expectedContainerRevision: 1
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
            try await worker.perform(
                sink: .widget,
                work: olderWork,
                expectedContainerRevision: 1
            )
        }
        try? await worker.perform(
            sink: .watch,
            work: newerWork,
            expectedContainerRevision: 1
        )
        #expect(probe.materializationCount == 2)

        try? await worker.perform(
            sink: .widget,
            work: olderWork,
            expectedContainerRevision: 1
        )
        #expect(probe.materializationCount == 3)
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

private nonisolated enum SystemProjectionAttemptOutcome:
    Equatable,
    Sendable
{
    case succeeded
    case failed
}

@MainActor
private func projectionAttempt(
    worker: CommittedMutationSystemProjectionWorker,
    sink: CommittedMutationSystemProjectionSink,
    work: CommittedMutationSystemProjectionWork,
    expectedContainerRevision: UInt
) async -> SystemProjectionAttemptOutcome {
    do {
        try await worker.perform(
            sink: sink,
            work: work,
            expectedContainerRevision: expectedContainerRevision
        )
        return .succeeded
    } catch {
        return .failed
    }
}

private nonisolated func systemSurfaceWork(
    generation: UInt
) -> CommittedMutationSystemProjectionWork {
    CommittedMutationSystemProjectionWork(
        generation: generation,
        targetSinks: Set(
            CommittedMutationSystemProjectionSink.systemSurfaceCases
        ),
        receiptIDs: [UUID()],
        events: [.fullSync]
    )
}

private nonisolated func systemProjectionMaterialization(
    generatedAt: Date
) -> CommittedMutationSystemProjectionMaterialization {
    CommittedMutationSystemProjectionMaterialization(
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

private actor AsyncSystemProjectionMaterializationGate {
    private var didSuspend = false
    private var didRelease = false
    private var suspendedWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation:
        CheckedContinuation<Void, Never>?

    func suspendFirstMaterialization() async {
        guard didSuspend == false else { return }
        didSuspend = true
        let waiters = suspendedWaiters
        suspendedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard didRelease == false else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilSuspended() async {
        guard didSuspend == false else { return }
        await withCheckedContinuation { continuation in
            suspendedWaiters.append(continuation)
        }
    }

    func release() {
        guard didRelease == false else { return }
        didRelease = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class AsyncSystemProjectionWorkerProbe {
    struct Publication {
        let sink: CommittedMutationSystemProjectionSink
        let generatedAt: Date
    }

    private let firstMaterializationGate:
        AsyncSystemProjectionMaterializationGate?
    private var materializationFailuresRemaining: Int
    private(set) var materializationCount = 0
    private(set) var publications: [Publication] = []

    init(
        firstMaterializationGate:
        AsyncSystemProjectionMaterializationGate? = nil,
        materializationFailuresRemaining: Int = 0
    ) {
        self.firstMaterializationGate =
            firstMaterializationGate
        self.materializationFailuresRemaining =
            materializationFailuresRemaining
    }

    func makeWorker(
        isContainerRegistrationCurrent:
        @escaping CommittedMutationSystemProjectionWorker
            .ContainerRegistrationValidator = { _ in true }
    ) -> CommittedMutationSystemProjectionWorker {
        CommittedMutationSystemProjectionWorker(
            materializer: { [weak self] _ in
                guard let self else {
                    throw SystemProjectionWorkerProbeError.deallocated
                }
                materializationCount += 1
                let attempt = materializationCount
                if attempt == 1,
                   let firstMaterializationGate
                {
                    await firstMaterializationGate
                        .suspendFirstMaterialization()
                }
                if materializationFailuresRemaining > 0 {
                    materializationFailuresRemaining -= 1
                    throw SystemProjectionWorkerProbeError.expected
                }
                return systemProjectionMaterialization(
                    generatedAt: Date(
                        timeIntervalSinceReferenceDate:
                        TimeInterval(attempt)
                    )
                )
            },
            publisher: { [weak self] sink, materialization in
                guard let self else {
                    throw SystemProjectionWorkerProbeError.deallocated
                }
                publications.append(Publication(
                    sink: sink,
                    generatedAt: materialization.generatedAt
                ))
            },
            isContainerRegistrationCurrent:
            isContainerRegistrationCurrent
        )
    }
}

@MainActor
private final class SystemProjectionMainActorHeartbeat {
    private(set) var didRun = false

    func record() {
        didRun = true
    }
}

@MainActor
private final class SystemProjectionContainerRevisionProbe {
    private var current: UInt

    init(current: UInt) {
        self.current = current
    }

    func isCurrent(_ revision: UInt) -> Bool {
        revision == current
    }

    func replace(with revision: UInt) {
        current = revision
    }
}

private final nonisolated class SystemProjectionBlockingOperationGate:
    @unchecked Sendable
{
    enum ReleaseSource: Equatable {
        case heartbeat
        case safety
    }

    private let lock = NSLock()
    private let resume = DispatchSemaphore(value: 0)
    private var didBlock = false
    private var isBlocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var releaseSource: ReleaseSource?

    var firstRelease: ReleaseSource? {
        lock.withLock { releaseSource }
    }

    func blockFirstEntry() {
        let state = lock.withLock {
            () -> (Bool, [CheckedContinuation<Void, Never>]) in
            guard didBlock == false else { return (false, []) }
            didBlock = true
            isBlocked = true
            defer { waiters.removeAll() }
            return (true, waiters)
        }
        state.1.forEach { $0.resume() }
        if state.0 {
            resume.wait()
        }
    }

    func waitUntilBlocked() async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock {
                guard isBlocked == false else { return true }
                waiters.append(continuation)
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    func releaseOnce(from source: ReleaseSource) {
        let shouldSignal = lock.withLock {
            guard releaseSource == nil else { return false }
            releaseSource = source
            return true
        }
        if shouldSignal {
            resume.signal()
        }
    }
}

private final nonisolated class SystemProjectionThreadSafeInvocationProbe:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var invocationCount = 0

    var count: Int {
        lock.withLock { invocationCount }
    }

    func record() {
        lock.withLock {
            invocationCount += 1
        }
    }
}

@MainActor
private final class SystemProjectionSurfacePublicationProbe {
    private(set) var sinks:
        [CommittedMutationSystemProjectionSink] = []

    func record(_ sink: CommittedMutationSystemProjectionSink) {
        sinks.append(sink)
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
        try await worker.perform(
            sink: sink,
            work: work,
            expectedContainerRevision: 1
        )
        return false
    } catch {
        return true
    }
}
