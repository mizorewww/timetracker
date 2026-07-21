import Foundation

extension TimeTrackerStore {
    func taskQuantityProgressReadState(
        for taskID: UUID
    ) -> TaskQuantityProgressReadState {
        _ = taskReadModelRevision
        guard taskIDsWithIncompleteQuantityProgress.contains(taskID) == false
        else {
            return .incomplete
        }
        if let snapshot = TaskQuantityProgressService().snapshot(
            taskID: taskID,
            goals: taskQuantityGoals,
            entries: taskQuantityEntries,
            isRecordingAllowed: trackableTaskIDs.contains(taskID)
        ) {
            return .available(snapshot)
        }

        let expectedGoalID = TaskProgressIdentity.quantityGoalID(
            taskID: taskID
        )
        let hasVisibleClaim = taskQuantityGoals.contains {
            $0.deletedAt == nil &&
                ($0.taskID == taskID || $0.id == expectedGoalID)
        } || taskQuantityEntries.contains {
            $0.deletedAt == nil &&
                ($0.taskID == taskID ||
                    $0.quantityGoalID == expectedGoalID)
        }
        return hasVisibleClaim ? .incomplete : .none
    }

    func taskQuantityProgressReadState(
        for taskID: UUID,
        expectedGoalMutationID: UUID?
    ) -> TaskQuantityProgressReadState {
        switch taskQuantityProgressReadState(for: taskID) {
        case .none:
            return expectedGoalMutationID == nil ? .none : .incomplete
        case .incomplete:
            return .incomplete
        case .available(let snapshot):
            return snapshot.goalBaseline.clientMutationID ==
                expectedGoalMutationID
                ? .available(snapshot)
                : .incomplete
        }
    }

    func taskQuantityProgress(
        for taskID: UUID
    ) -> TaskQuantityProgressSnapshot? {
        switch taskQuantityProgressReadState(for: taskID) {
        case .available(let snapshot):
            return snapshot
        case .none, .incomplete:
            return nil
        }
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
