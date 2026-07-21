import Foundation

extension StoreScopedTaskQuantityEntryCommandCoordinator {
    func recordReplayOutcome(
        command: TaskQuantityEntryRecordCommand,
        claimedRows: [TaskQuantityEntry],
        state: TaskQuantityEntryPersistenceState
    ) throws -> TaskQuantityEntryMutationOutcome? {
        guard let entry = claimedRows.latestByID()[
            command.proposedEntryID
        ] else {
            return nil
        }
        guard entry.taskID == command.taskID,
              entry.quantityGoalID == command.goalBaseline.goalID else {
            throw TaskQuantityEntryMutationError.entryChanged
        }
        guard entry.deletedAt == nil else {
            throw TaskQuantityEntryMutationError.entryUnavailable
        }
        guard entry.clientMutationID == command.proposedEntryID,
              entry.amount == command.amount,
              entry.recordedAt == command.recordedAt else {
            throw TaskQuantityEntryMutationError.entryChanged
        }
        return outcome(
            entryID: entry.id,
            taskID: entry.taskID,
            didMutate: false,
            state: state
        )
    }

    func outcome(
        entryID: UUID,
        taskID: UUID,
        didMutate: Bool,
        state: TaskQuantityEntryPersistenceState,
        entries: [TaskQuantityEntry]? = nil
    ) -> TaskQuantityEntryMutationOutcome {
        TaskQuantityEntryMutationOutcome(
            taskID: taskID,
            entryID: entryID,
            didMutate: didMutate,
            affectedAncestorTaskIDs:
                state.affectedAncestorTaskIDs(for: taskID),
            progressSnapshot: TaskQuantityProgressService().snapshot(
                taskID: taskID,
                goals: state.quantityGoals,
                entries: entries ?? state.quantityEntries,
                isRecordingAllowed:
                    state.directWorkTaskIDs.contains(taskID)
            )
        )
    }
}
