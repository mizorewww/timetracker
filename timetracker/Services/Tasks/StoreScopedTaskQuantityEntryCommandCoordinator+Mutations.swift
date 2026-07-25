import Foundation
import SwiftData

extension StoreScopedTaskQuantityEntryCommandCoordinator {
    func record(
        command: TaskQuantityEntryRecordCommand,
        context: ModelContext,
        state: TaskQuantityEntryPersistenceState
    ) throws -> TaskQuantityEntryMutationOutcome {
        try validate(amount: command.amount, recordedAt: command.recordedAt)
        try validate(
            goalBaseline: command.goalBaseline,
            taskID: command.taskID
        )

        let claimedRows = state.quantityEntries.filter {
            $0.id == command.proposedEntryID
        }
        if let replay = try recordReplayOutcome(
            command: command,
            claimedRows: claimedRows,
            state: state
        ) {
            return replay
        }

        try requireRecordingAllowed(taskID: command.taskID, state: state)
        _ = try requireActiveGoal(
            baseline: command.goalBaseline,
            state: state
        )

        let mutationDate = try mutationDate(
            observedRows: claimedRows
        )
        let entry = TaskQuantityEntry(
            id: command.proposedEntryID,
            taskID: command.taskID,
            amount: command.amount,
            recordedAt: command.recordedAt,
            createdAt: mutationDate,
            deviceID: deviceID
        )
        entry.updatedAt = mutationDate
        entry.clientMutationID = command.proposedEntryID
        context.insert(entry)
        try didReachCheckpoint(.entryInserted(entry.id))

        return outcome(
            entryID: entry.id,
            taskID: command.taskID,
            didMutate: true,
            state: state,
            entries: state.quantityEntries + [entry]
        )
    }

    func update(
        command: TaskQuantityEntryUpdateCommand,
        state: TaskQuantityEntryPersistenceState
    ) throws -> TaskQuantityEntryMutationOutcome {
        let baseline = command.entryBaseline
        try validate(amount: command.amount, recordedAt: command.recordedAt)
        try validate(
            goalBaseline: command.goalBaseline,
            taskID: baseline.taskID
        )
        guard baseline.quantityGoalID == command.goalBaseline.goalID else {
            throw TaskQuantityEntryMutationError.entryChanged
        }

        let rows = state.quantityEntries.filter {
            $0.id == baseline.entryID
        }
        let entry = try requireEntry(
            rows: rows,
            baseline: baseline,
            replayOperationID: command.operationID,
            replayMatches: {
                $0.deletedAt == nil &&
                    $0.amount == command.amount &&
                    $0.recordedAt == command.recordedAt
            }
        )
        if entry.clientMutationID == command.operationID {
            return outcome(
                entryID: entry.id,
                taskID: entry.taskID,
                didMutate: false,
                state: state
            )
        }

        try requireRecordingAllowed(taskID: baseline.taskID, state: state)
        _ = try requireActiveGoal(
            baseline: command.goalBaseline,
            state: state
        )
        guard entry.amount != command.amount ||
            entry.recordedAt != command.recordedAt
        else {
            return outcome(
                entryID: entry.id,
                taskID: entry.taskID,
                didMutate: false,
                state: state
            )
        }

        let date = try mutationDate(observedRows: rows)
        entry.amount = command.amount
        entry.recordedAt = command.recordedAt
        entry.updatedAt = date
        entry.deviceID = deviceID
        entry.clientMutationID = command.operationID
        try didReachCheckpoint(.entryUpdated(entry.id))
        return outcome(
            entryID: entry.id,
            taskID: entry.taskID,
            didMutate: true,
            state: state
        )
    }

    func delete(
        command: TaskQuantityEntryDeleteCommand,
        state: TaskQuantityEntryPersistenceState
    ) throws -> TaskQuantityEntryMutationOutcome {
        let baseline = command.entryBaseline
        guard baseline.quantityGoalID ==
            TaskProgressIdentity.quantityGoalID(taskID: baseline.taskID)
        else {
            throw TaskQuantityEntryMutationError.entryChanged
        }
        let rows = state.quantityEntries.filter {
            $0.id == baseline.entryID
        }
        guard let entry = rows.latestByID()[baseline.entryID] else {
            throw TaskQuantityEntryMutationError.entryUnavailable
        }
        guard entry.taskID == baseline.taskID,
              entry.quantityGoalID == baseline.quantityGoalID
        else {
            throw TaskQuantityEntryMutationError.entryChanged
        }
        if entry.deletedAt != nil {
            guard entry.clientMutationID == command.operationID else {
                throw TaskQuantityEntryMutationError.entryUnavailable
            }
            return outcome(
                entryID: entry.id,
                taskID: entry.taskID,
                didMutate: false,
                state: state
            )
        }
        guard entry.clientMutationID == baseline.clientMutationID else {
            throw TaskQuantityEntryMutationError.entryChanged
        }

        let date = try mutationDate(observedRows: rows)
        entry.deletedAt = date
        entry.updatedAt = date
        entry.deviceID = deviceID
        entry.clientMutationID = command.operationID
        try didReachCheckpoint(.entryDeleted(entry.id))
        return outcome(
            entryID: entry.id,
            taskID: entry.taskID,
            didMutate: true,
            state: state
        )
    }
}
