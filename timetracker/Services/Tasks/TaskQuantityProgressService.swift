import Foundation

@MainActor
struct TaskQuantityProgressService {
    func snapshot(
        taskID: UUID,
        goals: [TaskQuantityGoal],
        entries: [TaskQuantityEntry],
        isRecordingAllowed: Bool
    ) -> TaskQuantityProgressSnapshot? {
        let expectedGoalID = TaskProgressIdentity.quantityGoalID(
            taskID: taskID
        )
        let goalWinners = goals.latestByID()
        guard let goal = goalWinners[expectedGoalID],
              goal.deletedAt == nil,
              goal.taskID == taskID,
              goalIsCanonical(goal) else {
            return nil
        }

        let hasVisibleConflictingGoal = goalWinners.values.contains {
            $0.deletedAt == nil &&
                ($0.taskID == taskID || $0.id == expectedGoalID) &&
                ($0.taskID != taskID || $0.id != expectedGoalID)
        }
        guard hasVisibleConflictingGoal == false else { return nil }

        let entryWinners = entries.deduplicatedByID()
        let connectedVisibleEntries = entryWinners.filter {
            $0.deletedAt == nil &&
                ($0.taskID == taskID ||
                    $0.quantityGoalID == expectedGoalID)
        }
        guard connectedVisibleEntries.allSatisfy({
                $0.taskID == taskID &&
                $0.quantityGoalID == expectedGoalID &&
                TaskQuantityPolicy.valueRange.contains($0.amount) &&
                PersistentDatePolicy.contains($0.recordedAt) &&
                PersistentDatePolicy.contains($0.createdAt) &&
                PersistentDatePolicy.contains($0.updatedAt)
        }) else {
            return nil
        }

        var total: Int64 = 0
        for entry in connectedVisibleEntries {
            let (next, overflow) = total.addingReportingOverflow(
                Int64(entry.amount)
            )
            total = overflow ? Int64.max : next
        }

        return TaskQuantityProgressSnapshot(
            taskID: taskID,
            goalBaseline: TaskQuantityGoalMutationBaseline(goal: goal),
            targetAmount: Int64(goal.targetAmount),
            unitLabel: goal.unitLabel,
            totalAmount: total,
            entryCount: connectedVisibleEntries.count,
            entryRevision: TaskQuantityEntryRevision.value(
                taskID: taskID,
                entries: entryWinners
            ),
            isRecordingAllowed: isRecordingAllowed
        )
    }

    func goalIsCanonical(_ goal: TaskQuantityGoal) -> Bool {
        guard TaskQuantityPolicy.valueRange.contains(goal.targetAmount),
              PersistentDatePolicy.contains(goal.createdAt),
              PersistentDatePolicy.contains(goal.updatedAt) else {
            return false
        }
        do {
            let prepared = try TaskProgressDraftPersistencePolicy.prepare(
                quantityGoal: TaskQuantityGoalDraft(
                    targetAmount: goal.targetAmount,
                    unitLabel: goal.unitLabel
                ),
                dailyRecurrence: nil
            ).quantityGoal
            return prepared?.targetAmount == goal.targetAmount &&
                prepared?.unitLabel == goal.unitLabel
        } catch {
            return false
        }
    }
}
