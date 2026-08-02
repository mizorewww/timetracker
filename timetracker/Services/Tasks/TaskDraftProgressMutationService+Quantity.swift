import Foundation
import SwiftData

nonisolated extension TaskDraftProgressMutationService {
    func saveQuantityGoal(
        _ draft: PreparedTaskQuantityGoalDraft?,
        confirmsProgressReset: Bool,
        taskID: UUID,
        now: Date
    ) throws {
        let requestedTaskID = taskID
        let goalRows = try context.fetch(
            FetchDescriptor<TaskQuantityGoal>(
                predicate: #Predicate { $0.taskID == requestedTaskID }
            )
        )
        let goalID = TaskProgressIdentity.quantityGoalID(taskID: taskID)
        let requestedGoalID = goalID
        let identityRows = try context.fetch(
            FetchDescriptor<TaskQuantityGoal>(
                predicate: #Predicate { $0.id == requestedGoalID }
            )
        )
        let existing = identityRows.latestByID()[goalID]
        let entryRows = try context.fetch(
            FetchDescriptor<TaskQuantityEntry>(
                predicate: #Predicate { $0.taskID == requestedTaskID }
            )
        )
        let activeEntries = entryRows.visibleDeduplicatedByID().filter {
            $0.quantityGoalID == goalID
        }

        guard let draft else {
            guard let existing, existing.deletedAt == nil else { return }
            guard confirmsProgressReset else {
                throw TaskProgressDraftMutationError
                    .quantityGoalRemovalRequiresConfirmation
            }
            let mutationDate = mutationDate(
                preferred: now,
                goalRows: goalRows,
                entryRows: entryRows
            )
            tombstone(existing, at: mutationDate)
            activeEntries.forEach { tombstone($0, at: mutationDate) }
            try didReachCheckpoint(.quantityGoalChanged(existing.id))
            return
        }

        let hasAmbiguousGoalClaim = goalRows.contains {
            $0.id != goalID
        } || identityRows.contains {
            $0.taskID != taskID
        }
        if hasAmbiguousGoalClaim ||
            existing == nil && (
                goalRows.isEmpty == false ||
                    entryRows.contains {
                        $0.quantityGoalID == goalID
                    }
            )
        {
            throw TaskProgressDraftMutationError.incompleteQuantityGraph
        }
        if unitChangeWouldReinterpretProgress(
            existing: existing,
            draft: draft,
            activeEntries: activeEntries
        ) {
            throw TaskProgressDraftMutationError
                .unitChangeRequiresProgressReset
        }

        if let existing {
            try update(
                existing,
                from: draft,
                goalRows: goalRows,
                entryRows: entryRows,
                activeEntries: activeEntries,
                now: now
            )
            return
        }
        try insert(draft, taskID: taskID, now: now)
    }

    private func update(
        _ goal: TaskQuantityGoal,
        from draft: PreparedTaskQuantityGoalDraft,
        goalRows: [TaskQuantityGoal],
        entryRows: [TaskQuantityEntry],
        activeEntries: [TaskQuantityEntry],
        now: Date
    ) throws {
        let isUnchanged = goal.deletedAt == nil &&
            goal.targetAmount == draft.targetAmount &&
            goal.unitLabel == draft.unitLabel
        guard isUnchanged == false else { return }
        let date = mutationDate(
            preferred: now,
            goalRows: goalRows,
            entryRows: entryRows
        )
        if goal.deletedAt != nil {
            activeEntries.forEach { tombstone($0, at: date) }
        }
        goal.targetAmount = draft.targetAmount
        goal.unitLabel = draft.unitLabel
        goal.deletedAt = nil
        goal.updatedAt = date
        goal.deviceID = deviceID
        goal.clientMutationID = UUID()
        try didReachCheckpoint(.quantityGoalChanged(goal.id))
    }

    private func insert(
        _ draft: PreparedTaskQuantityGoalDraft,
        taskID: UUID,
        now: Date
    ) throws {
        let goal = TaskQuantityGoal(
            taskID: taskID,
            targetAmount: draft.targetAmount,
            unitLabel: draft.unitLabel,
            deviceID: deviceID
        )
        goal.createdAt = now
        goal.updatedAt = now
        goal.clientMutationID = UUID()
        context.insert(goal)
        try didReachCheckpoint(.quantityGoalChanged(goal.id))
    }

    private func unitChangeWouldReinterpretProgress(
        existing: TaskQuantityGoal?,
        draft: PreparedTaskQuantityGoalDraft,
        activeEntries: [TaskQuantityEntry]
    ) -> Bool {
        guard let existing, existing.deletedAt == nil else { return false }
        return existing.unitLabel.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) != draft.unitLabel && activeEntries.isEmpty == false
    }

    private func mutationDate(
        preferred: Date,
        goalRows: [TaskQuantityGoal],
        entryRows: [TaskQuantityEntry]
    ) -> Date {
        PersistentLWWMutationDate.strictlyDominating(
            preferred: preferred,
            observed: goalRows.map(\.updatedAt) +
                entryRows.map(\.updatedAt)
        )
    }

    private func tombstone<Model>(
        _ model: Model,
        at date: Date
    ) where Model: SoftDeletablePersistentUUIDModel &
        ClientMutationTrackedModel
    {
        model.deletedAt = date
        model.updatedAt = date
        model.deviceID = deviceID
        model.clientMutationID = UUID()
    }
}
