import Foundation

extension StoreScopedTaskQuantityEntryCommandCoordinator {
    func validate(amount: Int, recordedAt: Date) throws {
        guard TaskQuantityPolicy.valueRange.contains(amount) else {
            throw TaskQuantityEntryMutationError.invalidAmount
        }
        guard PersistentDatePolicy.contains(recordedAt) else {
            throw TaskQuantityEntryMutationError.invalidRecordedAt
        }
    }

    func validate(
        goalBaseline: TaskQuantityGoalMutationBaseline,
        taskID: UUID
    ) throws {
        guard goalBaseline.taskID == taskID,
              goalBaseline.goalID ==
                TaskProgressIdentity.quantityGoalID(taskID: taskID) else {
            throw TaskQuantityEntryMutationError.quantityGoalChanged
        }
    }

    func requireRecordingAllowed(
        taskID: UUID,
        state: TaskQuantityEntryPersistenceState
    ) throws {
        if state.recurrenceTemplateTaskIDs.contains(taskID) {
            throw TaskQuantityEntryMutationError
                .recurrenceTemplateRequiresGeneratedTask
        }
        guard state.directWorkTaskIDs.contains(taskID) else {
            throw TaskQuantityEntryMutationError.taskUnavailable
        }
    }

    func requireActiveGoal(
        baseline: TaskQuantityGoalMutationBaseline,
        state: TaskQuantityEntryPersistenceState
    ) throws -> TaskQuantityGoal {
        let taskID = baseline.taskID
        let expectedGoalID = TaskProgressIdentity.quantityGoalID(
            taskID: taskID
        )
        let goalWinners = state.quantityGoals.latestByID()
        let entryWinners = state.quantityEntries.deduplicatedByID()
        let connectedVisibleGoals = goalWinners.values.filter {
            $0.deletedAt == nil &&
                ($0.id == expectedGoalID || $0.taskID == taskID)
        }
        let connectedVisibleEntries = entryWinners.filter {
            $0.deletedAt == nil &&
                ($0.quantityGoalID == expectedGoalID ||
                    $0.taskID == taskID)
        }

        guard let goal = goalWinners[expectedGoalID] else {
            if connectedVisibleGoals.isEmpty == false ||
                connectedVisibleEntries.isEmpty == false {
                throw TaskQuantityEntryMutationError
                    .incompleteQuantityGraph
            }
            throw TaskQuantityEntryMutationError.quantityGoalUnavailable
        }
        if goal.deletedAt != nil {
            guard connectedVisibleGoals.isEmpty,
                  connectedVisibleEntries.isEmpty else {
                throw TaskQuantityEntryMutationError
                    .incompleteQuantityGraph
            }
            guard goal.clientMutationID == baseline.clientMutationID else {
                throw TaskQuantityEntryMutationError.quantityGoalChanged
            }
            throw TaskQuantityEntryMutationError.quantityGoalUnavailable
        }
        guard goal.taskID == taskID,
              TaskQuantityProgressService().goalIsCanonical(goal) else {
            throw TaskQuantityEntryMutationError.incompleteQuantityGraph
        }

        let hasVisibleConflictingGoal = connectedVisibleGoals.contains {
            $0.id != expectedGoalID || $0.taskID != taskID
        }
        let hasInvalidOrConflictingEntry = connectedVisibleEntries.contains {
            ($0.quantityGoalID != expectedGoalID ||
                $0.taskID != taskID) ||
                TaskQuantityPolicy.valueRange.contains($0.amount) == false ||
                PersistentDatePolicy.contains($0.recordedAt) == false ||
                PersistentDatePolicy.contains($0.createdAt) == false ||
                PersistentDatePolicy.contains($0.updatedAt) == false
        }
        guard hasVisibleConflictingGoal == false,
              hasInvalidOrConflictingEntry == false else {
            throw TaskQuantityEntryMutationError.incompleteQuantityGraph
        }
        guard goal.clientMutationID == baseline.clientMutationID else {
            throw TaskQuantityEntryMutationError.quantityGoalChanged
        }
        return goal
    }

    func requireEntry(
        rows: [TaskQuantityEntry],
        baseline: TaskQuantityEntryMutationBaseline,
        replayOperationID: UUID,
        replayMatches: (TaskQuantityEntry) -> Bool
    ) throws -> TaskQuantityEntry {
        guard let entry = rows.latestByID()[baseline.entryID] else {
            throw TaskQuantityEntryMutationError.entryUnavailable
        }
        guard entry.taskID == baseline.taskID,
              entry.quantityGoalID == baseline.quantityGoalID else {
            throw TaskQuantityEntryMutationError.entryChanged
        }
        if entry.clientMutationID == replayOperationID {
            guard replayMatches(entry) else {
                throw TaskQuantityEntryMutationError.entryChanged
            }
            return entry
        }
        guard entry.deletedAt == nil else {
            throw TaskQuantityEntryMutationError.entryUnavailable
        }
        guard entry.clientMutationID == baseline.clientMutationID else {
            throw TaskQuantityEntryMutationError.entryChanged
        }
        return entry
    }

    func mutationDate(
        observedRows: [TaskQuantityEntry]
    ) throws -> Date {
        let preferred = nowProvider()
        guard PersistentDatePolicy.contains(preferred) else {
            throw TaskQuantityEntryMutationError.invalidRecordedAt
        }
        let date = PersistentLWWMutationDate.strictlyDominating(
            preferred: preferred,
            observed: observedRows.map(\.updatedAt)
        )
        guard PersistentDatePolicy.contains(date) else {
            throw TaskQuantityEntryMutationError.invalidRecordedAt
        }
        return date
    }
}
