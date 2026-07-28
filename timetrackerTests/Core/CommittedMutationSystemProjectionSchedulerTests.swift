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
            events: [.fullSync]
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
    func blockedInFlightWorkCompletesBeforePendingReceiptsWithoutReplay() async {
        let probe = ProjectionWorkerProbe(
            blockedAttempts: [.widget: [0, 1]]
        )
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await probe.run(sink: sink, work: work)
        }
        let first = CommittedMutationSystemProjectionReceipt(
            events: [
                .ledgerChanged(
                    taskID: nil,
                    dateInterval: nil,
                    isVisible: true
                ),
            ]
        )
        let secondID = UUID()
        let second = CommittedMutationSystemProjectionReceipt(
            events: [
                .taskChanged(
                    taskID: secondID,
                    affectedAncestorIDs: []
                ),
            ]
        )
        let third = CommittedMutationSystemProjectionReceipt(
            events: [
                .pomodoroChanged(
                    runID: nil,
                    sessionID: nil,
                    taskID: nil
                ),
            ]
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
        #expect(
            widgetCalls[1].receiptIDs ==
                [second.id, third.id]
        )
        #expect(
            widgetCalls[1].events ==
                second.events.union(third.events)
        )
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
            events: [
                .ledgerChanged(
                    taskID: nil,
                    dateInterval: nil,
                    isVisible: true
                ),
            ]
        )
        let second = CommittedMutationSystemProjectionReceipt(
            events: [
                .taskChanged(
                    taskID: nil,
                    affectedAncestorIDs: []
                ),
            ]
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

    @Test @MainActor
    func everyMutationTargetsSyncWhileSystemSurfacesStayDomainScoped() async {
        let probe = ProjectionWorkerProbe()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await probe.run(sink: sink, work: work)
        }
        let syncOnlyEvents: Set<StoreDomainEvent> = [
            .checklistChanged(
                taskID: UUID(),
                affectedAncestorIDs: []
            ),
            .countdownChanged,
            .inboxChanged(itemIDs: [UUID()]),
        ]

        scheduler.enqueue(
            CommittedMutationSystemProjectionReceipt(
                events: syncOnlyEvents
            )
        )
        await scheduler.waitUntilIdle()

        #expect(scheduler.latestGeneration == 1)
        #expect(
            probe.calls(for: .syncSnapshot).map(\.events)
                == [syncOnlyEvents]
        )
        for sink in CommittedMutationSystemProjectionSink.systemSurfaceCases {
            #expect(probe.calls(for: sink).isEmpty)
        }

        let preferenceEvent: Set<StoreDomainEvent> = [
            .preferenceChanged(key: "quickStart"),
        ]
        scheduler.enqueue(
            CommittedMutationSystemProjectionReceipt(
                events: preferenceEvent
            )
        )
        await scheduler.waitUntilIdle()

        #expect(scheduler.latestGeneration == 2)
        #expect(probe.calls(for: .widget).isEmpty)
        #expect(probe.calls(for: .liveActivity).isEmpty)
        #expect(probe.calls(for: .watch).map(\.events) == [preferenceEvent])
        #expect(
            probe.calls(for: .syncSnapshot).map(\.events) == [
                syncOnlyEvents,
                preferenceEvent,
            ]
        )
    }

    @Test @MainActor
    func acknowledgedReceiptDeduplicationIsBounded() async {
        let probe = ProjectionWorkerProbe()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await probe.run(sink: sink, work: work)
        }
        let receipts = (0 ..< 600).map { _ in
            CommittedMutationSystemProjectionReceipt(events: [.fullSync])
        }

        receipts.forEach(scheduler.enqueue)
        await scheduler.waitUntilIdle()

        for sink in CommittedMutationSystemProjectionSink.allCases {
            #expect(scheduler.acknowledgedReceiptCount(for: sink) == 512)
        }

        scheduler.enqueue(receipts[599])
        await scheduler.waitUntilIdle()
        for sink in CommittedMutationSystemProjectionSink.allCases {
            #expect(probe.calls(for: sink).count == 1)
        }
    }

    @Test @MainActor
    func partiallyEvictedReceiptReplayTargetsMissingSyncAndWatchLanes() async {
        let probe = ProjectionWorkerProbe()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await probe.run(sink: sink, work: work)
        }
        let original = CommittedMutationSystemProjectionReceipt(
            events: [.fullSync]
        )
        scheduler.enqueue(original)
        await scheduler.waitUntilIdle()

        let watchOnlyReceipts = (0 ..< 600).map { index in
            CommittedMutationSystemProjectionReceipt(events: [
                .preferenceChanged(key: "watch-\(index)"),
            ])
        }
        watchOnlyReceipts.forEach(scheduler.enqueue)
        await scheduler.waitUntilIdle()

        #expect(scheduler.acknowledgedReceiptCount(for: .watch) == 512)
        #expect(
            scheduler.acknowledgedReceiptCount(
                for: .syncSnapshot
            ) == 512
        )
        #expect(scheduler.acknowledgedReceiptCount(for: .widget) == 1)
        #expect(
            scheduler.acknowledgedReceiptCount(for: .liveActivity) == 1
        )

        scheduler.enqueue(original)
        await scheduler.waitUntilIdle()

        #expect(probe.calls(for: .widget).count == 1)
        #expect(probe.calls(for: .liveActivity).count == 1)
        let watchReplay = probe.calls(for: .watch).last
        #expect(watchReplay?.receiptIDs == [original.id])
        #expect(
            watchReplay?.targetSinks == [
                .syncSnapshot,
                .watch,
            ]
        )
        #expect(watchReplay?.events == [.fullSync])
        let syncReplay = probe.calls(for: .syncSnapshot).last
        #expect(syncReplay?.receiptIDs == [original.id])
        #expect(syncReplay?.targetSinks == [
            .syncSnapshot,
            .watch,
        ])
        #expect(syncReplay?.events == [.fullSync])
    }

    @Test @MainActor
    func oneOversizedReceiptCollapsesAssociatedIdentitiesToFullSync() async {
        let probe = ProjectionWorkerProbe(
            failuresRemaining: [.widget: 1]
        )
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await probe.run(sink: sink, work: work)
        }
        let oversizedEvent = StoreDomainEvent.taskChanged(
            taskID: UUID(),
            affectedAncestorIDs: Set((0 ..< 600).map { _ in UUID() })
        )

        scheduler.enqueue(
            CommittedMutationSystemProjectionReceipt(
                events: [oversizedEvent]
            )
        )
        await scheduler.waitUntilIdle()

        for sink in CommittedMutationSystemProjectionSink.allCases {
            #expect(probe.calls(for: sink).first?.events == [.fullSync])
        }
        #expect(scheduler.pendingEvents(for: .widget) == [.fullSync])
    }

    @Test @MainActor
    func persistentlyFailingSinkKeepsPendingReceiptTrackingBounded() async {
        let probe = ProjectionWorkerProbe(
            failuresRemaining: [.widget: 10000]
        )
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await probe.run(sink: sink, work: work)
        }
        let receipts = (0 ..< 700).map { _ in
            CommittedMutationSystemProjectionReceipt(events: [
                .taskChanged(
                    taskID: UUID(),
                    affectedAncestorIDs: []
                ),
            ])
        }

        receipts.forEach(scheduler.enqueue)
        await scheduler.waitUntilIdle()

        #expect(scheduler.failedSinks == [.widget])
        #expect(scheduler.pendingReceiptCount(for: .widget) > 0)
        #expect(scheduler.pendingReceiptCount(for: .widget) <= 512)
        #expect(scheduler.pendingEvents(for: .widget) == [.fullSync])

        scheduler.retryFailedSinks()
        await scheduler.waitUntilIdle()

        #expect(scheduler.failedSinks == [.widget])
        #expect(scheduler.pendingReceiptCount(for: .widget) > 0)
        #expect(scheduler.pendingReceiptCount(for: .widget) <= 512)
        #expect(scheduler.pendingEvents(for: .widget) == [.fullSync])

        let newestReceipt = CommittedMutationSystemProjectionReceipt(
            events: [
                .taskChanged(
                    taskID: UUID(),
                    affectedAncestorIDs: []
                ),
            ]
        )
        scheduler.enqueue(newestReceipt)
        await scheduler.waitUntilIdle()

        #expect(scheduler.latestGeneration == 701)
        #expect(scheduler.failedSinks == [.widget])
        #expect(scheduler.pendingReceiptCount(for: .widget) > 0)
        #expect(scheduler.pendingReceiptCount(for: .widget) <= 512)
        #expect(scheduler.pendingEvents(for: .widget) == [.fullSync])
        #expect(probe.calls(for: .widget).count == 3)
        #expect(scheduler.acknowledgedReceiptCount(for: .watch) == 512)
        #expect(
            scheduler.acknowledgedReceiptCount(for: .liveActivity) == 512
        )
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
