import Foundation
import OSLog
import SwiftData

nonisolated enum CommittedMutationSystemProjectionSink:
    CaseIterable,
    Hashable,
    Sendable
{
    case widget
    case watch
    case liveActivity

    /// The surfaces that display facts touched by `events`.
    static func sinks(showing events: Set<StoreDomainEvent>) -> Set<Self> {
        var sinks: Set<Self> = []
        for event in events {
            switch event {
            case .taskChanged,
                 .ledgerChanged,
                 .pomodoroChanged,
                 .remoteImportCompleted,
                 .fullSync:
                return Set(allCases)
            case .preferenceChanged:
                sinks.insert(.watch)
            case .checklistChanged,
                 .countdownChanged,
                 .inboxChanged:
                break
            }
        }
        return sinks
    }
}

private nonisolated enum CommittedMutationSystemProjectionError:
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

/// Projects committed store facts to the Widget, Watch, and Live Activity
/// without making a durable mutation wait for their I/O.
///
/// Requests only mark sinks dirty. One drain task reads the committed store
/// once per pass and publishes to every sink that was dirty when the pass
/// began, so a burst of mutations collapses into one read. A sink whose read
/// or publication fails is retried with the next request; it never blocks its
/// siblings or the command that triggered it.
@MainActor
final class CommittedMutationSystemProjectionScheduler {
    typealias Materialize = @MainActor (
        ModelContainer?
    ) async throws -> CommittedMutationSystemProjectionMaterialization
    typealias Publish = @MainActor (
        CommittedMutationSystemProjectionSink,
        CommittedMutationSystemProjectionMaterialization
    ) async throws -> Void

    private static let logger = Logger(
        subsystem: AppIdentity.loggingSubsystem,
        category: "CommittedMutationProjection"
    )
    private static let widgetWriter = WidgetSnapshotProjectionWriter()

    /// Held weakly so short-lived test and recovery containers can disappear.
    weak var container: ModelContainer?
    private let materialize: Materialize
    private let publish: Publish
    private var dirtySinks: Set<CommittedMutationSystemProjectionSink> = []
    private var failedSinks: Set<CommittedMutationSystemProjectionSink> = []
    private var drainTask: Task<Void, Never>?

    init(
        container: ModelContainer? = nil,
        materialize: @escaping Materialize =
            CommittedMutationSystemProjectionScheduler.materializeCommittedFacts,
        publish: @escaping Publish =
            CommittedMutationSystemProjectionScheduler.publish
    ) {
        self.container = container
        self.materialize = materialize
        self.publish = publish
    }

    func enqueue(
        events: Set<StoreDomainEvent>,
        forcedSinks: Set<CommittedMutationSystemProjectionSink> = []
    ) {
        let sinks = CommittedMutationSystemProjectionSink
            .sinks(showing: events)
            .union(forcedSinks)
        guard sinks.isEmpty == false else { return }
        dirtySinks.formUnion(sinks)
        dirtySinks.formUnion(failedSinks)
        failedSinks.removeAll()
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while dirtySinks.isEmpty == false {
            let sinks = dirtySinks
            dirtySinks.removeAll()
            await PerformanceSignpost.interval("mutation.systemProjections") {
                await project(to: sinks)
            }
        }
        drainTask = nil
    }

    private func project(
        to sinks: Set<CommittedMutationSystemProjectionSink>
    ) async {
        let materialization: CommittedMutationSystemProjectionMaterialization
        do {
            materialization = try await materialize(container)
        } catch {
            failedSinks.formUnion(sinks)
            Self.logger.error(
                "System projection read failed: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        for sink in CommittedMutationSystemProjectionSink.allCases
            where sinks.contains(sink)
        {
            do {
                try await publish(sink, materialization)
            } catch {
                failedSinks.insert(sink)
                Self.logger.error(
                    "System projection publish failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    static func materializeCommittedFacts(
        _ container: ModelContainer?
    ) async throws -> CommittedMutationSystemProjectionMaterialization {
        guard let container else {
            throw CommittedMutationSystemProjectionError.storeContainerReleased
        }
        return try await CommittedMutationSystemSurfaceMaterializer(
            modelContainer: container
        )
        .materialize(now: Date())
    }

    static func publish(
        _ sink: CommittedMutationSystemProjectionSink,
        _ materialization: CommittedMutationSystemProjectionMaterialization
    ) async throws {
        switch sink {
        case .widget:
            // Deliberately bypasses TimeTrackerStore.errorMessage: projection
            // failures never surface as command failures.
            try await widgetWriter.save(materialization.widgetSnapshot)
        case .watch:
            try publishWatch(materialization.watchSnapshot)
        case .liveActivity:
            try await publishLiveActivity(materialization.liveActivity)
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
            throw CommittedMutationSystemProjectionError.watchNotActivated
        case .notReachable:
            // updateApplicationContext never reports this status. Treat it as
            // retryable if a future implementation does.
            throw CommittedMutationSystemProjectionError
                .watchDeliveryFailed("Watch is not reachable.")
        case let .failed(message):
            throw CommittedMutationSystemProjectionError
                .watchDeliveryFailed(message)
        }
        #else
        _ = snapshot
        #endif
    }

    private static func publishLiveActivity(
        _ projection: CommittedMutationLiveActivityProjection
    ) async throws {
        #if os(iOS) && canImport(ActivityKit)
        let coordinator = LiveActivityCoordinator.shared
        coordinator.sync(projection: projection)
        await coordinator.waitUntilIdle()

        switch coordinator.status {
        case .ready, .active:
            return
        case .synchronizing:
            throw CommittedMutationSystemProjectionError.liveActivityDidNotSettle
        case let .unavailable(failure):
            switch failure {
            case .backgroundStart, .capacity, .system:
                throw CommittedMutationSystemProjectionError
                    .liveActivityUnavailable(failure)
            case .unsupported,
                 .denied,
                 .configuration,
                 .payloadTooLarge,
                 .removed:
                // These require a capability, settings, configuration, or
                // explicit user action. Automatic retries would not make
                // progress and could recreate a dismissed activity.
                return
            }
        }
        #else
        _ = projection
        #endif
    }
}

/// One scheduler per physical store, shared by every scene facade and system
/// action that writes to it.
@MainActor
final class CommittedMutationSystemProjectionSchedulerRegistry {
    static let shared = CommittedMutationSystemProjectionSchedulerRegistry()

    private var schedulersByScope: [
        StoreScope: CommittedMutationSystemProjectionScheduler
    ] = [:]

    func scheduler(
        for container: ModelContainer
    ) throws -> CommittedMutationSystemProjectionScheduler {
        schedulersByScope = schedulersByScope.filter {
            $0.value.container != nil
        }
        let scope = try StoreScope(container: container)
        if let scheduler = schedulersByScope[scope] {
            scheduler.container = container
            return scheduler
        }
        let scheduler = CommittedMutationSystemProjectionScheduler(
            container: container
        )
        schedulersByScope[scope] = scheduler
        return scheduler
    }
}
