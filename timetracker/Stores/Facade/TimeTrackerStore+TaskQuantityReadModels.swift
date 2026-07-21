import Foundation

extension TimeTrackerStore {
    func taskQuantityProgress(
        for taskID: UUID
    ) -> TaskQuantityProgressSnapshot? {
        // Quantity models can merge from a sibling SwiftData context without
        // changing an existing @Model reference. The value-semantic task
        // revision guarantees observing views invalidate after task refresh.
        _ = taskReadModelRevision
        guard taskIDsWithIncompleteQuantityProgress.contains(taskID) == false
        else {
            return nil
        }
        return TaskQuantityProgressService().snapshot(
            taskID: taskID,
            goals: taskQuantityGoals,
            entries: taskQuantityEntries,
            isRecordingAllowed: trackableTaskIDs.contains(taskID)
        )
    }

    func taskQuantityEntries(for taskID: UUID) -> [TaskQuantityEntry] {
        _ = taskReadModelRevision
        return taskQuantityEntries.filter { $0.taskID == taskID }
    }

    func taskQuantityGoalBaseline(
        for taskID: UUID
    ) -> TaskQuantityGoalMutationBaseline? {
        taskQuantityProgress(for: taskID)?.goalBaseline
    }
}
