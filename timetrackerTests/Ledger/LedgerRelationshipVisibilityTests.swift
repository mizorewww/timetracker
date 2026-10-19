import Foundation
import SwiftData
import Testing
@testable import timetracker

/// AD-036: staged CloudKit imports may deliver ledger rows before their task.
/// Those rows stay hidden and become visible once the parent task arrives.
@Suite(.serialized)
@MainActor
struct LedgerRelationshipVisibilityTests {
    @Test
    func ledgerRowsAppearOnceTheirTaskArrives() throws {
        let context = try makeTestContext()
        let store = makeTestStore()
        try store.configureIfNeeded(context: context)

        let taskID = UUID()
        let startedAt = Date().addingTimeInterval(-7200)
        let sibling = ModelContext(context.container)
        let session = TimeSession(
            taskID: taskID,
            source: .timer,
            deviceID: "remote",
            startedAt: startedAt
        )
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .timer,
            deviceID: "remote",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600)
        )
        sibling.insert(session)
        sibling.insert(segment)
        try sibling.save()
        try store.refresh()
        #expect(store.allSegments.contains { $0.id == segment.id } == false)
        #expect(store.sessions.contains { $0.id == session.id } == false)

        let task = TaskNode(title: "Late task", parentID: nil, deviceID: "remote")
        task.id = taskID
        sibling.insert(task)
        try sibling.save()
        // Only the task set changes; the ledger history itself is unchanged.
        store.refreshStoreScopedTimerReadModels(includingTasks: true)

        #expect(store.allSegments.contains { $0.id == segment.id })
        #expect(store.sessions.contains { $0.id == session.id })
    }
}
