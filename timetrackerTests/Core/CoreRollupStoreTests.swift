import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreRollupStoreTests {
    @Test @MainActor
    func rollupStoreOwnsForecastStateSeparatelyFromAnalyticsCache() {
        let task = TaskNode(title: "Rollup Task", parentID: nil, deviceID: "test")
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: Date(timeIntervalSince1970: 25_000), titleSnapshot: task.title)
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: session.startedAt,
            endedAt: session.startedAt.addingTimeInterval(900)
        )
        let checklist = [
            ChecklistItem(taskID: task.id, title: "Done", isCompleted: true, sortOrder: 0, deviceID: "test"),
            ChecklistItem(taskID: task.id, title: "Next", isCompleted: false, sortOrder: 1, deviceID: "test")
        ]
        var rollupStore = RollupStore()
        let analyticsStore = AnalyticsStore()

        rollupStore.refresh(tasks: [task], segments: [segment], checklistItems: checklist, now: session.startedAt.addingTimeInterval(1_000))

        #expect(rollupStore.rollup(for: task.id)?.workedSeconds == 900)
        #expect(rollupStore.checklistProgress(for: task.id, checklistItems: checklist).label == "1/2")
        #expect(analyticsStore.cachedSnapshot(for: .today) == nil)
    }

    @Test @MainActor
    func rollupStoreRefreshAffectedRecomputesImpactedBranchAndAncestors() throws {
        let start = Date(timeIntervalSince1970: 30_000)
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let changedChild = TaskNode(title: "Changed Child", parentID: parent.id, deviceID: "test")
        let untouchedChild = TaskNode(title: "Untouched Child", parentID: parent.id, deviceID: "test")
        let changedSession = TimeSession(taskID: changedChild.id, source: .timer, deviceID: "test", startedAt: start)
        let untouchedSession = TimeSession(taskID: untouchedChild.id, source: .timer, deviceID: "test", startedAt: start)
        let changedSegment = TimeSegment(
            sessionID: changedSession.id,
            taskID: changedChild.id,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(600)
        )
        let untouchedSegment = TimeSegment(
            sessionID: untouchedSession.id,
            taskID: untouchedChild.id,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(1_200)
        )
        let initialChecklist = [
            ChecklistItem(taskID: changedChild.id, title: "Done", isCompleted: true, sortOrder: 0, deviceID: "test"),
            ChecklistItem(taskID: changedChild.id, title: "Next", isCompleted: false, sortOrder: 1, deviceID: "test"),
            ChecklistItem(taskID: untouchedChild.id, title: "Done", isCompleted: true, sortOrder: 0, deviceID: "test"),
            ChecklistItem(taskID: untouchedChild.id, title: "Next", isCompleted: false, sortOrder: 1, deviceID: "test")
        ]
        var store = RollupStore()
        store.refresh(
            tasks: [parent, changedChild, untouchedChild],
            segments: [changedSegment, untouchedSegment],
            checklistItems: initialChecklist,
            now: start.addingTimeInterval(2_000)
        )

        let initialUntouched = try #require(store.rollup(for: untouchedChild.id))
        #expect(initialUntouched.workedSeconds == 1_200)
        #expect(store.rollup(for: parent.id)?.remainingSeconds == 1_800)

        let staleIfRecomputedSegment = TimeSegment(
            sessionID: untouchedSession.id,
            taskID: untouchedChild.id,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(7_200)
        )
        let updatedChecklist = initialChecklist + [
            ChecklistItem(taskID: changedChild.id, title: "Later", isCompleted: false, sortOrder: 2, deviceID: "test")
        ]

        store.refreshAffected(
            taskIDs: [changedChild.id],
            tasks: [parent, changedChild, untouchedChild],
            segments: [changedSegment, staleIfRecomputedSegment],
            checklistItems: updatedChecklist,
            now: start.addingTimeInterval(8_000)
        )

        #expect(store.rollup(for: changedChild.id)?.remainingSeconds == 1_200)
        #expect(store.rollup(for: untouchedChild.id) == initialUntouched)
        #expect(store.rollup(for: parent.id)?.remainingSeconds == 2_400)
    }
}
