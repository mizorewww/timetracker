import Testing
@testable import timetracker

struct SystemProjectionSchedulerTests {
    @Test
    @MainActor
    func eventsTargetOnlyTheSurfacesThatShowThem() {
        let allSinks = Set(CommittedMutationSystemProjectionSink.allCases)

        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: .init(
                events: [.taskChanged(taskID: nil, affectedAncestorIDs: [])]
            )
        ) == allSinks)
        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: .init(
                events: [.remoteImportCompleted]
            )
        ) == allSinks)
        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: .init(
                events: [.fullSync]
            )
        ) == allSinks)
        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: .init(
                events: [.preferenceChanged(key: nil)]
            )
        ) == [.watch])
        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: .init(
                events: [.checklistChanged(taskID: nil, affectedAncestorIDs: [])]
            )
        ).isEmpty)
        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: .init(
                events: [],
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
    func failedSinkRetriesOnTheNextRelevantGeneration() async {
        var attempts: [CommittedMutationSystemProjectionSink: Int] = [:]
        let scheduler = CommittedMutationSystemProjectionScheduler { sink, _ in
            attempts[sink, default: 0] += 1
            if sink == .widget, attempts[sink] == 1 {
                throw ExpectedFailure.once
            }
        }
        let request = CommittedMutationSystemProjectionRequest(
            events: [.taskChanged(taskID: nil, affectedAncestorIDs: [])]
        )

        scheduler.enqueue(request)
        #expect(await eventually {
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
