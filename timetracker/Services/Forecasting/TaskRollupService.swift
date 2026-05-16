import Foundation

struct TaskRollupService {
    func checklistProgress(for taskID: UUID, checklistItems: [ChecklistItem]) -> ChecklistProgress {
        let items = checklistItems.filter { $0.taskID == taskID && $0.deletedAt == nil }
        return ChecklistProgress(
            taskID: taskID,
            totalCount: items.count,
            completedCount: items.filter(\.isCompleted).count
        )
    }

    func rollups(
        tasks: [TaskNode],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        forecastEligibleTaskIDs: Set<UUID>? = nil,
        now: Date = Date()
    ) -> [UUID: TaskRollup] {
        var context = TaskRollupCalculationContext(
            service: self,
            tasks: tasks,
            segments: segments,
            checklistItems: checklistItems,
            forecastEligibleTaskIDs: forecastEligibleTaskIDs,
            now: now,
            initialCache: [:]
        )
        return context.calculate(buildIDs: nil)
    }

    func rollups(
        updating affectedTaskIDs: Set<UUID>,
        existingRollups: [UUID: TaskRollup],
        tasks: [TaskNode],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        forecastEligibleTaskIDs: Set<UUID>? = nil,
        now: Date = Date()
    ) -> [UUID: TaskRollup] {
        let knownTaskIDs = Set(tasks.map(\.id))
        let affected = affectedTaskIDs.intersection(knownTaskIDs)
        guard !affected.isEmpty, !existingRollups.isEmpty else {
            return rollups(
                tasks: tasks,
                segments: segments,
                checklistItems: checklistItems,
                forecastEligibleTaskIDs: forecastEligibleTaskIDs,
                now: now
            )
        }

        let affectedWithAncestors = affected.union(ancestorIDs(of: affected, tasks: tasks))
        let seed = existingRollups.filter { taskID, _ in
            knownTaskIDs.contains(taskID) && !affectedWithAncestors.contains(taskID)
        }

        var context = TaskRollupCalculationContext(
            service: self,
            tasks: tasks,
            segments: segments,
            checklistItems: checklistItems,
            forecastEligibleTaskIDs: forecastEligibleTaskIDs,
            now: now,
            initialCache: seed
        )
        return context.calculate(buildIDs: affectedWithAncestors)
    }

    private func ancestorIDs(of taskIDs: Set<UUID>, tasks: [TaskNode]) -> Set<UUID> {
        let taskByID = tasks.latestByID()
        var ancestors = Set<UUID>()

        for taskID in taskIDs {
            var parentID = taskByID[taskID]?.parentID
            var visited = Set<UUID>()
            while let currentID = parentID, !visited.contains(currentID) {
                visited.insert(currentID)
                ancestors.insert(currentID)
                parentID = taskByID[currentID]?.parentID
            }
        }

        return ancestors
    }

}
