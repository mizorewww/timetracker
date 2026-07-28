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
    case watchNotActivated
    case watchDeliveryFailed(String)
    case liveActivityDidNotSettle
    case liveActivityUnavailable(LiveActivityFailure)

    var errorDescription: String? {
        switch self {
        case .storeContainerReleased:
            "The projection store container is no longer available."
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

@MainActor
private final class CommittedMutationModelContainerProvider {
    private final class WeakReference {
        weak var container: ModelContainer?

        init(_ container: ModelContainer) {
            self.container = container
        }
    }

    private var references: [WeakReference] = []

    init(_ container: ModelContainer) {
        update(container)
    }

    func update(_ container: ModelContainer) {
        references.removeAll {
            $0.container == nil || $0.container === container
        }
        references.append(WeakReference(container))
    }

    func currentContainer() -> ModelContainer? {
        references.removeAll { $0.container == nil }
        return references.last?.container
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
    typealias Materializer = @MainActor (
        CommittedMutationSystemProjectionWork
    ) throws -> CommittedMutationSystemProjectionMaterialization?
    typealias Publisher = @MainActor (
        CommittedMutationSystemProjectionSink,
        CommittedMutationSystemProjectionMaterialization
    ) async throws -> Void

    private enum MaterializationOutcome {
        case projected(CommittedMutationSystemProjectionMaterialization?)
        case failed(CommittedMutationMaterializationFailure)
    }

    private struct GenerationState {
        let outcome: MaterializationOutcome
        var targetedSinks: Set<CommittedMutationSystemProjectionSink>
        var materializationAttemptedSinks:
            Set<CommittedMutationSystemProjectionSink> = []
        var successfulSinks: Set<CommittedMutationSystemProjectionSink> = []
    }

    private let materializer: Materializer
    private let publisher: Publisher
    private var statesByGeneration: [UInt: GenerationState] = [:]
    private var newestRequestedGeneration: UInt = 0

    convenience init(
        container: ModelContainer,
        widgetCache: WidgetSnapshotCache? = nil,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.init(
            containerProvider:
            CommittedMutationModelContainerProvider(container),
            widgetCache: widgetCache,
            now: now
        )
    }

    fileprivate init(
        containerProvider: CommittedMutationModelContainerProvider,
        widgetCache: WidgetSnapshotCache? = nil,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        let resolvedWidgetCache = widgetCache ?? WidgetSnapshotCache()
        materializer = { _ in
            guard let container = containerProvider.currentContainer() else {
                throw CommittedMutationSystemProjectionWorkerError
                    .storeContainerReleased
            }
            let context = ModelContext(container)
            context.autosaveEnabled = false
            return try Self.materializeCurrentFacts(
                context: context,
                now: now()
            )
        }
        publisher = { sink, materialization in
            try await Self.publish(
                sink: sink,
                materialization: materialization,
                widgetCache: resolvedWidgetCache
            )
        }
    }

    init(
        materializer: @escaping Materializer,
        publisher: @escaping Publisher
    ) {
        self.materializer = materializer
        self.publisher = publisher
    }

    func perform(
        sink: CommittedMutationSystemProjectionSink,
        work: CommittedMutationSystemProjectionWork
    ) async throws {
        let materialization = try materialization(
            requestedBy: sink,
            work: work
        )
        guard let materialization else {
            markSuccessful(sink: sink, generation: work.generation)
            return
        }

        do {
            try await publisher(sink, materialization)
            markSuccessful(sink: sink, generation: work.generation)
        } catch {
            pruneSupersededGenerations()
            throw error
        }
    }

    private func materialization(
        requestedBy sink: CommittedMutationSystemProjectionSink,
        work: CommittedMutationSystemProjectionWork
    ) throws -> CommittedMutationSystemProjectionMaterialization? {
        newestRequestedGeneration = max(
            newestRequestedGeneration,
            work.generation
        )

        var state: GenerationState
        if let cached = statesByGeneration[work.generation] {
            state = cached
            state.targetedSinks.formUnion(work.targetSinks)
        } else {
            let outcome: MaterializationOutcome
            do {
                outcome = try .projected(materializer(work))
            } catch {
                outcome = .failed(
                    CommittedMutationMaterializationFailure(error)
                )
            }
            state = GenerationState(
                outcome: outcome,
                targetedSinks: work.targetSinks
            )
        }

        state.materializationAttemptedSinks.insert(sink)
        let outcome = state.outcome
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

    /// Performs a complete surface read instead of narrowing by the first
    /// sink's event set. The scheduler may give each sink a filtered event
    /// batch, so the first sink to arrive cannot define shared generation data.
    static func materializeCurrentFacts(
        context: ModelContext,
        now: Date
    ) throws -> CommittedMutationSystemProjectionMaterialization {
        let store = TimeTrackerStore()
        store.configureRepositoriesIfNeeded(context: context)
        _ = try store.refreshCommittedMutationSurfaceReadModels(
            events: [.fullSync]
        )

        let activeTaskIDs = Set(store.activeSegments.map(\.taskID))
        let widgetSnapshot = WidgetSnapshotCache.snapshot(
            activeSegments: store.activeSegments,
            taskByID: store.taskByID,
            taskParentPathByID: store.taskParentPathByID,
            recentTasks: store.frequentRecentTasks(
                excluding: activeTaskIDs,
                limit: 3
            ),
            todayGrossSeconds: store.todayGrossSeconds(now: now),
            todayWallSeconds: store.todayWallSeconds(now: now),
            generatedAt: now
        )

        return CommittedMutationSystemProjectionMaterialization(
            widgetSnapshot: widgetSnapshot,
            watchSnapshot: store.watchStateSnapshot(now: now),
            liveActivity:
            CommittedMutationLiveActivityProjection.materialize(
                activeSegments: store.activeSegments,
                tasks: store.tasks,
                now: now
            ),
            generatedAt: now
        )
    }

    private static func publish(
        sink: CommittedMutationSystemProjectionSink,
        materialization: CommittedMutationSystemProjectionMaterialization,
        widgetCache: WidgetSnapshotCache
    ) async throws {
        switch sink {
        case .widget:
            // Deliberately bypasses TimeTrackerStore.errorMessage. Projection
            // diagnostics belong to the scheduler's per-sink failure state.
            try widgetCache.save(materialization.widgetSnapshot)
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
    static let shared =
        CommittedMutationSystemProjectionSchedulerRegistry()

    private final class Entry {
        let containerProvider: CommittedMutationModelContainerProvider
        let scheduler: CommittedMutationSystemProjectionScheduler

        init(container: ModelContainer) {
            let containerProvider =
                CommittedMutationModelContainerProvider(container)
            self.containerProvider = containerProvider
            let worker = CommittedMutationSystemProjectionWorker(
                containerProvider: containerProvider
            )
            scheduler = CommittedMutationSystemProjectionScheduler {
                sink,
                work in
                try await PerformanceSignpost.interval(
                    "mutation.systemProjections"
                ) {
                    try await worker.perform(sink: sink, work: work)
                }
            }
        }

        func updateContainer(_ container: ModelContainer) {
            containerProvider.update(container)
        }

        var hasLiveContainer: Bool {
            containerProvider.currentContainer() != nil
        }
    }

    private var entriesByScope: [TimerStoreScope: Entry] = [:]

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

        let entry = Entry(container: container)
        entriesByScope[scope] = entry
        return entry.scheduler
    }
}
