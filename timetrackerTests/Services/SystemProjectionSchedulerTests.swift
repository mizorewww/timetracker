import Foundation
import Testing
@testable import timetracker

@MainActor
struct SystemProjectionSchedulerTests {
    @Test
    func eventsTargetOnlyTheSurfacesThatShowThem() {
        let allSinks = Set(CommittedMutationSystemProjectionSink.allCases)

        #expect(CommittedMutationSystemProjectionSink.sinks(
            showing: [.taskChanged(taskID: nil, affectedAncestorIDs: [])]
        ) == allSinks)
        #expect(CommittedMutationSystemProjectionSink.sinks(
            showing: [.remoteImportCompleted]
        ) == allSinks)
        #expect(CommittedMutationSystemProjectionSink.sinks(
            showing: [.fullSync]
        ) == allSinks)
        #expect(CommittedMutationSystemProjectionSink.sinks(
            showing: [.preferenceChanged(key: nil)]
        ) == [.watch])
        #expect(CommittedMutationSystemProjectionSink.sinks(
            showing: [.checklistChanged(taskID: nil, affectedAncestorIDs: [])]
        ).isEmpty)
    }

    @Test
    func burstOfRequestsSharesOneMaterializationAcrossSinks() async {
        var materializationCount = 0
        var published: [CommittedMutationSystemProjectionSink] = []
        let scheduler = CommittedMutationSystemProjectionScheduler(
            materialize: { _ in
                materializationCount += 1
                return Self.materialization()
            },
            publish: { sink, _ in
                published.append(sink)
            }
        )

        scheduler.enqueue(events: [.preferenceChanged(key: nil)])
        scheduler.enqueue(events: [.ledgerChanged(taskID: nil, dateInterval: nil, isVisible: true)])
        scheduler.enqueue(events: [], forcedSinks: [.watch])

        #expect(await eventually { published.count == 3 })
        #expect(materializationCount == 1)
        #expect(Set(published) == Set(CommittedMutationSystemProjectionSink.allCases))
    }

    @Test
    func forcedSinkProjectsWithoutEvents() async {
        var published: [CommittedMutationSystemProjectionSink] = []
        let scheduler = CommittedMutationSystemProjectionScheduler(
            materialize: { _ in Self.materialization() },
            publish: { sink, _ in published.append(sink) }
        )

        scheduler.enqueue(events: [.inboxChanged(itemIDs: [])])
        scheduler.enqueue(events: [], forcedSinks: [.watch])

        #expect(await eventually { published == [.watch] })
    }

    @Test
    func failedSinkRetriesWithTheNextRequest() async {
        var attempts: [CommittedMutationSystemProjectionSink: Int] = [:]
        let scheduler = CommittedMutationSystemProjectionScheduler(
            materialize: { _ in Self.materialization() },
            publish: { sink, _ in
                attempts[sink, default: 0] += 1
                if sink == .widget, attempts[sink] == 1 {
                    throw ExpectedFailure.once
                }
            }
        )

        scheduler.enqueue(events: [.taskChanged(taskID: nil, affectedAncestorIDs: [])])
        #expect(await eventually {
            CommittedMutationSystemProjectionSink.allCases.allSatisfy {
                attempts[$0] == 1
            }
        })

        scheduler.enqueue(events: [.preferenceChanged(key: nil)])
        #expect(await eventually {
            attempts[.widget] == 2 && attempts[.watch] == 2
        })
        #expect(attempts[.liveActivity] == 1)
    }

    @Test
    func failedReadRetriesEverySinkWithTheNextRequest() async {
        var materializationCount = 0
        var published: Set<CommittedMutationSystemProjectionSink> = []
        let scheduler = CommittedMutationSystemProjectionScheduler(
            materialize: { _ in
                materializationCount += 1
                if materializationCount == 1 {
                    throw ExpectedFailure.once
                }
                return Self.materialization()
            },
            publish: { sink, _ in published.insert(sink) }
        )

        scheduler.enqueue(events: [.fullSync])
        #expect(await eventually { materializationCount == 1 })
        #expect(published.isEmpty)

        scheduler.enqueue(events: [.preferenceChanged(key: nil)])
        #expect(await eventually {
            published == Set(CommittedMutationSystemProjectionSink.allCases)
        })
    }

    private static func materialization()
        -> CommittedMutationSystemProjectionMaterialization
    {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        return CommittedMutationSystemProjectionMaterialization(
            widgetSnapshot: WidgetSnapshot(
                generatedAt: now,
                todayGrossSeconds: 0,
                todayWallSeconds: 0,
                activeTimers: []
            ),
            watchSnapshot: WatchStateSnapshot(
                generatedAt: now,
                todayGrossSeconds: 0,
                todayWallSeconds: 0,
                activeTimers: [],
                recentTasks: []
            ),
            liveActivity: .inactive,
            generatedAt: now
        )
    }

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
