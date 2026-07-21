import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func recordTaskQuantity(
        taskID: UUID,
        amount: Int,
        entryID: UUID,
        recordedAt: Date = Date()
    ) -> Bool {
        guard let goalBaseline = taskQuantityGoalBaseline(for: taskID) else {
            handleTaskQuantityCommandError(
                taskQuantityReadModelError(taskID: taskID)
            )
            return false
        }
        return recordTaskQuantity(
            taskID: taskID,
            goalBaseline: goalBaseline,
            amount: amount,
            entryID: entryID,
            recordedAt: recordedAt
        )
    }

    @discardableResult
    func recordTaskQuantity(
        taskID: UUID,
        goalBaseline: TaskQuantityGoalMutationBaseline,
        amount: Int,
        entryID: UUID,
        recordedAt: Date = Date()
    ) -> Bool {
        return performTaskQuantityCommand { coordinator in
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

    @discardableResult
    func updateTaskQuantityEntry(
        baseline: TaskQuantityEntryMutationBaseline,
        amount: Int,
        recordedAt: Date,
        operationID: UUID
    ) -> Bool {
        guard let goalBaseline = taskQuantityGoalBaseline(
            for: baseline.taskID
        ) else {
            handleTaskQuantityCommandError(
                taskQuantityReadModelError(taskID: baseline.taskID)
            )
            return false
        }
        return updateTaskQuantityEntry(
            baseline: baseline,
            goalBaseline: goalBaseline,
            amount: amount,
            recordedAt: recordedAt,
            operationID: operationID
        )
    }

    @discardableResult
    func updateTaskQuantityEntry(
        baseline: TaskQuantityEntryMutationBaseline,
        goalBaseline: TaskQuantityGoalMutationBaseline,
        amount: Int,
        recordedAt: Date,
        operationID: UUID
    ) -> Bool {
        return performTaskQuantityCommand { coordinator in
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

    @discardableResult
    func deleteTaskQuantityEntry(
        baseline: TaskQuantityEntryMutationBaseline,
        operationID: UUID
    ) -> Bool {
        performTaskQuantityCommand { coordinator in
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
    ) -> Bool {
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try operation(
                StoreScopedTaskQuantityEntryCommandCoordinator(
                    container: modelContext.container,
                    writeAuthorization: writeAuthorization
                )
            )
            if outcome.didMutate {
                finishStoreScopedMutation(events: outcome.events)
            } else {
                try refresh(
                    plan: refreshPlanner.plan(
                        after: outcome.convergenceEvents
                    )
                )
            }
            return true
        } catch {
            handleTaskQuantityCommandError(error)
            return false
        }
    }

    private func handleTaskQuantityCommandError(
        _ error: Error
    ) {
        if error is TaskQuantityEntryMutationError {
            do {
                try refreshTaskQuantityConvergence()
            } catch {
                errorMessage = String(
                    format: AppStrings.localized(
                        "error.savedRefreshFailed"
                    ),
                    error.localizedDescription
                )
                return
            }
        }
        errorMessage = error.localizedDescription
    }

    private func refreshTaskQuantityConvergence() throws {
        try refresh(
            plan: StoreRefreshPlan(scopes: [.tasks])
        )
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
            taskIDsWithIncompleteQuantityProgress.contains(taskID) {
            .incompleteQuantityGraph
        } else {
            .quantityGoalUnavailable
        }
    }
}
