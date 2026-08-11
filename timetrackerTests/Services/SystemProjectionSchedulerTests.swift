import Testing
@testable import timetracker

struct SystemProjectionSchedulerTests {
    @Test
    @MainActor
    func requestCauseSeparatesLocalSnapshotRecordingFromSurfaceCatchUp() {
        let allSinks = Set(CommittedMutationSystemProjectionSink.allCases)
        let systemSurfaces = Set(
            CommittedMutationSystemProjectionSink.systemSurfaceCases
        )

        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: .init(
                events: [.taskChanged(taskID: nil, affectedAncestorIDs: [])],
                cause: .localCommit
            )
        ) == allSinks)
        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: .init(
                events: [.remoteImportCompleted],
                cause: .surfaceCatchUp
            )
        ) == systemSurfaces)
        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: .init(
                events: [.fullSync],
                cause: .startupCatchUp
            )
        ) == allSinks)
        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: .init(
                events: [.preferenceChanged(key: nil)],
                cause: .surfaceCatchUp
            )
        ) == [.watch])
        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: .init(
                events: [.preferenceChanged(key: nil)],
                cause: .localCommit
            )
        ) == [.syncSnapshot, .watch])
        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: .init(
                events: [.checklistChanged(taskID: nil, affectedAncestorIDs: [])],
                cause: .surfaceCatchUp
            )
        ).isEmpty)
        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: .init(
                events: [],
                cause: .surfaceCatchUp,
                forcedSystemSinks: [.watch]
            )
        ) == [.watch])
    }

    @Test
    @MainActor
    func oneGenerationSharesOneSystemSurfaceMaterialization() async throws {
        var materializationCount = 0
        let worker = CommittedMutationSystemProjectionWorker(
            materializer: { _ in
                materializationCount += 1
                return nil
            },
            publisher: { _, _ in
                Issue.record("A nil materialization must not publish")
            }
        )
        let targetSinks = Set(
            CommittedMutationSystemProjectionSink.systemSurfaceCases
        )
        let work = CommittedMutationSystemProjectionWork(
            generation: 1,
            targetSinks: targetSinks,
            events: [.fullSync]
        )

        for sink in CommittedMutationSystemProjectionSink.systemSurfaceCases {
            try await worker.perform(sink: sink, work: work)
        }

        #expect(materializationCount == 1)
    }

    @Test
    @MainActor
    func syncSnapshotUsesExactEventsWithoutMaterializingSurfaces() async throws {
        let events: Set<StoreDomainEvent> = [
            .checklistChanged(taskID: nil, affectedAncestorIDs: []),
        ]
        var recordedEvents: Set<StoreDomainEvent> = []
        var materializationCount = 0
        let worker = CommittedMutationSystemProjectionWorker(
            syncRecorder: { recordedEvents = $0 },
            materializer: { _ in
                materializationCount += 1
                return nil
            },
            publisher: { _, _ in }
        )
        let work = CommittedMutationSystemProjectionWork(
            generation: 1,
            targetSinks: [.syncSnapshot],
            events: events
        )

        try await worker.perform(sink: .syncSnapshot, work: work)

        #expect(recordedEvents == events)
        #expect(materializationCount == 0)
    }

    @Test
    @MainActor
    func failedSinkRetriesOnTheNextRelevantGeneration() async {
        var attempts: [CommittedMutationSystemProjectionSink: Int] = [:]
        let scheduler = CommittedMutationSystemProjectionScheduler { sink, _ in
            attempts[sink, default: 0] += 1
            if sink == .widget, attempts[sink] == 1 {
                throw ExpectedFailure.once
            }
        }
        let request = CommittedMutationSystemProjectionRequest(
            events: [.taskChanged(taskID: nil, affectedAncestorIDs: [])],
            cause: .localCommit
        )

        scheduler.enqueue(request)
        #expect(await eventually {
            attempts[.syncSnapshot] == 1 &&
                attempts[.widget] == 1 &&
                attempts[.watch] == 1 &&
                attempts[.liveActivity] == 1
        })

        scheduler.enqueue(request)
        #expect(await eventually {
            CommittedMutationSystemProjectionSink.allCases.allSatisfy {
                attempts[$0] == 2
            }
        })
    }

    @MainActor
    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0 ..< 100 where condition() == false {
            await Task.yield()
        }
        return condition()
    }

    private enum ExpectedFailure: Error {
        case once
    }
}
