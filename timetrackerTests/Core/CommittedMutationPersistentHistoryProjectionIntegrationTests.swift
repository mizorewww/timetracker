import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CommittedMutationPersistentHistoryProjectionIntegrationTests {
    @Test @MainActor
    func firstRequestFullyProjectsFourLanesAndSecondRequestHasNoEffect()
        async throws
    {
        try await withCommittedMutationHistoryFixture(
            name: #function
        ) { fixture in
            let probe = CommittedMutationHistoryProjectorProbe()
            let registry = fixture.makeRegistry(probe: probe)
            let scheduler = try registry.scheduler(
                for: fixture.container
            )

            scheduler.enqueue(CommittedMutationSystemProjectionReceipt(
                events: [.fullSync]
            ))
            await scheduler.waitUntilIdle()

            await expectProjectionBatch(
                probe.invocations(),
                lanes: Set(PersistentHistoryProjectionLane.allCases),
                kind: .fullReconciliation,
                transactionCount: 0,
                events: [.fullSync]
            )

            scheduler.enqueue(CommittedMutationSystemProjectionReceipt(
                events: [.fullSync]
            ))
            await scheduler.waitUntilIdle()

            #expect(await probe.invocations().count == 4)
        }
    }

    @Test @MainActor
    func historyAuthorRoutesLocalAndRemoteTransactionsAndAdvancesSyncCursor()
        async throws
    {
        try await withCommittedMutationHistoryFixture(
            name: #function
        ) { fixture in
            let probe = CommittedMutationHistoryProjectorProbe()
            let registry = fixture.makeRegistry(probe: probe)
            let scheduler = try registry.scheduler(
                for: fixture.container
            )
            try await establishFourLaneBaseline(
                scheduler: scheduler,
                probe: probe
            )

            try fixture.insertTask(
                title: "Local before remote",
                author: .localMutation
            )
            scheduler.enqueue(CommittedMutationSystemProjectionReceipt(
                events: [taskChangedEvent]
            ))
            await scheduler.waitUntilIdle()

            await expectProjectionBatch(
                probe.invocations(),
                lanes: Set(PersistentHistoryProjectionLane.allCases),
                kind: .incremental,
                transactionCount: 1,
                events: [taskChangedEvent]
            )
            await probe.reset()

            try fixture.insertTask(
                title: "Remote import",
                author: .syncReconciliation
            )
            scheduler.enqueue(CommittedMutationSystemProjectionReceipt(
                events: [.remoteImportCompleted]
            ))
            await scheduler.waitUntilIdle()

            await expectProjectionBatch(
                probe.invocations(),
                lanes: [
                    .widget,
                    .watch,
                    .liveActivity,
                ],
                kind: .incremental,
                transactionCount: 1,
                events: [taskChangedEvent]
            )
            await probe.reset()

            try fixture.insertTask(
                title: "Local after remote",
                author: .localMutation
            )
            scheduler.enqueue(CommittedMutationSystemProjectionReceipt(
                events: [taskChangedEvent]
            ))
            await scheduler.waitUntilIdle()

            // A transaction count of one on the sync lane proves that its
            // cursor advanced past the remote transaction without projecting
            // it, rather than replaying remote history with this local write.
            await expectProjectionBatch(
                probe.invocations(),
                lanes: Set(PersistentHistoryProjectionLane.allCases),
                kind: .incremental,
                transactionCount: 1,
                events: [taskChangedEvent]
            )
        }
    }

    @Test @MainActor
    func failedLaneKeepsItsFrontierWhileSiblingsAdvanceAndRetryOnlyReplaysIt()
        async throws
    {
        try await withCommittedMutationHistoryFixture(
            name: #function
        ) { fixture in
            let probe = CommittedMutationHistoryProjectorProbe(
                failuresRemaining: [.widget: 1]
            )
            let registry = fixture.makeRegistry(probe: probe)
            let scheduler = try registry.scheduler(
                for: fixture.container
            )

            scheduler.enqueue(CommittedMutationSystemProjectionReceipt(
                events: [.fullSync]
            ))
            await scheduler.waitUntilIdle()

            await expectProjectionBatch(
                probe.invocations(),
                lanes: Set(PersistentHistoryProjectionLane.allCases),
                kind: .fullReconciliation,
                transactionCount: 0,
                events: [.fullSync]
            )
            #expect(scheduler.failedSinks == [.widget])
            await probe.reset()

            scheduler.retryFailedSinks()
            await scheduler.waitUntilIdle()

            await expectProjectionBatch(
                probe.invocations(),
                lanes: [.widget],
                kind: .fullReconciliation,
                transactionCount: 0,
                events: [.fullSync]
            )
            #expect(scheduler.failedSinks.isEmpty)
        }
    }

    @Test @MainActor
    func rebuiltRegistryUsesDurableCursorsAndSkipsAcknowledgedFrontier()
        async throws
    {
        try await withCommittedMutationHistoryFixture(
            name: #function
        ) { fixture in
            let firstProbe = CommittedMutationHistoryProjectorProbe()
            var firstRegistry:
                CommittedMutationSystemProjectionSchedulerRegistry? =
                fixture.makeRegistry(probe: firstProbe)
            var firstScheduler:
                CommittedMutationSystemProjectionScheduler? =
                try firstRegistry?.scheduler(for: fixture.container)

            firstScheduler?.enqueue(
                CommittedMutationSystemProjectionReceipt(
                    events: [.fullSync]
                )
            )
            await firstScheduler?.waitUntilIdle()
            #expect(await firstProbe.invocations().count == 4)

            firstScheduler = nil
            firstRegistry = nil

            let rebuiltProbe =
                CommittedMutationHistoryProjectorProbe()
            let rebuiltRegistry = fixture.makeRegistry(
                probe: rebuiltProbe
            )
            let rebuiltScheduler = try rebuiltRegistry.scheduler(
                for: fixture.container
            )
            rebuiltScheduler.enqueue(
                CommittedMutationSystemProjectionReceipt(
                    events: [.fullSync]
                )
            )
            await rebuiltScheduler.waitUntilIdle()

            #expect(await rebuiltProbe.invocations().isEmpty)
        }
    }

    @Test @MainActor
    func containerRevisionFenceRejectsBlockedOldRegistrationAndRetriesWithNewContainer()
        async throws
    {
        try await withCommittedMutationHistoryFixture(
            name: #function
        ) { fixture in
            var oldContainer: ModelContainer? =
                try fixture.makeSiblingContainer()
            let oldContainerIdentity = try ObjectIdentifier(
                #require(oldContainer)
            )
            let oldContainerReference =
                try weakCommittedMutationHistoryContainer(
                    oldContainer
                )
            let allLanes = Set(
                PersistentHistoryProjectionLane.allCases
            )
            let allSinks = Set(
                CommittedMutationSystemProjectionSink.allCases
            )
            let probe = CommittedMutationHistoryProjectorProbe(
                blockedRegistration: oldContainerIdentity,
                blockedLanes: allLanes
            )
            let registry = fixture.makeRegistry(probe: probe)
            let scheduler = try registry.scheduler(
                for: #require(oldContainer)
            )
            let oldReceiptID = UUID()

            scheduler.enqueue(
                CommittedMutationSystemProjectionReceipt(
                    id: oldReceiptID,
                    events: [.fullSync]
                )
            )
            await probe.waitUntilBlocked(lanes: allLanes)

            var newContainer: ModelContainer? =
                try fixture.makeSiblingContainer()
            let newContainerIdentity = try ObjectIdentifier(
                #require(newContainer)
            )
            let newContainerReference =
                try weakCommittedMutationHistoryContainer(
                    newContainer
                )
            let returnedScheduler = try registry.scheduler(
                for: #require(newContainer)
            )
            #expect(returnedScheduler === scheduler)

            let trailingReceiptID = UUID()
            returnedScheduler.enqueue(
                CommittedMutationSystemProjectionReceipt(
                    id: trailingReceiptID,
                    events: [.fullSync]
                )
            )
            oldContainer = nil
            await probe.releaseBlockedInvocations()
            await scheduler.waitUntilIdle()

            // Every old effect completed after the provider revision changed.
            // None may acknowledge either its scheduler generation or the
            // durable history frontier.
            #expect(scheduler.failedSinks == allSinks)
            #expect(
                allSinks.allSatisfy {
                    scheduler.acknowledgedGeneration(for: $0) == nil
                }
            )
            #expect(
                await probe.records().filter {
                    $0.registration == oldContainerIdentity
                }.count == allLanes.count
            )
            #expect(
                await probe.records().contains {
                    $0.registration == newContainerIdentity
                } == false
            )

            scheduler.retryFailedSinks()
            await scheduler.waitUntilIdle()

            let newRegistrationRecords =
                await probe.records().filter {
                    $0.registration == newContainerIdentity
                }
            expectProjectionBatch(
                newRegistrationRecords.map(\.invocation),
                lanes: allLanes,
                kind: .fullReconciliation,
                transactionCount: 0,
                events: [.fullSync]
            )
            #expect(scheduler.failedSinks.isEmpty)
            #expect(
                allSinks.allSatisfy {
                    scheduler.acknowledgedGeneration(for: $0)
                        == scheduler.latestGeneration
                }
            )
            #expect(
                allSinks.allSatisfy {
                    scheduler.acknowledgedReceiptCount(for: $0) == 2
                }
            )

            newContainer = nil
            await Task.yield()
            #expect(oldContainerReference.container == nil)
            #expect(newContainerReference.container == nil)
        }
    }
}

private let taskChangedEvent = StoreDomainEvent.taskChanged(
    taskID: nil,
    affectedAncestorIDs: []
)

private func expectProjectionBatch(
    _ invocations: [PersistentHistoryProjectionInvocation],
    lanes: Set<PersistentHistoryProjectionLane>,
    kind: PersistentHistoryProjectionInvocationKind,
    transactionCount: Int,
    events: Set<StoreDomainEvent>
) {
    #expect(invocations.count == lanes.count)
    #expect(Set(invocations.map(\.lane)) == lanes)
    #expect(invocations.allSatisfy { $0.kind == kind })
    #expect(
        invocations.allSatisfy {
            $0.transactionCount == transactionCount
        }
    )
    #expect(invocations.allSatisfy { $0.events == events })
}

@MainActor
private func establishFourLaneBaseline(
    scheduler: CommittedMutationSystemProjectionScheduler,
    probe: CommittedMutationHistoryProjectorProbe
) async throws {
    scheduler.enqueue(CommittedMutationSystemProjectionReceipt(
        events: [.fullSync]
    ))
    await scheduler.waitUntilIdle()
    await expectProjectionBatch(
        probe.invocations(),
        lanes: Set(PersistentHistoryProjectionLane.allCases),
        kind: .fullReconciliation,
        transactionCount: 0,
        events: [.fullSync]
    )
    await probe.reset()
}

@MainActor
private final class CommittedMutationHistoryFixture {
    let container: ModelContainer
    let directory: URL
    let localFile = DurableLocalFile()

    init(name: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CommittedMutationHistoryIntegration-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let schema = TimeTrackerModelRegistry.currentSchema
        container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [
                ModelConfiguration(
                    "CommittedMutationHistoryIntegration",
                    schema: schema,
                    url: directory.appendingPathComponent(
                        "timetracker.store"
                    ),
                    cloudKitDatabase: .none
                ),
            ]
        )
    }

    func makeRegistry(
        probe: CommittedMutationHistoryProjectorProbe
    ) -> CommittedMutationSystemProjectionSchedulerRegistry {
        CommittedMutationSystemProjectionSchedulerRegistry(
            localFile: localFile,
            projectorFactory: { (container: ModelContainer)
                -> PersistentHistoryProjectionDriver.Effect in
                let registration = ObjectIdentifier(container)
                return { invocation in
                    try await probe.perform(
                        invocation,
                        registration: registration
                    )
                }
            }
        )
    }

    func makeSiblingContainer() throws -> ModelContainer {
        let schema = TimeTrackerModelRegistry.currentSchema
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [
                ModelConfiguration(
                    "CommittedMutationHistoryIntegration",
                    schema: schema,
                    url: directory.appendingPathComponent(
                        "timetracker.store"
                    ),
                    cloudKitDatabase: .none
                ),
            ]
        )
    }

    func insertTask(
        title: String,
        author: TimeTrackerHistoryAuthor
    ) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try context.performAtomicMutation(author: author) {
            context.insert(TaskNode(
                title: title,
                parentID: nil,
                deviceID: "committed-history-integration-test"
            ))
        }
    }
}

@MainActor
private func withCommittedMutationHistoryFixture(
    name: String,
    operation: @MainActor (
        CommittedMutationHistoryFixture
    ) async throws -> Void
) async throws {
    var fixture: CommittedMutationHistoryFixture?
    do {
        fixture = try CommittedMutationHistoryFixture(name: name)
        let directory = try #require(fixture?.directory)
        try await operation(#require(fixture))
        fixture = nil
        try? FileManager.default.removeItem(at: directory)
    } catch {
        let directory = fixture?.directory
        fixture = nil
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        throw error
    }
}

private actor CommittedMutationHistoryProjectorProbe {
    private var recorded: [
        CommittedMutationHistoryProjectorRecord
    ] = []
    private var failuresRemaining: [
        PersistentHistoryProjectionLane: Int
    ]
    private let blockedRegistration: ObjectIdentifier?
    private let blockedLanes: Set<PersistentHistoryProjectionLane>
    private var reachedBlockedLanes:
        Set<PersistentHistoryProjectionLane> = []
    private var blockedLaneWaiters: [
        CheckedContinuation<Void, Never>
    ] = []
    private var releaseContinuations: [
        PersistentHistoryProjectionLane:
            CheckedContinuation<Void, Never>
    ] = [:]

    init(
        failuresRemaining: [PersistentHistoryProjectionLane: Int] = [:],
        blockedRegistration: ObjectIdentifier? = nil,
        blockedLanes: Set<PersistentHistoryProjectionLane> = []
    ) {
        self.failuresRemaining = failuresRemaining
        self.blockedRegistration = blockedRegistration
        self.blockedLanes = blockedLanes
    }

    func perform(
        _ invocation: PersistentHistoryProjectionInvocation,
        registration: ObjectIdentifier
    ) async throws {
        recorded.append(
            CommittedMutationHistoryProjectorRecord(
                registration: registration,
                invocation: invocation
            )
        )
        let lane = invocation.lane
        if registration == blockedRegistration,
           blockedLanes.contains(lane),
           reachedBlockedLanes.insert(lane).inserted
        {
            if reachedBlockedLanes.isSuperset(of: blockedLanes) {
                let waiters = blockedLaneWaiters
                blockedLaneWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
            await withCheckedContinuation { continuation in
                releaseContinuations[lane] = continuation
            }
        }
        let remaining = failuresRemaining[lane, default: 0]
        guard remaining > 0 else { return }
        failuresRemaining[lane] = remaining - 1
        throw CommittedMutationHistoryProjectorProbeError.expected
    }

    func invocations() -> [PersistentHistoryProjectionInvocation] {
        recorded.map(\.invocation)
    }

    func records() -> [CommittedMutationHistoryProjectorRecord] {
        recorded
    }

    func reset() {
        recorded.removeAll()
    }

    func waitUntilBlocked(
        lanes: Set<PersistentHistoryProjectionLane>
    ) async {
        guard reachedBlockedLanes.isSuperset(of: lanes) == false
        else {
            return
        }
        await withCheckedContinuation { continuation in
            blockedLaneWaiters.append(continuation)
        }
    }

    func releaseBlockedInvocations() {
        let continuations = Array(releaseContinuations.values)
        releaseContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private nonisolated struct CommittedMutationHistoryProjectorRecord:
    Sendable
{
    let registration: ObjectIdentifier
    let invocation: PersistentHistoryProjectionInvocation
}

@MainActor
private final class WeakCommittedMutationHistoryContainer {
    weak var container: ModelContainer?

    init(_ container: ModelContainer) {
        self.container = container
    }
}

@MainActor
private func weakCommittedMutationHistoryContainer(
    _ container: ModelContainer?
) throws -> WeakCommittedMutationHistoryContainer {
    try WeakCommittedMutationHistoryContainer(#require(container))
}

private nonisolated enum CommittedMutationHistoryProjectorProbeError:
    Error
{
    case expected
}
