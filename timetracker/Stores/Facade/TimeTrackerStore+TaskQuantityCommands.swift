import Foundation
import SwiftData

extension TimeTrackerStore {
    func recordTaskQuantity(
        taskID: UUID,
        amount: Int,
        entryID: UUID,
        recordedAt: Date = Date()
    ) throws {
        guard let goalBaseline = taskQuantityGoalBaseline(for: taskID) else {
            let error = taskQuantityReadModelError(taskID: taskID)
            handleTaskQuantityCommandError(error)
            throw error
        }
        try recordTaskQuantity(
            taskID: taskID,
            goalBaseline: goalBaseline,
            amount: amount,
            entryID: entryID,
            recordedAt: recordedAt
        )
    }

    func recordTaskQuantity(
        taskID: UUID,
        goalBaseline: TaskQuantityGoalMutationBaseline,
        amount: Int,
        entryID: UUID,
        recordedAt: Date = Date()
    ) throws {
        try performTaskQuantityCommand { coordinator in
            try coordinator.record(
                command: TaskQuantityEntryRecordCommand(
                    taskID: taskID,
                    goalBaseline: goalBaseline,
                    amount: amount,
                    recordedAt: recordedAt,
                    proposedEntryID: entryID
                )
            )
        }
    }

    func updateTaskQuantityEntry(
        baseline: TaskQuantityEntryMutationBaseline,
        amount: Int,
        recordedAt: Date,
        operationID: UUID
    ) throws {
        guard let goalBaseline = taskQuantityGoalBaseline(
            for: baseline.taskID
        ) else {
            let error = taskQuantityReadModelError(taskID: baseline.taskID)
            handleTaskQuantityCommandError(error)
            throw error
        }
        try updateTaskQuantityEntry(
            baseline: baseline,
            goalBaseline: goalBaseline,
            amount: amount,
            recordedAt: recordedAt,
            operationID: operationID
        )
    }

    func updateTaskQuantityEntry(
        baseline: TaskQuantityEntryMutationBaseline,
        goalBaseline: TaskQuantityGoalMutationBaseline,
        amount: Int,
        recordedAt: Date,
        operationID: UUID
    ) throws {
        try performTaskQuantityCommand { coordinator in
            try coordinator.update(
                command: TaskQuantityEntryUpdateCommand(
                    entryBaseline: baseline,
                    goalBaseline: goalBaseline,
                    amount: amount,
                    recordedAt: recordedAt,
                    operationID: operationID
                )
            )
        }
    }

    func deleteTaskQuantityEntry(
        baseline: TaskQuantityEntryMutationBaseline,
        operationID: UUID
    ) throws {
        try performTaskQuantityCommand { coordinator in
            try coordinator.delete(
                command: TaskQuantityEntryDeleteCommand(
                    entryBaseline: baseline,
                    operationID: operationID
                )
            )
        }
    }

    private func performTaskQuantityCommand(
        operation: (
            StoreScopedTaskQuantityEntryCommandCoordinator
        ) throws -> TaskQuantityEntryMutationOutcome
    ) throws {
        try performStoreCommand(
            onError: handleTaskQuantityCommandError,
            command: { session in
                try operation(
                    StoreScopedTaskQuantityEntryCommandCoordinator(
                        session: session
                    )
                )
            },
            finish: { outcome in
                if outcome.didMutate {
                    finishStoreScopedMutation(events: outcome.events)
                } else {
                    try refresh(
                        plan: StoreRefreshPlanner.plan(
                            after: outcome.convergenceEvents
                        )
                    )
                }
            }
        )
    }

    private func handleTaskQuantityCommandError(
        _ error: Error
    ) {
        if error is TaskQuantityEntryMutationError {
            refreshLoggingFailure(plan: StoreRefreshPlan(scopes: [.tasks]))
        }
    }

    private func taskQuantityReadModelError(
        taskID: UUID
    ) -> TaskQuantityEntryMutationError {
        let expectedGoalID = TaskProgressIdentity.quantityGoalID(
            taskID: taskID
        )
        let hasVisibleGoalClaim = taskQuantityGoals.contains {
            $0.taskID == taskID || $0.id == expectedGoalID
        }
        return if hasVisibleGoalClaim ||
            taskIDsWithIncompleteQuantityProgress.contains(taskID)
        {
            .incompleteQuantityGraph
        } else {
            .quantityGoalUnavailable
        }
    }
}
