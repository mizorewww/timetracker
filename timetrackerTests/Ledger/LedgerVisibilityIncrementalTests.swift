import Foundation
import SwiftData
import Testing
@testable import timetracker

/// Incremental relationship-visibility updates must leave the published
/// ledger exactly where a freshly configured store would put it.
@Suite(.serialized)
@MainActor
struct LedgerVisibilityIncrementalTests {
    @Test
    func incrementalVisibilityMatchesAFreshStoreAfterEachLedgerChange() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "seed")
        let work = try repository.createTask(title: "Work", parentID: nil)
        let study = try repository.createTask(title: "Study", parentID: nil)
        let sibling = ModelContext(context.container)
        let now = Date()
        for offset in 1 ... 5 {
            insertSegment(
                taskID: offset.isMultiple(of: 2) ? work.id : study.id,
                startedAt: now.addingTimeInterval(Double(-offset) * 86400),
                into: sibling
            )
        }
        try sibling.save()
        let store = makeTestStore()
        try store.configureIfNeeded(context: context)
        try expectMatchesFreshStore(store, container: context.container)

        _ = try store.startTask(#require(store.task(for: work.id)))
        try expectMatchesFreshStore(store, container: context.container)

        try store.stopTimer(taskID: work.id)
        try expectMatchesFreshStore(store, container: context.container)

        // A staged import delivers a segment and session before their task.
        let lateTaskID = UUID()
        insertSegment(taskID: lateTaskID, startedAt: now.addingTimeInterval(-600), into: sibling)
        try sibling.save()
        store.refreshStoreScopedTimerReadModels()
        try expectMatchesFreshStore(store, container: context.container)

        let lateTask = TaskNode(title: "Late", parentID: nil, deviceID: "remote")
        lateTask.id = lateTaskID
        sibling.insert(lateTask)
        try sibling.save()
        store.refreshStoreScopedTimerReadModels(includingTasks: true)
        try expectMatchesFreshStore(store, container: context.container)
        #expect(store.allSegments.contains { $0.taskID == lateTaskID })

        let deleted = try #require(store.allSegments.last)
        try store.commitSegmentDeletion(deleted.id, expectedBaseline: nil)
        try expectMatchesFreshStore(store, container: context.container)
    }

    private func insertSegment(taskID: UUID, startedAt: Date, into context: ModelContext) {
        let session = TimeSession(taskID: taskID, source: .timer, deviceID: "remote", startedAt: startedAt)
        context.insert(session)
        context.insert(TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .timer,
            deviceID: "remote",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(300)
        ))
    }

    private func expectMatchesFreshStore(
        _ store: TimeTrackerStore,
        container: ModelContainer
    ) throws {
        let fresh = makeTestStore()
        try fresh.configureIfNeeded(context: ModelContext(container))
        #expect(store.allSegments.map(\.id) == fresh.allSegments.map(\.id))
        #expect(store.sessions.map(\.id) == fresh.sessions.map(\.id))
        #expect(store.activeSegments.map(\.id) == fresh.activeSegments.map(\.id))
        #expect(store.todaySegments.map(\.id) == fresh.todaySegments.map(\.id))
    }
}
