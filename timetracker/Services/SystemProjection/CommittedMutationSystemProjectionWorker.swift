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

private nonisolated enum CommittedMutationMaterializationOutcome: Sendable {
    case projected(CommittedMutationSystemProjectionMaterialization?)
    case failed(CommittedMutationMaterializationFailure)
}

/// A weak handle to the store container currently backing one projection scope.
///
/// Projection entries must not retain their container: short-lived test and
/// recovery containers have to be able to disappear, and a replacement store
/// for the same scope must invalidate any cached materialization.
@MainActor
final class CommittedMutationModelContainerReference {
    private weak var container: ModelContainer?

    init(_ container: ModelContainer) {
        self.container = container
    }

    var current: ModelContainer? {
        container
    }

    /// Registers `container` for this scope and reports whether it replaced the
    /// previously registered one.
    func update(_ container: ModelContainer) -> Bool {
        if let current, current === container {
            return false
        }
        self.container = container
        return true
    }
}

/// Shares one committed-fact materialization across the independently
/// scheduled Widget, Watch, and Live Activity publications for a generation.
///
/// The last generation's materialization is cached, so publishing siblings of
/// the same generation perform one store read. A newer generation supersedes an
/// older one: the older publication is skipped rather than made visible again.
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

    private let syncRecorder: SyncRecorder
    private let materializer: Materializer
    private let publisher: Publisher
    private var cachedGeneration: UInt?
    private var cachedTask:
        Task<CommittedMutationMaterializationOutcome, Never>?
    private var newestRequestedGeneration: UInt = 0

    init(
        syncRecorder: @escaping SyncRecorder = { _ in },
        materializer: @escaping Materializer,
        publisher: @escaping Publisher
    ) {
        self.syncRecorder = syncRecorder
        self.materializer = materializer
        self.publisher = publisher
    }

    convenience init(
        containerReference: CommittedMutationModelContainerReference,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        let widgetWriter = WidgetSnapshotProjectionWriter()
        self.init(
            syncRecorder: { events in
                guard let container = containerReference.current else {
                    throw CommittedMutationSystemProjectionWorkerError
                        .storeContainerReleased
                }
                let worker = try PersistentHistorySyncSnapshotWorker(
                    container: container
                )
                let result = try await worker.record(events: events)
                if case .recorded = result {
                    StoreMutationBroadcaster
                        .publishSyncConflictPromptChange()
                }
            },
            materializer: { _ in
                guard let container = containerReference.current else {
                    throw CommittedMutationSystemProjectionWorkerError
                        .storeContainerReleased
                }
                let materializer =
                    CommittedMutationSystemSurfaceMaterializer(
                        modelContainer: container
                    )
                return try await materializer.materialize(now: now())
            },
            publisher: { sink, materialization in
                try await Self.publish(
                    sink: sink,
                    materialization: materialization,
                    widgetWriter: widgetWriter
                )
            }
        )
    }

    func perform(
        sink: CommittedMutationSystemProjectionSink,
        work: CommittedMutationSystemProjectionWork
    ) async throws {
        if sink == .syncSnapshot {
            try await syncRecorder(work.events)
            return
        }

        newestRequestedGeneration = max(
            newestRequestedGeneration,
            work.generation
        )
        guard let materialization = try await materialization(for: work) else {
            return
        }
        // A materialization started before a newer request arrived must not
        // make its older facts visible.
        guard work.generation >= newestRequestedGeneration else { return }
        try await publisher(sink, materialization)
    }

    private func materialization(
        for work: CommittedMutationSystemProjectionWork
    ) async throws -> CommittedMutationSystemProjectionMaterialization? {
        if cachedGeneration != work.generation || cachedTask == nil {
            let materializer = materializer
            cachedGeneration = work.generation
            cachedTask = Task { @MainActor in
                do {
                    let materialization = try await materializer(work)
                    return CommittedMutationMaterializationOutcome
                        .projected(materialization)
                } catch {
                    return .failed(
                        CommittedMutationMaterializationFailure(error)
                    )
                }
            }
        }
        guard let task = cachedTask else { return nil }
        switch await task.value {
        case let .projected(materialization):
            return materialization
        case let .failed(error):
            // Release the failed read so a retry can perform a fresh one.
            cachedGeneration = nil
            cachedTask = nil
            throw error
        }
    }

    func containerRegistrationDidChange() {
        cachedGeneration = nil
        cachedTask = nil
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
    static let shared =
        CommittedMutationSystemProjectionSchedulerRegistry()

    private final class Entry {
        let containerReference:
            CommittedMutationModelContainerReference
        let worker: CommittedMutationSystemProjectionWorker
        let scheduler: CommittedMutationSystemProjectionScheduler

        init(container: ModelContainer) {
            let reference = CommittedMutationModelContainerReference(
                container
            )
            containerReference = reference
            let projectionWorker =
                CommittedMutationSystemProjectionWorker(
                    containerReference: reference
                )
            worker = projectionWorker
            scheduler = CommittedMutationSystemProjectionScheduler {
                sink,
                work in
                try await PerformanceSignpost.interval(
                    "mutation.systemProjections"
                ) {
                    try await projectionWorker.perform(
                        sink: sink,
                        work: work
                    )
                }
            }
        }

        func updateContainer(_ container: ModelContainer) {
            guard containerReference.update(container) else { return }
            worker.containerRegistrationDidChange()
        }

        var hasLiveContainer: Bool {
            containerReference.current != nil
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
