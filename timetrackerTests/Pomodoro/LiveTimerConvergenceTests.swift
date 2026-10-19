import Foundation
import SwiftData
import Testing
@testable import timetracker

/// The Pomodoro page-appear path converges live timer read models without
/// running the full refresh pipeline. A segment closed by another process
/// must still reach rollups through that path.
@Suite(.serialized)
@MainActor
struct LiveTimerConvergenceTests {
    @Test
    func segmentClosedElsewhereReachesRollupsThroughLiveConvergence() throws {
        let context = try makeTestContext()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: "Remote work",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )

        let startedAt = Date().addingTimeInterval(-3600)
        let sibling = ModelContext(context.container)
        let session = TimeSession(
            taskID: task.id,
            source: .timer,
            deviceID: "remote",
            startedAt: startedAt,
            titleSnapshot: task.title
        )
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "remote",
            startedAt: startedAt
        )
        sibling.insert(session)
        sibling.insert(segment)
        try sibling.save()
        try store.refresh()
        #expect(store.activeSegment(for: task.id) != nil)

        // Another process closes the segment without notifying this scene.
        segment.endedAt = startedAt.addingTimeInterval(1800)
        segment.updatedAt = Date()
        try sibling.save()

        #expect(store.reconcileActivePomodoro() == false)
        #expect(store.activeSegment(for: task.id) == nil)
        #expect(store.rollup(for: task.id)?.workedSeconds == 1800)

        // A later visible-ledger refresh must not discard the change either.
        store.refreshStoreScopedTimerReadModels()
        #expect(store.rollup(for: task.id)?.workedSeconds == 1800)
    }
}
