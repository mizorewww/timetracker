import Foundation
import SwiftData
import Testing
@testable import timetracker

/// Subtree-active-timer index contracts.
///
/// `taskIDsWithActiveTimerInSubtree` is cached per (task, ledger) revision.
/// These tests assert the observable semantics the cache must preserve:
/// ancestors of a task with a running timer report true, unrelated tasks
/// false, and stopping the timer (a ledger write) is reflected on the next
/// read without stale cache hits.
@Suite(.serialized)
@MainActor
struct TaskActiveTimerIndexTests {
    private func makeStoreWithHierarchy() throws -> (
        TimeTrackerStore,
        TaskNode,
        TaskNode
    ) {
        let context = try makeTestContext()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        )
        let parent = try repository.createTask(
            title: "Parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try repository.createTask(
            title: "Child",
            parentID: parent.id,
            colorHex: nil,
            iconName: nil
        )
        return (store, parent, child)
    }

    @Test
    func ancestorsOfRunningTaskReportTrueAndUnrelatedFalse() throws {
        let (store, parent, child) = try makeStoreWithHierarchy()
        let other = try SwiftDataTaskRepository(
            context: store.modelContext!.container.mainContext,
            deviceID: "seed"
        ).createTask(
            title: "Other",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )

        #expect(store.startTask(child))

        #expect(store.hasActiveTimer(inTaskSubtree: child.id))
        #expect(store.hasActiveTimer(inTaskSubtree: parent.id))
        #expect(store.hasActiveTimer(inTaskSubtree: other.id) == false)
    }

    @Test
    func stoppingTheTimerInvalidatesTheIndex() throws {
        let (store, parent, child) = try makeStoreWithHierarchy()
        #expect(store.startTask(child))
        #expect(store.hasActiveTimer(inTaskSubtree: parent.id))

        guard let active = store.activeSegment(for: child.id) else {
            Issue.record("Expected an active segment")
            return
        }
        #expect(store.stop(segment: active))

        #expect(store.hasActiveTimer(inTaskSubtree: child.id) == false)
        #expect(store.hasActiveTimer(inTaskSubtree: parent.id) == false)
    }
}
