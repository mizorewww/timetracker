import Foundation

struct RollupStore {
    private let rollupService = TaskRollupService()
    private(set) var taskRollups: [UUID: TaskRollup] = [:]
    private var incrementalIndex = RollupIncrementalIndex()

    mutating func refresh(
        tasks: [TaskNode],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        forecastEligibleTaskIDs: Set<UUID>? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        PerformanceSignpost.interval("Rollup service calculation") {
            incrementalIndex.rebuild(
                tasks: tasks,
                segments: segments,
                checklistItems: checklistItems,
                now: now,
                calendar: calendar
            )
            var context = TaskRollupCalculationContext(
                service: rollupService,
                taskByID: incrementalIndex.taskByID,
                childrenByParent: incrementalIndex.childrenByParent,
                ownWorkedSecondsByTaskID: incrementalIndex.ownWorkedSecondsByTaskID,
                checklistProgressByTaskID: incrementalIndex.checklistProgressByTaskID,
                historicalPaceByTaskID: incrementalIndex.historicalPaceByTaskID,
                forecastEligibleTaskIDs: forecastEligibleTaskIDs,
                postorderTaskIDs: incrementalIndex.postorderTaskIDs,
                initialCache: [:]
            )
            taskRollups = context.calculateUpdates(buildOrder: incrementalIndex.postorderTaskIDs)
        }
    }

    /// Compatibility overload for service-level callers. The application uses
    /// the scoped overload below so this method never sits on a mutation hot path.
    mutating func refreshAffected(
        taskIDs: Set<UUID>,
        tasks: [TaskNode],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        forecastEligibleTaskIDs: Set<UUID>? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard incrementalIndex.isInitialized else {
            refresh(
                tasks: tasks,
                segments: segments,
                checklistItems: checklistItems,
                forecastEligibleTaskIDs: forecastEligibleTaskIDs,
                now: now,
                calendar: calendar
            )
            return
        }
        let scopedChecklistItems = Dictionary(
            grouping: checklistItems.filter { taskIDs.contains($0.taskID) },
            by: \.taskID
        )
        refreshAffected(
            directTaskIDs: taskIDs,
            explicitAncestorTaskIDs: [],
            segmentChanges: incrementalIndex.replacementChanges(taskIDs: taskIDs, segments: segments),
            checklistItemsByTaskID: scopedChecklistItems,
            forecastEligibleTaskIDs: forecastEligibleTaskIDs,
            now: now,
            calendar: calendar
        )
    }

    mutating func refreshAffected(
        directTaskIDs: Set<UUID>,
        explicitAncestorTaskIDs: Set<UUID>,
        segmentChanges: [LedgerSegmentChange],
        checklistItemsByTaskID: [UUID: [ChecklistItem]],
        forecastEligibleTaskIDs: Set<UUID>? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        PerformanceSignpost.interval("Rollup service calculation") {
            let buildOrder = incrementalIndex.apply(
                directTaskIDs: directTaskIDs,
                explicitAncestorTaskIDs: explicitAncestorTaskIDs,
                segmentChanges: segmentChanges,
                checklistItemsByTaskID: checklistItemsByTaskID,
                now: now,
                calendar: calendar
            )
            guard !buildOrder.isEmpty else { return }
            let updates: [UUID: TaskRollup] = {
                var context = TaskRollupCalculationContext(
                    service: rollupService,
                    taskByID: incrementalIndex.taskByID,
                    childrenByParent: incrementalIndex.childrenByParent,
                    ownWorkedSecondsByTaskID: incrementalIndex.ownWorkedSecondsByTaskID,
                    checklistProgressByTaskID: incrementalIndex.checklistProgressByTaskID,
                    historicalPaceByTaskID: incrementalIndex.historicalPaceByTaskID,
                    forecastEligibleTaskIDs: forecastEligibleTaskIDs,
                    postorderTaskIDs: incrementalIndex.postorderTaskIDs,
                    initialCache: taskRollups
                )
                return context.calculateUpdates(buildOrder: buildOrder)
            }()
            for (taskID, rollup) in updates {
                taskRollups[taskID] = rollup
            }
        }
    }

    func rollup(for taskID: UUID) -> TaskRollup? {
        taskRollups[taskID]
    }

    func activitySummary(for taskID: UUID) -> TaskLedgerActivitySummary? {
        incrementalIndex.activitySummary(for: taskID)
    }

    func checklistProgress(for taskID: UUID, checklistItems: [ChecklistItem]) -> ChecklistProgress {
        rollupService.checklistProgress(for: taskID, checklistItems: checklistItems)
    }
}
