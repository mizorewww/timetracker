import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CommittedMutationSystemProjectionSchedulerTests {
    @Test @MainActor
    func identicalReceiptRunsEachSinkOnce() async {
        let probe = ProjectionWorkerProbe()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await probe.run(sink: sink, work: work)
        }
        let receipt = CommittedMutationSystemProjectionReceipt(
            events: [.countdownChanged]
        )

        scheduler.enqueue(receipt)
        await scheduler.waitUntilIdle()
        scheduler.enqueue(receipt)
        await scheduler.waitUntilIdle()

        for sink in CommittedMutationSystemProjectionSink.allCases {
            #expect(probe.calls(for: sink).count == 1)
            #expect(probe.calls(for: sink).first?.receiptIDs == [receipt.id])
        }
        #expect(scheduler.latestGeneration == 1)
    }

    @Test @MainActor
    func pendingReceiptsMergeAndOldCompletionCannotAcknowledgeNewGeneration() async {
        let probe = ProjectionWorkerProbe(
            blockedAttempts: [.widget: [0, 1]]
        )
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await probe.run(sink: sink, work: work)
        }
        let first = CommittedMutationSystemProjectionReceipt(
            events: [.countdownChanged]
        )
        let secondID = UUID()
        let second = CommittedMutationSystemProjectionReceipt(
            events: [.inboxChanged(itemIDs: [secondID])]
        )
        let third = CommittedMutationSystemProjectionReceipt(
            events: [.preferenceChanged(key: "appearance")]
        )

        scheduler.enqueue(first)
        await probe.waitForCall(sink: .widget, attempt: 0)
        scheduler.enqueue(second)
        scheduler.enqueue(third)

        #expect(scheduler.acknowledgedGeneration(for: .widget) == nil)
        probe.release(sink: .widget, attempt: 0)
        await probe.waitForCall(sink: .widget, attempt: 1)

        let widgetCalls = probe.calls(for: .widget)
        #expect(widgetCalls.count == 2)
        #expect(widgetCalls[0].generation == 1)
        #expect(widgetCalls[0].receiptIDs == [first.id])
        #expect(widgetCalls[1].generation == 3)
        #expect(widgetCalls[1].receiptIDs == [second.id, third.id])
        #expect(widgetCalls[1].events == second.events.union(third.events))
        #expect(scheduler.acknowledgedGeneration(for: .widget) == 1)

        probe.release(sink: .widget, attempt: 1)
        await scheduler.waitUntilIdle()
        #expect(scheduler.acknowledgedGeneration(for: .widget) == 3)
    }

    @Test @MainActor
    func sinkFailureDoesNotBlockSiblingsAndRetryRunsOnlyFailedSink() async {
        let probe = ProjectionWorkerProbe(
            failuresRemaining: [.widget: 1]
        )
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await probe.run(sink: sink, work: work)
        }
        let receipt = CommittedMutationSystemProjectionReceipt(
            events: [.fullSync]
        )

        scheduler.enqueue(receipt)
        await scheduler.waitUntilIdle()

        #expect(scheduler.failedSinks == [.widget])
        #expect(scheduler.failure(for: .widget)?.generation == 1)
        #expect(scheduler.acknowledgedGeneration(for: .widget) == nil)
        #expect(scheduler.acknowledgedGeneration(for: .watch) == 1)
        #expect(scheduler.acknowledgedGeneration(for: .liveActivity) == 1)
        #expect(probe.calls(for: .widget).count == 1)
        #expect(probe.calls(for: .watch).count == 1)
        #expect(probe.calls(for: .liveActivity).count == 1)

        scheduler.retryFailedSinks()
        await scheduler.waitUntilIdle()

        #expect(scheduler.failedSinks.isEmpty)
        #expect(scheduler.acknowledgedGeneration(for: .widget) == 1)
        #expect(probe.calls(for: .widget).count == 2)
        #expect(probe.calls(for: .watch).count == 1)
        #expect(probe.calls(for: .liveActivity).count == 1)
    }

    @Test @MainActor
    func laterReceiptRetriesFailedWorkWithoutRepeatingAcknowledgedEvents() async {
        let probe = ProjectionWorkerProbe(
            failuresRemaining: [.widget: 1]
        )
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await probe.run(sink: sink, work: work)
        }
        let first = CommittedMutationSystemProjectionReceipt(
            events: [.countdownChanged]
        )
        let second = CommittedMutationSystemProjectionReceipt(
            events: [.preferenceChanged(key: "quickStart")]
        )

        scheduler.enqueue(first)
        await scheduler.waitUntilIdle()
        scheduler.enqueue(second)
        await scheduler.waitUntilIdle()

        let widgetCalls = probe.calls(for: .widget)
        let watchCalls = probe.calls(for: .watch)
        #expect(widgetCalls.count == 2)
        #expect(widgetCalls[1].receiptIDs == [first.id, second.id])
        #expect(widgetCalls[1].events == first.events.union(second.events))
        #expect(watchCalls.count == 2)
        #expect(watchCalls[1].receiptIDs == [second.id])
        #expect(watchCalls[1].events == second.events)
        #expect(scheduler.failedSinks.isEmpty)
    }
}

@MainActor
private final class ProjectionWorkerProbe {
    private struct AttemptKey: Hashable {
        let sink: CommittedMutationSystemProjectionSink
        let attempt: Int
    }

    private var recorded: [
        CommittedMutationSystemProjectionSink:
            [CommittedMutationSystemProjectionWork]
    ] = [:]
    private var blockedAttempts: [
        CommittedMutationSystemProjectionSink: Set<Int>
    ]
    private var failuresRemaining: [
        CommittedMutationSystemProjectionSink: Int
    ]
    private var entryWaiters: [
        AttemptKey: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var releaseContinuations: [
        AttemptKey: CheckedContinuation<Void, Never>
    ] = [:]

    init(
        blockedAttempts: [CommittedMutationSystemProjectionSink: Set<Int>] = [:],
        failuresRemaining: [CommittedMutationSystemProjectionSink: Int] = [:]
    ) {
        self.blockedAttempts = blockedAttempts
        self.failuresRemaining = failuresRemaining
    }

    func run(
        sink: CommittedMutationSystemProjectionSink,
        work: CommittedMutationSystemProjectionWork
    ) async throws {
        let attempt = recorded[sink, default: []].count
        recorded[sink, default: []].append(work)
        let key = AttemptKey(sink: sink, attempt: attempt)

        if blockedAttempts[sink]?.contains(attempt) == true {
            await withCheckedContinuation { continuation in
                releaseContinuations[key] = continuation
                resumeEntryWaiters(for: key)
            }
        } else {
            resumeEntryWaiters(for: key)
        }

        if let remaining = failuresRemaining[sink], remaining > 0 {
            failuresRemaining[sink] = remaining - 1
            throw ProjectionWorkerProbeError.expectedFailure
        }
    }

    func calls(
        for sink: CommittedMutationSystemProjectionSink
    ) -> [CommittedMutationSystemProjectionWork] {
        recorded[sink, default: []]
    }

    func waitForCall(
        sink: CommittedMutationSystemProjectionSink,
        attempt: Int
    ) async {
        if recorded[sink, default: []].indices.contains(attempt) {
            return
        }
        let key = AttemptKey(sink: sink, attempt: attempt)
        await withCheckedContinuation { continuation in
            entryWaiters[key, default: []].append(continuation)
        }
    }

    func release(
        sink: CommittedMutationSystemProjectionSink,
        attempt: Int
    ) {
        let key = AttemptKey(sink: sink, attempt: attempt)
        releaseContinuations.removeValue(forKey: key)?.resume()
    }

    private func resumeEntryWaiters(for key: AttemptKey) {
        entryWaiters.removeValue(forKey: key)?.forEach { $0.resume() }
    }
}

private enum ProjectionWorkerProbeError: Error {
    case expectedFailure
}
