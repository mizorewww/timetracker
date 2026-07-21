import Foundation

@MainActor
struct TaskQuantityProgressService {
    struct ValidatedSnapshot {
        let progress: TaskQuantityProgressSnapshot
        let entries: [TaskQuantityEntrySnapshot]
    }

    func snapshot(
        taskID: UUID,
        goals: [TaskQuantityGoal],
        entries: [TaskQuantityEntry],
        isRecordingAllowed: Bool
    ) -> TaskQuantityProgressSnapshot? {
        validatedSnapshot(
            taskID: taskID,
            goals: goals,
            entries: entries,
            isRecordingAllowed: isRecordingAllowed
        )?.progress
    }

    func validatedSnapshot(
        taskID: UUID,
        goals: [TaskQuantityGoal],
        entries: [TaskQuantityEntry],
        isRecordingAllowed: Bool
    ) -> ValidatedSnapshot? {
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

        let progress = TaskQuantityProgressSnapshot(
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
        let entrySnapshots = connectedVisibleEntries
            .map(TaskQuantityEntrySnapshot.init)
            .sorted {
                if $0.recordedAt != $1.recordedAt {
                    return $0.recordedAt > $1.recordedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        return ValidatedSnapshot(
            progress: progress,
            entries: entrySnapshots
        )
    }

    func snapshotIndex(
        taskIDs: Set<UUID>,
        goals: [TaskQuantityGoal],
        entries: [TaskQuantityEntry],
        recordingAllowedTaskIDs: Set<UUID>,
        incompleteTaskIDs: Set<UUID>
    ) -> [UUID: TaskQuantityProgressSnapshot] {
        let goalWinners = goals.deduplicatedByID()
        let entryWinners = entries.deduplicatedByID()
        let goalsByTaskID = Dictionary(
            grouping: goalWinners,
            by: \.taskID
        )
        let goalsByID = Dictionary(grouping: goalWinners, by: \.id)
        let entriesByTaskID = Dictionary(
            grouping: entryWinners,
            by: \.taskID
        )
        let entriesByGoalID = Dictionary(
            grouping: entryWinners,
            by: \.quantityGoalID
        )

        return taskIDs.reduce(into: [:]) { result, taskID in
            guard incompleteTaskIDs.contains(taskID) == false else {
                return
            }
            let expectedGoalID = TaskProgressIdentity.quantityGoalID(
                taskID: taskID
            )
            let scopedGoals = (goalsByTaskID[taskID] ?? []) +
                (goalsByID[expectedGoalID] ?? [])
            let scopedEntries = (entriesByTaskID[taskID] ?? []) +
                (entriesByGoalID[expectedGoalID] ?? [])
            guard scopedGoals.isEmpty == false ||
                    scopedEntries.isEmpty == false else {
                return
            }
            result[taskID] = snapshot(
                taskID: taskID,
                goals: scopedGoals,
                entries: scopedEntries,
                isRecordingAllowed:
                    recordingAllowedTaskIDs.contains(taskID)
            )
        }
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
