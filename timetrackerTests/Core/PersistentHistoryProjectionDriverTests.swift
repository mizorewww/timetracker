import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct PersistentHistoryProjectionDriverTests {
    @Test @MainActor
    func emptyStoreEstablishesOneFullBaselineThenProcessesFirstTransaction()
        async throws
    {
        try await withPersistentHistoryProjectionFixture(
            name: #function
        ) { fixture in
            #expect(try fixture.historyTransactions().isEmpty)
            let probe = PersistentHistoryProjectionEffectProbe()
            let driver = try fixture.makeDriver(probe: probe)

            try await driver.run(.widget)
            try await driver.run(.widget)

            #expect(
                await probe.invocations() == [
                    PersistentHistoryProjectionInvocation(
                        lane: .widget,
                        kind: .fullReconciliation,
                        transactionCount: 0,
                        events: [.fullSync]
                    ),
                ]
            )

            try fixture.insertTask(
                title: "First transaction",
                author: .localMutation
            )
            try await driver.run(.widget)

            #expect(
                await probe.invocations().map(\.kind) == [
                    .fullReconciliation,
                    .incremental,
                ]
            )
            #expect(
                await probe.invocations().last?.transactionCount == 1
            )
            #expect(
                await probe.invocations().last?.events == [
                    .taskChanged(
                        taskID: nil,
                        affectedAncestorIDs: []
                    ),
                ]
            )
        }
    }

    @Test @MainActor
    func fullReconciliationCapturesTailBeforeRunningItsEffect() async throws {
        try await withPersistentHistoryProjectionFixture(
            name: #function
        ) { fixture in
            try fixture.insertTask(
                title: "Before full reconciliation",
                author: .localMutation
            )
            let probe = PersistentHistoryProjectionEffectProbe(
                blockedInvocationIndices: [0]
            )
            let driver = try fixture.makeDriver(probe: probe)

            let firstRun = Task {
                try await driver.run(.watch)
            }
            await probe.waitForInvocation(at: 0)
            try fixture.insertTask(
                title: "While full reconciliation is blocked",
                author: .localMutation
            )
            await probe.releaseInvocation(at: 0)
            try await firstRun.value

            try await driver.run(.watch)

            let invocations = await probe.invocations()
            #expect(invocations.map(\.kind) == [
                .fullReconciliation,
                .incremental,
            ])
            #expect(invocations.map(\.transactionCount) == [1, 1])
        }
    }

    @Test @MainActor
    func nonLocalHistoryAdvancesSyncCursorWithoutRunningSyncEffect()
        async throws
    {
        try await withPersistentHistoryProjectionFixture(
            name: #function
        ) { fixture in
            let probe = PersistentHistoryProjectionEffectProbe()
            let driver = try fixture.makeDriver(probe: probe)
            try await driver.run(.syncSnapshot)

            try fixture.insertTask(
                title: "Imported",
                author: .syncReconciliation
            )
            try fixture.insertTask(
                title: "Startup maintenance",
                author: .bootstrapMaintenance
            )
            try fixture.insertTask(
                title: "Legacy nil author",
                authorRawValue: nil
            )
            try fixture.insertTask(
                title: "Unknown future author",
                authorRawValue:
                "me.mezorewww.timetracker.unknown-test-author"
            )
            try await driver.run(.syncSnapshot)
            #expect(await probe.invocations().count == 1)

            try fixture.insertTask(
                title: "Local",
                author: .localMutation
            )
            try fixture.insertTask(
                title: "Trailing maintenance",
                author: .bootstrapMaintenance
            )
            try await driver.run(.syncSnapshot)
            try await driver.run(.syncSnapshot)

            let invocations = await probe.invocations()
            #expect(invocations.map(\.kind) == [
                .fullReconciliation,
                .incremental,
            ])
            #expect(invocations.last?.transactionCount == 2)
            #expect(
                invocations.last?.events == [
                    .taskChanged(
                        taskID: nil,
                        affectedAncestorIDs: []
                    ),
                ]
            )
        }
    }

    @Test
    func modelEntityNamesMapToConservativeDomainEventsAndLaneTargets() {
        let taskEvent = StoreDomainEvent.taskChanged(
            taskID: nil,
            affectedAncestorIDs: []
        )
        let ledgerEvent = StoreDomainEvent.ledgerChanged(
            taskID: nil,
            dateInterval: nil,
            isVisible: true
        )

        #expect(
            PersistentHistoryProjectionImpact.events(
                forEntityNames: [
                    "TaskNode",
                    "TaskCategory",
                    "TaskRecurrenceRule",
                ]
            ) == [taskEvent]
        )
        #expect(
            PersistentHistoryProjectionImpact.events(
                forEntityNames: [
                    "TimeSession",
                    "TimeSegment",
                    "PomodoroRun",
                    "SyncedPreference",
                    "CountdownEvent",
                    "ChecklistItem",
                    "InboxItem",
                ]
            ) == [
                ledgerEvent,
                .pomodoroChanged(
                    runID: nil,
                    sessionID: nil,
                    taskID: nil
                ),
                .preferenceChanged(key: nil),
                .countdownChanged,
                .checklistChanged(
                    taskID: nil,
                    affectedAncestorIDs: []
                ),
                .inboxChanged(itemIDs: []),
            ]
        )
        #expect(
            PersistentHistoryProjectionImpact.events(
                forEntityNames: ["FutureModel"]
            ) == [.fullSync]
        )
        #expect(
            PersistentHistoryProjectionImpact.affects(
                lane: .widget,
                events: [.inboxChanged(itemIDs: [])]
            ) == false
        )
        #expect(
            PersistentHistoryProjectionImpact.affects(
                lane: .watch,
                events: [.preferenceChanged(key: nil)]
            )
        )
        #expect(
            PersistentHistoryProjectionImpact.affects(
                lane: .syncSnapshot,
                events: [.countdownChanged]
            )
        )
    }

    @Test @MainActor
    func everyCurrentStoreEntityHasAnExplicitProjectionImpact() {
        for entityName in TimeTrackerModelRegistry
            .cloudSyncedUserModelNames
        {
            #expect(
                PersistentHistoryProjectionImpact.events(
                    forEntityNames: [entityName]
                ) != [.fullSync],
                "Missing projection impact for \(entityName)"
            )
        }
    }

    @Test @MainActor
    func failedEffectDoesNotAdvanceItsLaneCursor() async throws {
        try await withPersistentHistoryProjectionFixture(
            name: #function
        ) { fixture in
            let probe = PersistentHistoryProjectionEffectProbe(
                failingInvocationIndices: [1]
            )
            let driver = try fixture.makeDriver(probe: probe)
            try await driver.run(.liveActivity)
            try fixture.insertTask(
                title: "Retry me",
                author: .localMutation
            )

            await #expect(
                throws: PersistentHistoryProjectionEffectProbeError.self
            ) {
                try await driver.run(.liveActivity)
            }
            try await driver.run(.liveActivity)

            let invocations = await probe.invocations()
            #expect(invocations.map(\.kind) == [
                .fullReconciliation,
                .incremental,
                .incremental,
            ])
            #expect(invocations.map(\.transactionCount) == [0, 1, 1])
        }
    }

    @Test @MainActor
    func independentLanesKeepIndependentHistoryFrontiers() async throws {
        try await withPersistentHistoryProjectionFixture(
            name: #function
        ) { fixture in
            let probe = PersistentHistoryProjectionEffectProbe()
            let driver = try fixture.makeDriver(probe: probe)
            try await driver.run(.widget)
            try fixture.insertTask(
                title: "After widget baseline",
                author: .localMutation
            )
            try await driver.run(.watch)
            try await driver.run(.widget)

            let invocations = await probe.invocations()
            #expect(invocations.map(\.lane) == [
                .widget,
                .watch,
                .widget,
            ])
            #expect(invocations.map(\.kind) == [
                .fullReconciliation,
                .fullReconciliation,
                .incremental,
            ])
            #expect(invocations.map(\.transactionCount) == [0, 1, 1])
        }
    }

    @Test @MainActor
    func expiredCursorRunsFullReconciliationAndRebases() async throws {
        try await withPersistentHistoryProjectionFixture(
            name: #function
        ) { fixture in
            try fixture.insertTask(
                title: "Old frontier",
                author: .localMutation
            )
            let probe = PersistentHistoryProjectionEffectProbe()
            let driver = try fixture.makeDriver(probe: probe)
            try await driver.run(.widget)
            let oldToken = try #require(
                fixture.historyTransactions().last?.token
            )

            try fixture.insertTask(
                title: "Retained frontier",
                author: .localMutation
            )
            let retainedToken = try #require(
                fixture.historyTransactions().last?.token
            )
            try fixture.deleteHistory(before: retainedToken)

            do {
                _ = try fixture.historyTransactions(after: oldToken)
                Issue.record(
                    "Fetching after the deleted token should expire it."
                )
            } catch let error as SwiftDataError {
                #expect(error == .historyTokenExpired)
            }

            try await driver.run(.widget)
            try await driver.run(.widget)

            let invocations = await probe.invocations()
            #expect(invocations.map(\.kind) == [
                .fullReconciliation,
                .fullReconciliation,
            ])
            #expect(invocations.map(\.transactionCount) == [1, 1])
        }
    }

    @Test @MainActor
    func inMemoryStoreKeepsAProcessLocalBaselineWithoutSidecars()
        async throws
    {
        try await withPersistentHistoryProjectionFixture(
            name: #function,
            isStoredInMemoryOnly: true
        ) { fixture in
            let probe = PersistentHistoryProjectionEffectProbe()
            let driver = try fixture.makeDriver(probe: probe)

            try await driver.run(.liveActivity)
            try await driver.run(.liveActivity)
            try fixture.insertTask(
                title: "In-memory transaction",
                author: .localMutation
            )
            try await driver.run(.liveActivity)
            try await driver.run(.liveActivity)

            #expect(
                await probe.invocations().map(\.kind) == [
                    .fullReconciliation,
                    .incremental,
                ]
            )
            #expect(
                try FileManager.default.contentsOfDirectory(
                    atPath: fixture.directory.path
                ).isEmpty
            )
        }
    }

    @Test @MainActor
    func durableCursorReadDoesNotBlockMainActorHeartbeat() async throws {
        try await withPersistentHistoryProjectionFixture(
            name: #function
        ) { fixture in
            let gate = BlockingCursorReadGate()
            let localFile = DurableLocalFile(injectFault: { point in
                if point == .beforeManagedRead {
                    gate.blockFirstRead()
                }
            })
            let probe = PersistentHistoryProjectionEffectProbe()
            let driver = try fixture.makeDriver(
                probe: probe,
                localFile: localFile
            )
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
            let run = Task.detached {
                try await driver.run(.watch)
            }

            try await run.value
            await coordinator.value

            #expect(gate.firstRelease == .heartbeat)
        }
    }

    @Test @MainActor
    func paginationCarriesAuthorRoutingAcrossThePageBoundary()
        async throws
    {
        try await withPersistentHistoryProjectionFixture(
            name: #function
        ) { fixture in
            let probe = PersistentHistoryProjectionEffectProbe()
            let driver = try fixture.makeDriver(probe: probe)
            try await driver.run(.syncSnapshot)

            try fixture.insertTasks(
                count: 256,
                titlePrefix: "Remote",
                author: .syncReconciliation
            )
            try fixture.insertTask(
                title: "Local on second page",
                author: .localMutation
            )

            try await driver.run(.syncSnapshot)
            try await driver.run(.syncSnapshot)

            let invocations = await probe.invocations()
            #expect(invocations.map(\.kind) == [
                .fullReconciliation,
                .incremental,
            ])
            #expect(invocations.map(\.transactionCount) == [0, 257])
        }
    }

    @Test @MainActor
    func newDriverReplaysFailedIncrementalAndInterruptedFullWork()
        async throws
    {
        try await withPersistentHistoryProjectionFixture(
            name: #function
        ) { fixture in
            let incrementalFailureProbe =
                PersistentHistoryProjectionEffectProbe(
                    failingInvocationIndices: [1]
                )
            var driver: PersistentHistoryProjectionDriver? =
                try fixture.makeDriver(
                    probe: incrementalFailureProbe
                )
            try await driver?.run(.widget)
            try fixture.insertTask(
                title: "Persist across driver replacement",
                author: .localMutation
            )
            await #expect(
                throws: PersistentHistoryProjectionEffectProbeError.self
            ) {
                try await driver?.run(.widget)
            }
            driver = nil

            let incrementalReplayProbe =
                PersistentHistoryProjectionEffectProbe()
            driver = try fixture.makeDriver(
                probe: incrementalReplayProbe
            )
            try await driver?.run(.widget)
            #expect(
                await incrementalReplayProbe.invocations() == [
                    PersistentHistoryProjectionInvocation(
                        lane: .widget,
                        kind: .incremental,
                        transactionCount: 1,
                        events: [
                            .taskChanged(
                                taskID: nil,
                                affectedAncestorIDs: []
                            ),
                        ]
                    ),
                ]
            )
            driver = nil

            let fullFailureProbe =
                PersistentHistoryProjectionEffectProbe(
                    failingInvocationIndices: [0]
                )
            driver = try fixture.makeDriver(probe: fullFailureProbe)
            await #expect(
                throws: PersistentHistoryProjectionEffectProbeError.self
            ) {
                try await driver?.run(.watch)
            }
            driver = nil

            let fullReplayProbe =
                PersistentHistoryProjectionEffectProbe()
            driver = try fixture.makeDriver(probe: fullReplayProbe)
            try await driver?.run(.watch)
            try await driver?.run(.watch)
            #expect(
                await fullReplayProbe.invocations() == [
                    PersistentHistoryProjectionInvocation(
                        lane: .watch,
                        kind: .fullReconciliation,
                        transactionCount: 1,
                        events: [.fullSync]
                    ),
                ]
            )
        }
    }

    @Test @MainActor
    func resetEpochMismatchDropsTheStaleRegistrationBeforeRetry()
        async throws
    {
        try await withPersistentHistoryProjectionFixture(
            name: #function
        ) { fixture in
            let probe = PersistentHistoryProjectionEffectProbe()
            let driver = try fixture.makeDriver(probe: probe)
            try await driver.run(.liveActivity)

            try fixture.advanceProjectionResetEpoch()
            await #expect(
                throws: PersistentHistoryProjectionDriverError
                    .fullReconciliationSuperseded
            ) {
                try await driver.run(.liveActivity)
            }
            try await driver.run(.liveActivity)
            try await driver.run(.liveActivity)

            #expect(
                await probe.invocations().map(\.kind) == [
                    .fullReconciliation,
                    .fullReconciliation,
                ]
            )
        }
    }
}

@MainActor
private final class PersistentHistoryProjectionDriverFixture {
    let container: ModelContainer
    let directory: URL
    let storeURL: URL

    init(
        name: String,
        isStoredInMemoryOnly: Bool = false
    ) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PersistentHistoryProjectionDriverTests-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
        storeURL = directory.appendingPathComponent("timetracker.store")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let schema = TimeTrackerModelRegistry.currentSchema
        let configuration = if isStoredInMemoryOnly {
            ModelConfiguration(
                "PersistentHistoryProjectionDriver",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        } else {
            ModelConfiguration(
                "PersistentHistoryProjectionDriver",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        }
        container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    func makeDriver(
        probe: PersistentHistoryProjectionEffectProbe,
        localFile: DurableLocalFile = DurableLocalFile()
    ) throws -> PersistentHistoryProjectionDriver {
        try PersistentHistoryProjectionDriver(
            container: container,
            scope: TimerStoreScope(container: container),
            localFile: localFile
        ) { invocation in
            try await probe.perform(invocation)
        }
    }

    func insertTask(
        title: String,
        author: TimeTrackerHistoryAuthor
    ) throws {
        try insertTask(
            title: title,
            authorRawValue: author.rawValue
        )
    }

    func insertTask(
        title: String,
        authorRawValue: String?
    ) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let previousAuthor = context.author
        context.author = authorRawValue
        defer { context.author = previousAuthor }
        try context.performAtomicMutation {
            context.insert(TaskNode(
                title: title,
                parentID: nil,
                deviceID: "persistent-history-projection-test"
            ))
        }
    }

    func insertTasks(
        count: Int,
        titlePrefix: String,
        author: TimeTrackerHistoryAuthor
    ) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        for index in 0 ..< count {
            try context.performAtomicMutation(author: author) {
                context.insert(TaskNode(
                    title: "\(titlePrefix) \(index)",
                    parentID: nil,
                    deviceID:
                    "persistent-history-projection-pagination-test"
                ))
            }
        }
    }

    func historyTransactions(
        after token: DefaultHistoryToken? = nil
    ) throws -> [DefaultHistoryTransaction] {
        let context = ModelContext(container)
        let descriptor: HistoryDescriptor<DefaultHistoryTransaction> = if let token {
            HistoryDescriptor(
                predicate: #Predicate { transaction in
                    transaction.token > token
                }
            )
        } else {
            HistoryDescriptor()
        }
        return try context.fetchHistory(descriptor)
    }

    func deleteHistory(
        before token: DefaultHistoryToken
    ) throws {
        let context = ModelContext(container)
        try context.deleteHistory(
            HistoryDescriptor<DefaultHistoryTransaction>(
                predicate: #Predicate { transaction in
                    transaction.token < token
                }
            )
        )
    }

    func advanceProjectionResetEpoch() throws {
        _ = try PersistentHistoryProjectionResetFence(
            scope: TimerStoreScope(container: container)
        ).advanceForStoreReset()
    }
}

@MainActor
private func withPersistentHistoryProjectionFixture(
    name: String,
    isStoredInMemoryOnly: Bool = false,
    operation: @MainActor (
        PersistentHistoryProjectionDriverFixture
    ) async throws -> Void
) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "PersistentHistoryProjectionDriverTests-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
    var fixture: PersistentHistoryProjectionDriverFixture?
    do {
        fixture = try PersistentHistoryProjectionDriverFixture(
            name: name,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        let actualDirectory = try #require(fixture?.directory)
        try await operation(#require(fixture))
        fixture = nil
        try? FileManager.default.removeItem(at: actualDirectory)
    } catch {
        let actualDirectory = fixture?.directory ?? directory
        fixture = nil
        try? FileManager.default.removeItem(at: actualDirectory)
        throw error
    }
}

private actor PersistentHistoryProjectionEffectProbe {
    private var recorded: [PersistentHistoryProjectionInvocation] = []
    private let blockedInvocationIndices: Set<Int>
    private let failingInvocationIndices: Set<Int>
    private var entryWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var releaseContinuations: [
        Int: CheckedContinuation<Void, Never>
    ] = [:]

    init(
        blockedInvocationIndices: Set<Int> = [],
        failingInvocationIndices: Set<Int> = []
    ) {
        self.blockedInvocationIndices = blockedInvocationIndices
        self.failingInvocationIndices = failingInvocationIndices
    }

    func perform(
        _ invocation: PersistentHistoryProjectionInvocation
    ) async throws {
        let index = recorded.count
        recorded.append(invocation)
        resumeEntryWaiters(at: index)
        if blockedInvocationIndices.contains(index) {
            await withCheckedContinuation { continuation in
                releaseContinuations[index] = continuation
            }
        }
        if failingInvocationIndices.contains(index) {
            throw PersistentHistoryProjectionEffectProbeError.expected
        }
    }

    func invocations() -> [PersistentHistoryProjectionInvocation] {
        recorded
    }

    func waitForInvocation(at index: Int) async {
        guard recorded.indices.contains(index) == false else { return }
        await withCheckedContinuation { continuation in
            entryWaiters[index, default: []].append(continuation)
        }
    }

    func releaseInvocation(at index: Int) {
        releaseContinuations.removeValue(forKey: index)?.resume()
    }

    private func resumeEntryWaiters(at index: Int) {
        entryWaiters.removeValue(forKey: index)?.forEach { $0.resume() }
    }
}

private nonisolated enum PersistentHistoryProjectionEffectProbeError: Error {
    case expected
}

private final nonisolated class BlockingCursorReadGate: @unchecked Sendable {
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

    func blockFirstRead() {
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
