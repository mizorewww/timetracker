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
        var acknowledgedGeneration: UInt?
        var failure: CommittedMutationSystemProjectionFailure?
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

    func enqueue(_ receipt: CommittedMutationSystemProjectionReceipt) {
        guard receipt.events.isEmpty == false,
              CommittedMutationSystemProjectionSink.allCases.contains(where: {
                  contains(receipt.id, in: $0) == false
              })
        else {
            return
        }
        generation &+= 1
        let receiptGeneration = generation

        for sink in CommittedMutationSystemProjectionSink.allCases {
            guard var state = states[sink],
                  state.acknowledgedReceiptIDs.contains(receipt.id) == false,
                  state.pending?.receiptIDs.contains(receipt.id) != true,
                  state.inFlight?.receiptIDs.contains(receipt.id) != true
            else {
                continue
            }

            state.pending = Self.merging(
                state.pending,
                with: CommittedMutationSystemProjectionWork(
                    generation: receiptGeneration,
                    receiptIDs: [receipt.id],
                    events: receipt.events
                )
            )
            // A later committed mutation is also a safe retry trigger. Keep
            // the failed work in the merged batch, then let this sink catch up
            // without repeating siblings that already succeeded.
            state.failure = nil
            states[sink] = state
            startDrainIfNeeded(for: sink)
        }
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
        for sink in failedSinks {
            guard var state = states[sink] else { continue }
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
                completedState.acknowledgedReceiptIDs.formUnion(
                    work.receiptIDs
                )
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
        return CommittedMutationSystemProjectionWork(
            generation: max(lhs.generation, rhs.generation),
            receiptIDs: lhs.receiptIDs.union(rhs.receiptIDs),
            events: lhs.events.union(rhs.events)
        )
    }
}
