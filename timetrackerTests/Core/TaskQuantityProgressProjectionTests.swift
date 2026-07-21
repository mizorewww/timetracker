import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct TaskQuantityProgressProjectionTests {
    @Test
    func snapshotIndexProjectsEachTaskOnceAndFailsCrossClaimsClosed() {
        let firstTaskID = UUID()
        let secondTaskID = UUID()
        let firstGoal = goal(
            taskID: firstTaskID,
            target: 50,
            unit: "reps"
        )
        let secondGoal = goal(
            taskID: secondTaskID,
            target: 10,
            unit: "pages"
        )
        let firstEntry = entry(taskID: firstTaskID, amount: 20)
        let secondEntry = entry(taskID: secondTaskID, amount: 5)
        let service = TaskQuantityProgressService()

        let index = service.snapshotIndex(
            taskIDs: [firstTaskID, secondTaskID, UUID()],
            goals: [firstGoal, secondGoal],
            entries: [firstEntry, secondEntry],
            recordingAllowedTaskIDs: [secondTaskID],
            incompleteTaskIDs: []
        )

        #expect(index[firstTaskID]?.totalAmount == 20)
        #expect(index[firstTaskID]?.isRecordingAllowed == false)
        #expect(index[secondTaskID]?.totalAmount == 5)
        #expect(index[secondTaskID]?.isRecordingAllowed == true)
        #expect(index.count == 2)

        let crossClaim = entry(taskID: firstTaskID, amount: 1)
        crossClaim.quantityGoalID = secondGoal.id
        let conflicted = service.snapshotIndex(
            taskIDs: [firstTaskID, secondTaskID],
            goals: [firstGoal, secondGoal],
            entries: [firstEntry, secondEntry, crossClaim],
            recordingAllowedTaskIDs: [firstTaskID, secondTaskID],
            incompleteTaskIDs: []
        )

        #expect(conflicted.isEmpty)
    }

    @Test
    func snapshotIndexOmitsIncompleteTasks() {
        let taskID = UUID()
        let index = TaskQuantityProgressService().snapshotIndex(
            taskIDs: [taskID],
            goals: [goal(taskID: taskID, target: 50, unit: "reps")],
            entries: [entry(taskID: taskID, amount: 20)],
            recordingAllowedTaskIDs: [taskID],
            incompleteTaskIDs: [taskID]
        )

        #expect(index.isEmpty)
    }

    @Test
    func snapshotIndexResolvesGlobalWinnersBeforeRelationshipBuckets() {
        let firstTaskID = UUID()
        let secondTaskID = UUID()
        let firstGoal = goal(
            taskID: firstTaskID,
            target: 50,
            unit: "reps"
        )
        let secondGoal = goal(
            taskID: secondTaskID,
            target: 10,
            unit: "pages"
        )
        let stableEntry = entry(taskID: firstTaskID, amount: 20)
        let duplicateID = UUID()
        let staleEntry = TaskQuantityEntry(
            id: duplicateID,
            taskID: firstTaskID,
            amount: 99,
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            deviceID: "stale"
        )
        let winningTombstone = TaskQuantityEntry(
            id: duplicateID,
            taskID: secondTaskID,
            amount: 1,
            createdAt: Date(timeIntervalSinceReferenceDate: 200),
            deviceID: "winner"
        )
        winningTombstone.deletedAt = Date(
            timeIntervalSinceReferenceDate: 300
        )
        winningTombstone.updatedAt = winningTombstone.deletedAt!

        let index = TaskQuantityProgressService().snapshotIndex(
            taskIDs: [firstTaskID, secondTaskID],
            goals: [firstGoal, secondGoal],
            entries: [stableEntry, staleEntry, winningTombstone],
            recordingAllowedTaskIDs: [firstTaskID, secondTaskID],
            incompleteTaskIDs: []
        )

        #expect(index[firstTaskID]?.totalAmount == 20)
        #expect(index[secondTaskID]?.totalAmount == 0)

        let newerCrossClaim = goal(
            taskID: secondTaskID,
            target: 50,
            unit: "reps"
        )
        newerCrossClaim.id = firstGoal.id
        firstGoal.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        newerCrossClaim.updatedAt = Date(
            timeIntervalSinceReferenceDate: 200
        )
        let conflicted = TaskQuantityProgressService().snapshotIndex(
            taskIDs: [firstTaskID, secondTaskID],
            goals: [firstGoal, secondGoal, newerCrossClaim],
            entries: [],
            recordingAllowedTaskIDs: [firstTaskID, secondTaskID],
            incompleteTaskIDs: []
        )

        #expect(conflicted.isEmpty)
    }

    private func goal(
        taskID: UUID,
        target: Int,
        unit: String
    ) -> TaskQuantityGoal {
        TaskQuantityGoal(
            taskID: taskID,
            targetAmount: target,
            unitLabel: unit,
            deviceID: "test"
        )
    }

    private func entry(
        taskID: UUID,
        amount: Int
    ) -> TaskQuantityEntry {
        TaskQuantityEntry(
            id: UUID(),
            taskID: taskID,
            amount: amount,
            deviceID: "test"
        )
    }
}
