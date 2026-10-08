import Foundation

nonisolated enum CommittedMutationSystemProjectionSink:
    CaseIterable,
    Hashable,
    Sendable
{
    case syncSnapshot
    case widget
    case watch
    case liveActivity

    static let systemSurfaceCases: [Self] = [
        .widget,
        .watch,
        .liveActivity,
    ]
}

nonisolated enum CommittedMutationSystemProjectionCause: Equatable, Sendable {
    case localCommit
    case startupCatchUp
    case surfaceCatchUp

    var recordsSyncSnapshot: Bool {
        self != .surfaceCatchUp
    }
}

nonisolated struct CommittedMutationSystemProjectionRequest:
    Equatable,
    Sendable
{
    let events: Set<StoreDomainEvent>
    let cause: CommittedMutationSystemProjectionCause
    let forcedSystemSinks:
        Set<CommittedMutationSystemProjectionSink>

    init(
        events: Set<StoreDomainEvent>,
        cause: CommittedMutationSystemProjectionCause,
        forcedSystemSinks:
        Set<CommittedMutationSystemProjectionSink> = []
    ) {
        self.events = events
        self.cause = cause
        self.forcedSystemSinks = forcedSystemSinks.intersection(
            CommittedMutationSystemProjectionSink.systemSurfaceCases
        )
    }
}

nonisolated struct CommittedMutationSystemProjectionWork:
    Equatable,
    Sendable
{
    let generation: UInt
    let targetSinks: Set<CommittedMutationSystemProjectionSink>
    let events: Set<StoreDomainEvent>
}

/// Coalesces committed-mutation projection work without making a durable
/// mutation wait for Widget, Watch, or Live Activity I/O.
///
/// This core intentionally owns only in-process scheduling. Each sink keeps at
/// most one coalesced pending generation and one serialized drain task; a
/// failed sink keeps its work queued and retries when the next relevant
/// mutation arrives, never blocking a sibling.
@MainActor
final class CommittedMutationSystemProjectionScheduler {
    typealias Worker = @MainActor (
        CommittedMutationSystemProjectionSink,
        CommittedMutationSystemProjectionWork
    ) async throws -> Void

    private let worker: Worker
    private var generation: UInt = 0
    private var pending: [
        CommittedMutationSystemProjectionSink:
            CommittedMutationSystemProjectionWork
    ] = [:]
    private var drainTasks: [
        CommittedMutationSystemProjectionSink: Task<Void, Never>
    ] = [:]

    init(worker: @escaping Worker) {
        self.worker = worker
    }

    func enqueue(_ request: CommittedMutationSystemProjectionRequest) {
        let eligibleSinks = Self.targetedSinks(for: request)
        guard eligibleSinks.isEmpty == false else {
            return
        }
        generation &+= 1
        let requestGeneration = generation
        let targetSinks = Set(eligibleSinks)

        for sink in eligibleSinks {
            pending[sink] = Self.merging(
                pending[sink],
                with: CommittedMutationSystemProjectionWork(
                    generation: requestGeneration,
                    targetSinks: targetSinks,
                    events: Self.events(request.events, for: sink)
                )
            )
            startDrain(for: sink)
        }
    }

    static func targetedSinks(
        for request: CommittedMutationSystemProjectionRequest
    ) -> Set<CommittedMutationSystemProjectionSink> {
        var sinks = Set(
            CommittedMutationSystemProjectionSink.systemSurfaceCases.filter {
                Self.events(request.events, for: $0).isEmpty == false
            }
        )
        if request.cause.recordsSyncSnapshot,
           request.events.isEmpty == false
        {
            sinks.insert(.syncSnapshot)
        }
        sinks.formUnion(request.forcedSystemSinks)
        return sinks
    }

    private static func events(
        _ events: Set<StoreDomainEvent>,
        for sink: CommittedMutationSystemProjectionSink
    ) -> Set<StoreDomainEvent> {
        StoreDomainEventBatchLimiter.bounded(
            events.filter { event in
                switch sink {
                case .syncSnapshot:
                    true
                case .widget, .liveActivity:
                    switch event {
                    case .taskChanged,
                         .ledgerChanged,
                         .pomodoroChanged,
                         .remoteImportCompleted,
                         .fullSync:
                        true
                    case .preferenceChanged,
                         .checklistChanged,
                         .countdownChanged,
                         .inboxChanged:
                        false
                    }
                case .watch:
                    switch event {
                    case .taskChanged,
                         .ledgerChanged,
                         .pomodoroChanged,
                         .preferenceChanged,
                         .remoteImportCompleted,
                         .fullSync:
                        true
                    case .checklistChanged,
                         .countdownChanged,
                         .inboxChanged:
                        false
                    }
                }
            }
        )
    }

    private func startDrain(
        for sink: CommittedMutationSystemProjectionSink
    ) {
        guard drainTasks[sink] == nil, pending[sink] != nil else {
            return
        }
        drainTasks[sink] = Task { @MainActor [weak self] in
            await self?.drain(sink)
        }
    }

    private func drain(_ sink: CommittedMutationSystemProjectionSink) async {
        while Task.isCancelled == false, let work = pending[sink] {
            pending[sink] = nil
            do {
                try await worker(sink, work)
            } catch {
                // Keep the failed work queued; the next relevant mutation
                // restarts this sink without touching its siblings.
                pending[sink] = Self.merging(work, with: pending[sink])
                break
            }
        }
        drainTasks[sink] = nil
    }

    private static func merging(
        _ lhs: CommittedMutationSystemProjectionWork?,
        with rhs: CommittedMutationSystemProjectionWork?
    ) -> CommittedMutationSystemProjectionWork? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        let targetSinks: Set<CommittedMutationSystemProjectionSink> = if lhs.generation == rhs.generation {
            lhs.targetSinks.union(rhs.targetSinks)
        } else if lhs.generation > rhs.generation {
            lhs.targetSinks
        } else {
            rhs.targetSinks
        }
        return CommittedMutationSystemProjectionWork(
            generation: max(lhs.generation, rhs.generation),
            targetSinks: targetSinks,
            events: StoreDomainEventBatchLimiter.bounded(
                lhs.events.union(rhs.events)
            )
        )
    }
}
