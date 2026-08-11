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
/// This core intentionally owns only in-process scheduling. Durable recovery is
/// a separate boundary because it requires an explicit persistence contract.
@MainActor
final class CommittedMutationSystemProjectionScheduler {
    typealias Worker = @MainActor (
        CommittedMutationSystemProjectionSink,
        CommittedMutationSystemProjectionWork
    ) async throws -> Void

    private struct SinkState {
        var pending: CommittedMutationSystemProjectionWork?
        var inFlight: CommittedMutationSystemProjectionWork?
        var isPausedAfterFailure = false
    }

    private let worker: Worker
    private var generation: UInt = 0
    private var states = Dictionary(
        uniqueKeysWithValues: CommittedMutationSystemProjectionSink.allCases.map {
            ($0, SinkState())
        }
    )
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
            let events = Self.events(
                request.events,
                for: sink
            )
            guard var state = states[sink] else { continue }

            state.pending = Self.merging(
                state.pending,
                with: CommittedMutationSystemProjectionWork(
                    generation: requestGeneration,
                    targetSinks: targetSinks,
                    events: events
                )
            )
            // A later relevant request is a safe retry trigger. Keep the
            // failed work in the merged batch, then let this sink catch up
            // without repeating siblings that already succeeded.
            state.isPausedAfterFailure = false
            states[sink] = state
            startDrainIfNeeded(for: sink)
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

    private func startDrainIfNeeded(
        for sink: CommittedMutationSystemProjectionSink
    ) {
        guard drainTasks[sink] == nil,
              let state = states[sink],
              state.isPausedAfterFailure == false,
              state.pending != nil
        else {
            return
        }

        drainTasks[sink] = Task { @MainActor [weak self] in
            await self?.drain(sink)
        }
    }

    private func drain(_ sink: CommittedMutationSystemProjectionSink) async {
        defer {
            drainTasks[sink] = nil
            startDrainIfNeeded(for: sink)
        }

        while Task.isCancelled == false,
              var state = states[sink],
              let work = state.pending
        {
            state.pending = nil
            state.inFlight = work
            states[sink] = state

            do {
                try await worker(sink, work)
                guard var completedState = states[sink],
                      completedState.inFlight?.generation == work.generation
                else {
                    continue
                }
                completedState.inFlight = nil
                completedState.isPausedAfterFailure = false
                states[sink] = completedState
            } catch {
                guard var failedState = states[sink],
                      failedState.inFlight?.generation == work.generation
                else {
                    continue
                }
                failedState.inFlight = nil
                failedState.pending = Self.merging(
                    work,
                    with: failedState.pending
                )
                failedState.isPausedAfterFailure = true
                states[sink] = failedState
                return
            }
        }
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
