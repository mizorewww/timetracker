import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct SystemActionPostCommitEffectsTests {
    @Test @MainActor
    func returnsAfterBroadcastAndEnqueueWhileEveryProjectionLaneIsBlocked()
        async throws
    {
        await StoreMutationBroadcaster.waitUntilIdle()
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        ).createTask(
            title: "External timer",
            parentID: nil,
            colorHex: "#0A84FF",
            iconName: "timer"
        )
        let gate = BlockingSystemActionProjectionWorker()
        let scheduler = CommittedMutationSystemProjectionScheduler {
            sink,
            work in
            try await gate.run(sink: sink, work: work)
        }
        defer { gate.releaseAll() }
        var scheduledContainerID: ObjectIdentifier?
        let effects = SystemActionPostCommitEffects(
            schedulerProvider: { container in
                scheduledContainerID = ObjectIdentifier(container)
                return scheduler
            }
        )
        let outcome = try makeTestSystemActionCommandHandler()
            .startTimerMutation(
                taskID: task.id,
                source: .shortcut,
                container: context.container
            )
        let segmentID = try #require(outcome.subjectSegmentID)

        effects.apply(
            container: context.container,
            events: outcome.events
        )

        #expect(
            scheduledContainerID == ObjectIdentifier(context.container)
        )
        #expect(
            StoreMutationBroadcaster.pendingBroadcastEvents ==
                outcome.events
        )
        #expect(
            try SwiftDataTimeTrackingRepository(
                context: ModelContext(context.container)
            ).activeSegments().map(\.id) == [segmentID]
        )

        for sink in CommittedMutationSystemProjectionSink.allCases {
            await gate.waitUntilBlocked(sink)
            #expect(gate.calls(for: sink).count == 1)
            #expect(gate.calls(for: sink).first?.events == outcome.events)
        }

        gate.releaseAll()
        await scheduler.waitUntilIdle()
        await StoreMutationBroadcaster.waitUntilIdle()
    }

    @Test @MainActor
    func enqueueFailureKeepsCommittedMutationAndBroadcastsExactEvents()
        async throws
    {
        await StoreMutationBroadcaster.waitUntilIdle()
        let context = try makeTestContext()
        let outcome = try makeTestSystemActionCommandHandler().addInboxItem(
            title: "Committed before projection scheduling",
            container: context.container,
            deviceID: "test"
        )
        let itemID = try #require(outcome.affectedItemIDs.first)
        let effects = SystemActionPostCommitEffects(
            schedulerProvider: { _ in
                throw ExpectedSystemActionProjectionSchedulingError()
            }
        )

        effects.apply(
            container: context.container,
            events: outcome.events
        )

        #expect(
            StoreMutationBroadcaster.pendingBroadcastEvents ==
                outcome.events
        )
        let persistedItems = try ModelContext(context.container)
            .fetch(FetchDescriptor<InboxItem>())
        #expect(
            persistedItems.contains {
                $0.id == itemID && $0.deletedAt == nil
            }
        )
        await StoreMutationBroadcaster.waitUntilIdle()
    }
}

@MainActor
private final class BlockingSystemActionProjectionWorker {
    private var recorded: [
        CommittedMutationSystemProjectionSink:
            [CommittedMutationSystemProjectionWork]
    ] = [:]
    private var entryWaiters: [
        CommittedMutationSystemProjectionSink:
            [CheckedContinuation<Void, Never>]
    ] = [:]
    private var releaseContinuations: [
        CommittedMutationSystemProjectionSink:
            CheckedContinuation<Void, Never>
    ] = [:]

    func run(
        sink: CommittedMutationSystemProjectionSink,
        work: CommittedMutationSystemProjectionWork
    ) async throws {
        recorded[sink, default: []].append(work)
        await withCheckedContinuation { continuation in
            releaseContinuations[sink] = continuation
            entryWaiters.removeValue(forKey: sink)?.forEach {
                $0.resume()
            }
        }
    }

    func waitUntilBlocked(
        _ sink: CommittedMutationSystemProjectionSink
    ) async {
        guard releaseContinuations[sink] == nil else { return }
        await withCheckedContinuation { continuation in
            entryWaiters[sink, default: []].append(continuation)
        }
    }

    func calls(
        for sink: CommittedMutationSystemProjectionSink
    ) -> [CommittedMutationSystemProjectionWork] {
        recorded[sink, default: []]
    }

    func releaseAll() {
        let continuations = Array(releaseContinuations.values)
        releaseContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private struct ExpectedSystemActionProjectionSchedulingError: Error {}
