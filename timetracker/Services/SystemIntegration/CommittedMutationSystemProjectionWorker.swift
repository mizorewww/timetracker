import Foundation
import SwiftData

nonisolated struct CommittedMutationLiveActivityState:
    Equatable,
    Sendable
{
    let segmentID: String
    let taskID: String
    let taskTitle: String
    let taskPath: String
    let taskPathAbbreviated: String
    let iconName: String
    let colorHex: String
    let startedAt: Date
}

nonisolated enum CommittedMutationLiveActivityProjection:
    Equatable,
    Sendable
{
    case inactive
    case active(CommittedMutationLiveActivityState)

    @MainActor
    static func materialize(
        activeSegments: [TimeSegment],
        tasks: [TaskNode],
        now: Date
    ) -> Self {
        let projectionService = LiveActivityProjectionService()
        guard let primary = projectionService.primarySegment(
            from: activeSegments,
            now: now
        ) else {
            return .inactive
        }
        let task = projectionService.taskProjection(
            taskID: primary.taskID,
            tasks: tasks,
            fallbackTitle: AppStrings.activeTimers
        )
        return .active(CommittedMutationLiveActivityState(
            segmentID: primary.id.uuidString,
            taskID: primary.taskID.uuidString,
            taskTitle: task.title,
            taskPath: task.path,
            taskPathAbbreviated: task.abbreviatedPath,
            iconName: task.iconName,
            colorHex: task.colorHex,
            startedAt: primary.startedAt
        ))
    }
}

/// One value snapshot of the committed store for every external system
/// surface. Retaining a failed generation never retains its ModelContext.
nonisolated struct CommittedMutationSystemProjectionMaterialization:
    Sendable
{
    let widgetSnapshot: WidgetSnapshot
    let watchSnapshot: WatchStateSnapshot
    let liveActivity: CommittedMutationLiveActivityProjection
    let generatedAt: Date
}

private nonisolated enum CommittedMutationSystemProjectionWorkerError:
    LocalizedError
{
    case storeContainerReleased
    case storeContainerRegistrationChanged
    case watchNotActivated
    case watchDeliveryFailed(String)
    case liveActivityDidNotSettle
    case liveActivityUnavailable(LiveActivityFailure)

    var errorDescription: String? {
        switch self {
        case .storeContainerReleased:
            "The projection store container is no longer available."
        case .storeContainerRegistrationChanged:
            "The projection store container changed while work was running."
        case .watchNotActivated:
            "Watch connectivity is not activated."
        case let .watchDeliveryFailed(message):
            "Watch application-context delivery failed: \(message)"
        case .liveActivityDidNotSettle:
            "Live Activity synchronization did not settle."
        case let .liveActivityUnavailable(failure):
            "Live Activity synchronization is unavailable: \(String(describing: failure))."
        }
    }
}

private nonisolated struct CommittedMutationMaterializationFailure:
    LocalizedError,
    Sendable
{
    let errorDescription: String?

    init(_ error: any Error) {
        errorDescription = error.localizedDescription
    }
}

private nonisolated enum CommittedMutationMaterializationOutcome: Sendable {
    case projected(CommittedMutationSystemProjectionMaterialization?)
    case failed(CommittedMutationMaterializationFailure)
}

@MainActor
private final class CommittedMutationModelContainerProvider {
    struct Registration {
        let container: ModelContainer
        let revision: UInt
    }

    private final class WeakReference {
        weak var container: ModelContainer?

        init(_ container: ModelContainer) {
            self.container = container
        }
    }

    private var references: [WeakReference] = []
    private var revision: UInt = 0
    private var resolvedContainerIdentifier: ObjectIdentifier?

    init(_ container: ModelContainer) {
        update(container)
    }

    func update(_ container: ModelContainer) {
        references.removeAll {
            $0.container == nil || $0.container === container
        }
        references.append(WeakReference(container))
        _ = resolveCurrentContainer()
    }

    func currentContainer() -> ModelContainer? {
        currentRegistration()?.container
    }

    func currentRegistration() -> Registration? {
        guard let container = resolveCurrentContainer() else {
            return nil
        }
        return Registration(
            container: container,
            revision: revision
        )
    }

    func isCurrent(revision expectedRevision: UInt) -> Bool {
        guard currentRegistration() != nil else { return false }
        return revision == expectedRevision
    }

    private func resolveCurrentContainer() -> ModelContainer? {
        references.removeAll { $0.container == nil }
        let container = references.last?.container
        let identifier = container.map(ObjectIdentifier.init)
        if identifier != resolvedContainerIdentifier {
            revision &+= 1
            resolvedContainerIdentifier = identifier
        }
        return container
    }
}

/// Shares one committed-fact materialization across the independently
/// scheduled Widget, Watch, and Live Activity publications for a generation.
///
/// A failed publisher retains the same materialization for an explicit retry,
/// while successful siblings remain acknowledged by the scheduler. When newer
/// work supersedes a fully requested older generation, the abandoned cache can
/// be released without making the older facts visible again.
@MainActor
final class CommittedMutationSystemProjectionWorker {
    typealias SyncRecorder = @MainActor @Sendable (
        Set<StoreDomainEvent>
    ) async throws -> Void
    typealias Materializer = @MainActor @Sendable (
        CommittedMutationSystemProjectionWork
    ) async throws -> CommittedMutationSystemProjectionMaterialization?
    typealias Publisher = @MainActor @Sendable (
        CommittedMutationSystemProjectionSink,
        CommittedMutationSystemProjectionMaterialization
    ) async throws -> Void
    typealias ContainerRegistrationValidator = @MainActor @Sendable (
        UInt
    ) -> Bool

    private enum MaterializationPhase {
        case inFlight(
            attemptID: UUID,
            task: Task<CommittedMutationMaterializationOutcome, Never>
        )
        case resolved(
            attemptID: UUID,
            outcome: CommittedMutationMaterializationOutcome
        )

        var attemptID: UUID {
            switch self {
            case let .inFlight(attemptID, _),
                 let .resolved(attemptID, _):
                attemptID
            }
        }
    }

    private struct GenerationState {
        let sourceContainerRevision: UInt?
        var phase: MaterializationPhase
        var targetedSinks: Set<CommittedMutationSystemProjectionSink>
        var materializationAttemptedSinks:
            Set<CommittedMutationSystemProjectionSink> = []
        var successfulSinks: Set<CommittedMutationSystemProjectionSink> = []
    }

    private let syncRecorder: SyncRecorder
    private let materializer: Materializer
    private let publisher: Publisher
    private let isContainerRegistrationCurrent:
        ContainerRegistrationValidator
    private var statesByGeneration: [UInt: GenerationState] = [:]
    private var newestRequestedGeneration: UInt = 0

    convenience init(
        container: ModelContainer,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.init(
            containerProvider:
            CommittedMutationModelContainerProvider(container),
            now: now
        )
    }

    fileprivate init(
        containerProvider: CommittedMutationModelContainerProvider,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        let widgetWriter = WidgetSnapshotProjectionWriter()
        syncRecorder = { events in
            guard let container =
                containerProvider.currentContainer()
            else {
                throw CommittedMutationSystemProjectionWorkerError
                    .storeContainerReleased
            }
            let worker = try PersistentHistorySyncSnapshotWorker(
                container: container
            )
            _ = try await worker.record(events: events)
        }
        materializer = { _ in
            guard let container = containerProvider.currentContainer() else {
                throw CommittedMutationSystemProjectionWorkerError
                    .storeContainerReleased
            }
            let materializer =
                CommittedMutationSystemSurfaceMaterializer(
                    modelContainer: container
                )
            return try await materializer.materialize(
                now: now()
            )
        }
        publisher = { sink, materialization in
            try await Self.publish(
                sink: sink,
                materialization: materialization,
                widgetWriter: widgetWriter
            )
        }
        isContainerRegistrationCurrent = { revision in
            containerProvider.isCurrent(revision: revision)
        }
    }

    init(
        syncRecorder: @escaping SyncRecorder = { _ in },
        materializer: @escaping Materializer,
        publisher: @escaping Publisher,
        isContainerRegistrationCurrent:
        @escaping ContainerRegistrationValidator = { _ in true }
    ) {
        self.syncRecorder = syncRecorder
        self.materializer = materializer
        self.publisher = publisher
        self.isContainerRegistrationCurrent =
            isContainerRegistrationCurrent
    }

    func perform(
        sink: CommittedMutationSystemProjectionSink,
        work: CommittedMutationSystemProjectionWork,
        expectedContainerRevision: UInt? = nil
    ) async throws {
        try requireCurrentContainerRegistration(
            expectedContainerRevision
        )
        if sink == .syncSnapshot {
            try await syncRecorder(work.events)
            try requireCurrentContainerRegistration(
                expectedContainerRevision
            )
            return
        }

        let materialization = try await materialization(
            requestedBy: sink,
            work: work,
            sourceContainerRevision: expectedContainerRevision
        )
        try requireCurrentContainerRegistration(
            expectedContainerRevision
        )
        guard let materialization else {
            markSuccessful(sink: sink, generation: work.generation)
            return
        }

        do {
            try requireCurrentContainerRegistration(
                expectedContainerRevision
            )
            try await publisher(sink, materialization)
            try requireCurrentContainerRegistration(
                expectedContainerRevision
            )
            markSuccessful(sink: sink, generation: work.generation)
        } catch {
            discardGenerationIfSourcedFromChangedRegistration(
                generation: work.generation,
                expectedRevision: expectedContainerRevision
            )
            pruneSupersededGenerations()
            throw error
        }
    }

    private func materialization(
        requestedBy sink: CommittedMutationSystemProjectionSink,
        work: CommittedMutationSystemProjectionWork,
        sourceContainerRevision: UInt?
    ) async throws -> CommittedMutationSystemProjectionMaterialization? {
        do {
            try requireCurrentContainerRegistration(
                sourceContainerRevision
            )
        } catch {
            discardGenerationIfSourcedFromChangedRegistration(
                generation: work.generation,
                expectedRevision: sourceContainerRevision
            )
            throw error
        }
        let systemSurfaceTargets = work.targetSinks.intersection(
            CommittedMutationSystemProjectionSink.systemSurfaceCases
        )
        newestRequestedGeneration = max(
            newestRequestedGeneration,
            work.generation
        )

        var state: GenerationState
        if let cached = statesByGeneration[work.generation],
           cached.sourceContainerRevision == sourceContainerRevision
        {
            state = cached
            state.targetedSinks.formUnion(systemSurfaceTargets)
        } else {
            statesByGeneration[work.generation] = nil
            let attemptID = UUID()
            let materializer = materializer
            let task:
                Task<CommittedMutationMaterializationOutcome, Never> =
                Task { @MainActor in
                    do {
                        let materialization = try await materializer(
                            work
                        )
                        return CommittedMutationMaterializationOutcome
                            .projected(materialization)
                    } catch {
                        return .failed(
                            CommittedMutationMaterializationFailure(error)
                        )
                    }
                }
            state = GenerationState(
                sourceContainerRevision: sourceContainerRevision,
                phase: .inFlight(
                    attemptID: attemptID,
                    task: task
                ),
                targetedSinks: systemSurfaceTargets
            )
        }
        statesByGeneration[work.generation] = state
        pruneSupersededGenerations()

        let attemptID = state.phase.attemptID
        let outcome: CommittedMutationMaterializationOutcome
        switch state.phase {
        case let .inFlight(_, task):
            outcome = await task.value
            do {
                try requireCurrentContainerRegistration(
                    sourceContainerRevision
                )
            } catch {
                discardGenerationIfSourcedFromChangedRegistration(
                    generation: work.generation,
                    expectedRevision: sourceContainerRevision
                )
                throw error
            }
            guard var current = statesByGeneration[work.generation],
                  current.sourceContainerRevision ==
                  sourceContainerRevision,
                  current.phase.attemptID == attemptID
            else {
                throw CommittedMutationSystemProjectionWorkerError
                    .storeContainerRegistrationChanged
            }
            current.phase = .resolved(
                attemptID: attemptID,
                outcome: outcome
            )
            state = current
        case let .resolved(_, resolved):
            outcome = resolved
        }

        state.materializationAttemptedSinks.insert(sink)
        if case .failed = outcome,
           state.materializationAttemptedSinks.isSuperset(
               of: state.targetedSinks
           )
        {
            // Every initially targeted lane observed the same read failure.
            // Release it so an explicit scheduler retry can perform one fresh
            // store read and recover without waiting for another mutation.
            statesByGeneration[work.generation] = nil
        } else {
            statesByGeneration[work.generation] = state
        }
        pruneSupersededGenerations()

        switch outcome {
        case let .projected(materialization):
            return materialization
        case let .failed(error):
            throw error
        }
    }

    func containerRegistrationDidChange() {
        // Dropping a Task handle does not cancel an already-started read. Its
        // attempt token simply cannot reinsert or publish an obsolete DTO.
        statesByGeneration.removeAll()
    }

    private func requireCurrentContainerRegistration(
        _ expectedRevision: UInt?
    ) throws {
        guard let expectedRevision else { return }
        guard isContainerRegistrationCurrent(expectedRevision) else {
            throw CommittedMutationSystemProjectionWorkerError
                .storeContainerRegistrationChanged
        }
    }

    private func discardGenerationIfSourcedFromChangedRegistration(
        generation: UInt,
        expectedRevision: UInt?
    ) {
        guard let expectedRevision,
              isContainerRegistrationCurrent(expectedRevision) == false,
              statesByGeneration[generation]?
              .sourceContainerRevision == expectedRevision
        else {
            return
        }
        statesByGeneration[generation] = nil
    }

    private func markSuccessful(
        sink: CommittedMutationSystemProjectionSink,
        generation: UInt
    ) {
        guard var state = statesByGeneration[generation] else { return }
        state.successfulSinks.insert(sink)
        if state.successfulSinks.isSuperset(of: state.targetedSinks) {
            statesByGeneration[generation] = nil
        } else {
            statesByGeneration[generation] = state
        }
        pruneSupersededGenerations()
    }

    private func pruneSupersededGenerations() {
        for generation in statesByGeneration.keys
            where generation < newestRequestedGeneration
        {
            statesByGeneration[generation] = nil
        }
    }

    private static func publish(
        sink: CommittedMutationSystemProjectionSink,
        materialization: CommittedMutationSystemProjectionMaterialization,
        widgetWriter: WidgetSnapshotProjectionWriter
    ) async throws {
        switch sink {
        case .syncSnapshot:
            assertionFailure(
                "Sync snapshot publication bypassed its dedicated recorder."
            )
        case .widget:
            // Deliberately bypasses TimeTrackerStore.errorMessage. Projection
            // diagnostics belong to the scheduler's per-sink failure state.
            try await widgetWriter.save(
                materialization.widgetSnapshot
            )
        case .watch:
            try publishWatch(materialization.watchSnapshot)
        case .liveActivity:
            try await publishLiveActivity(materialization)
        }
    }

    private static func publishWatch(
        _ snapshot: WatchStateSnapshot
    ) throws {
        #if os(iOS) && canImport(WatchConnectivity)
        let bridge = WatchConnectivityBridge.shared
        let applicationContextStatus = bridge.updateApplicationContext(snapshot)
        _ = bridge.sendReachableMessage(snapshot)

        switch applicationContextStatus {
        case .submitted, .unavailable:
            return
        case .notActivated:
            throw CommittedMutationSystemProjectionWorkerError
                .watchNotActivated
        case .notReachable:
            // updateApplicationContext never reports this status. Treat it as
            // retryable if a future implementation does.
            throw CommittedMutationSystemProjectionWorkerError
                .watchDeliveryFailed("Watch is not reachable.")
        case let .failed(message):
            throw CommittedMutationSystemProjectionWorkerError
                .watchDeliveryFailed(message)
        }
        #else
        _ = snapshot
        #endif
    }

    private static func publishLiveActivity(
        _ materialization: CommittedMutationSystemProjectionMaterialization
    ) async throws {
        #if os(iOS) && canImport(ActivityKit)
        let coordinator = LiveActivityCoordinator.shared
        coordinator.sync(projection: materialization.liveActivity)
        await coordinator.waitUntilIdle()

        switch coordinator.status {
        case .ready, .active:
            return
        case .synchronizing:
            throw CommittedMutationSystemProjectionWorkerError
                .liveActivityDidNotSettle
        case let .unavailable(failure):
            switch failure {
            case .backgroundStart, .capacity, .system:
                throw CommittedMutationSystemProjectionWorkerError
                    .liveActivityUnavailable(failure)
            case .unsupported,
                 .denied,
                 .configuration,
                 .payloadTooLarge,
                 .removed:
                // These require a capability, settings, configuration, or
                // explicit user action. Automatic mutation retries would not
                // make progress and could recreate a dismissed activity.
                return
            }
        }
        #else
        _ = materialization
        #endif
    }
}

/// One scheduler per physical store coordinates projections across configured
/// scene facades. Entries retain neither their ModelContainer nor a
/// ModelContext, so short-lived test and recovery containers can disappear.
@MainActor
final class CommittedMutationSystemProjectionSchedulerRegistry {
    typealias ProjectorFactory = @MainActor @Sendable (
        ModelContainer
    ) -> PersistentHistoryProjectionDriver.Effect

    static let shared =
        CommittedMutationSystemProjectionSchedulerRegistry()

    private final class Entry {
        let containerProvider: CommittedMutationModelContainerProvider
        let scheduler: CommittedMutationSystemProjectionScheduler
        let worker: CommittedMutationSystemProjectionWorker

        init(
            container: ModelContainer,
            scope: TimerStoreScope,
            localFile: DurableLocalFile,
            projectorFactory: ProjectorFactory?
        ) {
            let containerProvider =
                CommittedMutationModelContainerProvider(container)
            self.containerProvider = containerProvider
            let projectionWorker =
                CommittedMutationSystemProjectionWorker(
                    containerProvider: containerProvider
                )
            worker = projectionWorker
            scheduler = CommittedMutationSystemProjectionScheduler {
                sink,
                work in
                try await PerformanceSignpost.interval(
                    "mutation.systemProjections"
                ) {
                    guard let registration =
                        containerProvider.currentRegistration()
                    else {
                        throw CommittedMutationSystemProjectionWorkerError
                            .storeContainerReleased
                    }
                    let registrationRevision = registration.revision
                    let driver = PersistentHistoryProjectionDriver(
                        container: registration.container,
                        scope: scope,
                        localFile: localFile
                    ) { invocation in
                        guard await containerProvider.isCurrent(
                            revision: registrationRevision
                        ) else {
                            throw CommittedMutationSystemProjectionWorkerError
                                .storeContainerRegistrationChanged
                        }

                        if let projectorFactory {
                            let projector = await projectorFactory(
                                registration.container
                            )
                            try await projector(invocation)
                        } else {
                            try await projectionWorker.perform(
                                sink: sink,
                                work:
                                CommittedMutationSystemProjectionWork(
                                    generation: work.generation,
                                    targetSinks: work.targetSinks,
                                    receiptIDs: work.receiptIDs,
                                    events: invocation.events
                                ),
                                expectedContainerRevision:
                                registrationRevision
                            )
                        }

                        guard await containerProvider.isCurrent(
                            revision: registrationRevision
                        ) else {
                            throw CommittedMutationSystemProjectionWorkerError
                                .storeContainerRegistrationChanged
                        }
                    }
                    try await driver.run(
                        sink.persistentHistoryLane,
                        forceCurrentStateEffect:
                        work.forceCurrentStateProjection
                    )
                }
            }
        }

        func updateContainer(_ container: ModelContainer) {
            let previousRevision =
                containerProvider.currentRegistration()?.revision
            containerProvider.update(container)
            guard containerProvider.currentRegistration()?.revision !=
                previousRevision
            else {
                return
            }
            worker.containerRegistrationDidChange()
        }

        var hasLiveContainer: Bool {
            containerProvider.currentContainer() != nil
        }
    }

    private var entriesByScope: [TimerStoreScope: Entry] = [:]
    private let localFile: DurableLocalFile
    private let projectorFactory: ProjectorFactory?

    init(
        localFile: DurableLocalFile = DurableLocalFile(),
        projectorFactory: ProjectorFactory? = nil
    ) {
        self.localFile = localFile
        self.projectorFactory = projectorFactory
    }

    func scheduler(
        for container: ModelContainer
    ) throws -> CommittedMutationSystemProjectionScheduler {
        entriesByScope = entriesByScope.filter {
            $0.value.hasLiveContainer
        }

        let scope = try TimerStoreScope(container: container)
        if let entry = entriesByScope[scope] {
            entry.updateContainer(container)
            return entry.scheduler
        }

        let entry = Entry(
            container: container,
            scope: scope,
            localFile: localFile,
            projectorFactory: projectorFactory
        )
        entriesByScope[scope] = entry
        return entry.scheduler
    }
}
