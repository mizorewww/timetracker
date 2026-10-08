import Foundation
import Testing
@testable import timetracker

struct TaskRollupServiceTests {
    private let now = Date(timeIntervalSinceReferenceDate: 2_000_000)

    @Test
    func explicitChildForecastRollsIntoItsParent() throws {
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let child = TaskNode(title: "Child", parentID: parent.id, deviceID: "test")
        child.estimatedSeconds = 120
        let segment = TimeSegment(
            sessionID: UUID(),
            taskID: child.id,
            source: .manual,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-20),
            endedAt: now
        )

        var store = RollupStore()
        store.refresh(
            tasks: [parent, child],
            segments: [segment],
            checklistItems: [],
            now: now
        )
        let childRollup = try #require(store.rollup(for: child.id))
        let parentRollup = try #require(store.rollup(for: parent.id))

        #expect(childRollup.workedSeconds == 20)
        #expect(childRollup.remainingSeconds == 100)
        #expect(parentRollup.workedSeconds == 20)
        #expect(parentRollup.remainingSeconds == 100)
        #expect(parentRollup.estimatedTotalSeconds == 120)
        #expect(parentRollup.forecastState == .aggregate)
        #expect(parentRollup.forecastSourceTaskIDs == [child.id])
    }

    @Test
    func completedChecklistProducesACompletedZeroRemainingForecast() throws {
        let task = TaskNode(title: "Done", parentID: nil, deviceID: "test")
        let items = [
            ChecklistItem(taskID: task.id, title: "One", isCompleted: true, deviceID: "test"),
            ChecklistItem(taskID: task.id, title: "Two", isCompleted: true, deviceID: "test"),
        ]

        var store = RollupStore()
        store.refresh(
            tasks: [task],
            segments: [],
            checklistItems: items,
            now: now
        )
        let rollup = try #require(store.rollup(for: task.id))

        #expect(rollup.checklistProgress == ChecklistProgress(taskID: task.id, totalCount: 2, completedCount: 2))
        #expect(rollup.remainingSeconds == 0)
        #expect(rollup.estimatedTotalSeconds == 0)
        #expect(rollup.forecastState == .completed)
        #expect(rollup.completionFraction == 1)
    }

    @Test
    func forecastEligibilityDisablesAnOtherwiseReadyTask() throws {
        let task = TaskNode(title: "Excluded", parentID: nil, deviceID: "test")
        task.estimatedSeconds = 600

        var store = RollupStore()
        store.refresh(
            tasks: [task],
            segments: [],
            checklistItems: [],
            forecastEligibleTaskIDs: [],
            now: now
        )
        let rollup = try #require(store.rollup(for: task.id))

        #expect(rollup.forecastState == .disabled)
        #expect(rollup.estimatedTotalSeconds == nil)
        #expect(rollup.remainingSeconds == nil)
        #expect(rollup.forecastSourceTaskIDs.isEmpty)
    }

    @Test
    func incrementalRollupRebuildsAncestorsAndPreservesUnrelatedValues() {
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let child = TaskNode(title: "Child", parentID: parent.id, deviceID: "test")
        let unrelated = TaskNode(title: "Unrelated", parentID: nil, deviceID: "test")
        child.estimatedSeconds = 100
        unrelated.estimatedSeconds = 300

        var store = RollupStore()
        store.refresh(
            tasks: [parent, child, unrelated],
            segments: [],
            checklistItems: [],
            now: now
        )
        let initial = store.taskRollups

        child.estimatedSeconds = 200
        store.refreshAffected(
            directTaskIDs: [child.id],
            explicitAncestorTaskIDs: [],
            segmentChanges: [],
            checklistItemsByTaskID: [:],
            now: now
        )
        let updated = store.taskRollups

        #expect(updated[child.id]?.remainingSeconds == 200)
        #expect(updated[parent.id]?.remainingSeconds == 200)
        #expect(updated[unrelated.id] == initial[unrelated.id])
    }
}
