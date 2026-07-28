import Foundation

nonisolated enum CommittedMutationSystemProjectionSink:
    CaseIterable,
    Hashable,
    Sendable
{
    case widget
    case watch
    case liveActivity
}

nonisolated struct CommittedMutationSystemProjectionFailure:
    Equatable,
    Sendable
{
    let generation: UInt
    let message: String
}

nonisolated struct CommittedMutationSystemProjectionReceipt:
    Equatable,
    Sendable
{
    let id: UUID
    let events: Set<StoreDomainEvent>

    init(id: UUID = UUID(), events: Set<StoreDomainEvent>) {
        self.id = id
        self.events = events
    }
}

nonisolated struct CommittedMutationSystemProjectionWork:
    Equatable,
    Sendable
{
    let generation: UInt
    let targetSinks: Set<CommittedMutationSystemProjectionSink>
    let receiptIDs: Set<UUID>
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
        var acknowledgedReceiptIDs: Set<UUID> = []
        var acknowledgedReceiptOrder: [UUID] = []
        var receiptGenerationByID: [UUID: UInt] = [:]
        var acknowledgedGeneration: UInt?
        var failure: CommittedMutationSystemProjectionFailure?
    }

    private static let receiptRetentionLimit = 512
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

    var latestGeneration: UInt {
        generation
    }

    var failedSinks: Set<CommittedMutationSystemProjectionSink> {
        Set(states.compactMap { sink, state in
            state.failure == nil ? nil : sink
        })
    }

    func failure(
        for sink: CommittedMutationSystemProjectionSink
    ) -> CommittedMutationSystemProjectionFailure? {
        states[sink]?.failure
    }

    func acknowledgedGeneration(
        for sink: CommittedMutationSystemProjectionSink
    ) -> UInt? {
        states[sink]?.acknowledgedGeneration
    }

    func acknowledgedReceiptCount(
        for sink: CommittedMutationSystemProjectionSink
    ) -> Int {
        states[sink]?.acknowledgedReceiptIDs.count ?? 0
    }

    func pendingReceiptCount(
        for sink: CommittedMutationSystemProjectionSink
    ) -> Int {
        states[sink]?.pending?.receiptIDs.count ?? 0
    }

    func pendingEvents(
        for sink: CommittedMutationSystemProjectionSink
    ) -> Set<StoreDomainEvent> {
        states[sink]?.pending?.events ?? []
    }

    func trackedReceiptCount(
        for sink: CommittedMutationSystemProjectionSink
    ) -> Int {
        states[sink]?.receiptGenerationByID.count ?? 0
    }

    func enqueue(_ receipt: CommittedMutationSystemProjectionReceipt) {
        let targetedEvents = Dictionary(
            uniqueKeysWithValues:
            Self.targetedSinks(for: receipt.events).map { sink in
                let events = Self.events(receipt.events, for: sink)
                return (sink, events)
            }
        )
        let eligibleEvents = targetedEvents.filter { sink, _ in
            contains(receipt.id, in: sink) == false
        }
        guard eligibleEvents.isEmpty == false else {
            return
        }
        generation &+= 1
        let receiptGeneration = generation
        let targetSinks = Set(eligibleEvents.keys)

        for (sink, events) in eligibleEvents {
            guard var state = states[sink] else { continue }

            state.receiptGenerationByID[receipt.id] = receiptGeneration
            state.pending = Self.merging(
                state.pending,
                with: CommittedMutationSystemProjectionWork(
                    generation: receiptGeneration,
                    targetSinks: targetSinks,
                    receiptIDs: [receipt.id],
                    events: events
                )
            )
            Self.trimPendingReceiptTracking(&state)
            // A later committed mutation is also a safe retry trigger. Keep
            // the failed work in the merged batch, then let this sink catch up
            // without repeating siblings that already succeeded.
            state.failure = nil
            states[sink] = state
            startDrainIfNeeded(for: sink)
        }
    }

    static func targetedSinks(
        for events: Set<StoreDomainEvent>
    ) -> Set<CommittedMutationSystemProjectionSink> {
        Set(
            CommittedMutationSystemProjectionSink.allCases.filter {
                Self.events(events, for: $0).isEmpty == false
            }
        )
    }

    private static func events(
        _ events: Set<StoreDomainEvent>,
        for sink: CommittedMutationSystemProjectionSink
    ) -> Set<StoreDomainEvent> {
        StoreDomainEventBatchLimiter.bounded(
            events.filter { event in
                switch event {
                case .taskChanged,
                     .ledgerChanged,
                     .pomodoroChanged,
                     .remoteImportCompleted,
                     .fullSync:
                    true
                case .preferenceChanged:
                    sink == .watch
                case .checklistChanged,
                     .countdownChanged,
                     .inboxChanged:
                    false
                }
            }
        )
    }

    private func contains(
        _ receiptID: UUID,
        in sink: CommittedMutationSystemProjectionSink
    ) -> Bool {
        guard let state = states[sink] else { return false }
        return state.acknowledgedReceiptIDs.contains(receiptID)
            || state.pending?.receiptIDs.contains(receiptID) == true
            || state.inFlight?.receiptIDs.contains(receiptID) == true
    }

    /// Retries only sinks whose previous attempt failed. Successfully
    /// acknowledged siblings retain their receipt deduplication state.
    func retryFailedSinks() {
        let retrySinks = failedSinks
        var retrySinksByGeneration: [
            UInt: Set<CommittedMutationSystemProjectionSink>
        ] = [:]
        for sink in retrySinks {
            if let generation = states[sink]?.pending?.generation {
                retrySinksByGeneration[generation, default: []]
                    .insert(sink)
            }
        }
        for sink in retrySinks {
            guard var state = states[sink] else { continue }
            if let pending = state.pending {
                let generationSinks =
                    retrySinksByGeneration[pending.generation] ?? []
                state.pending = CommittedMutationSystemProjectionWork(
                    generation: pending.generation,
                    targetSinks: generationSinks,
                    receiptIDs: pending.receiptIDs,
                    events: pending.events
                )
            }
            state.failure = nil
            states[sink] = state
            startDrainIfNeeded(for: sink)
        }
    }

    func waitUntilIdle() async {
        while let task = drainTasks.values.first {
            await task.value
        }
    }

    private func startDrainIfNeeded(
        for sink: CommittedMutationSystemProjectionSink
    ) {
        guard drainTasks[sink] == nil,
              let state = states[sink],
              state.failure == nil,
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
                let orderedReceiptIDs = work.receiptIDs.sorted {
                    completedState.receiptGenerationByID[$0, default: 0]
                        < completedState.receiptGenerationByID[$1, default: 0]
                }
                for receiptID in orderedReceiptIDs
                    where completedState.acknowledgedReceiptIDs
                    .insert(receiptID).inserted
                {
                    completedState.acknowledgedReceiptOrder.append(receiptID)
                }
                let overflow = completedState.acknowledgedReceiptOrder.count
                    - Self.receiptRetentionLimit
                if overflow > 0 {
                    let expiredReceiptIDs =
                        completedState.acknowledgedReceiptOrder.prefix(overflow)
                    completedState.acknowledgedReceiptIDs.subtract(
                        expiredReceiptIDs
                    )
                    for receiptID in expiredReceiptIDs {
                        completedState.receiptGenerationByID[receiptID] = nil
                    }
                    completedState.acknowledgedReceiptOrder.removeFirst(
                        overflow
                    )
                }
                completedState.acknowledgedGeneration = max(
                    completedState.acknowledgedGeneration ?? 0,
                    work.generation
                )
                completedState.failure = nil
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
                Self.trimPendingReceiptTracking(&failedState)
                failedState.failure = CommittedMutationSystemProjectionFailure(
                    generation: work.generation,
                    message: error.localizedDescription
                )
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
            receiptIDs: lhs.receiptIDs.union(rhs.receiptIDs),
            events: StoreDomainEventBatchLimiter.bounded(
                lhs.events.union(rhs.events)
            )
        )
    }

    private static func trimPendingReceiptTracking(
        _ state: inout SinkState
    ) {
        guard let pending = state.pending,
              pending.receiptIDs.count > receiptRetentionLimit
        else {
            return
        }

        let orderedReceiptIDs = pending.receiptIDs.sorted { lhs, rhs in
            let lhsGeneration = state.receiptGenerationByID[lhs, default: 0]
            let rhsGeneration = state.receiptGenerationByID[rhs, default: 0]
            if lhsGeneration == rhsGeneration {
                return lhs.uuidString < rhs.uuidString
            }
            return lhsGeneration < rhsGeneration
        }
        let retainedReceiptIDs = Set(
            orderedReceiptIDs.suffix(receiptRetentionLimit)
        )
        let discardedReceiptIDs =
            pending.receiptIDs.subtracting(retainedReceiptIDs)
        state.pending = CommittedMutationSystemProjectionWork(
            generation: pending.generation,
            targetSinks: pending.targetSinks,
            receiptIDs: retainedReceiptIDs,
            // Surface materialization reads the complete current committed
            // state. Collapse an unusually long failure backlog to full sync
            // so associated IDs cannot make the event set grow without bound.
            events: [.fullSync]
        )
        for receiptID in discardedReceiptIDs
            where state.inFlight?.receiptIDs.contains(receiptID) != true
            && state.acknowledgedReceiptIDs.contains(receiptID) == false
        {
            state.receiptGenerationByID[receiptID] = nil
        }
    }
}
