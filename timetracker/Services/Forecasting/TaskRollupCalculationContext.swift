import Foundation

struct TaskRollupCalculationContext {
    private let service: TaskRollupService
    private let taskByID: [UUID: TaskNode]
    private let childrenByParent: [UUID?: [TaskNode]]
    private let ownWorkedSecondsByTaskID: [UUID: Int]
    private let checklistProgressByTaskID: [UUID: ChecklistProgress]
    private let forecastEligibleTaskIDs: Set<UUID>?
    private let postorderTaskIDs: [UUID]
    private let historicalPaceByTaskID: [UUID: TaskRollupHistoricalPace]
    private let initialCache: [UUID: TaskRollup]
    private var updates: [UUID: TaskRollup] = [:]

    init(
        service: TaskRollupService,
        tasks: [TaskNode],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        forecastEligibleTaskIDs: Set<UUID>?,
        now: Date,
        initialCache: [UUID: TaskRollup]
    ) {
        let inputs = TaskRollupInputAggregation().inputs(
            tasks: tasks,
            segments: segments,
            checklistItems: checklistItems,
            now: now
        )
        self.init(
            service: service,
            taskByID: inputs.taskByID,
            childrenByParent: inputs.childrenByParent,
            ownWorkedSecondsByTaskID: inputs.ownWorkedSecondsByTaskID,
            checklistProgressByTaskID: inputs.checklistProgressByTaskID,
            historicalPaceByTaskID: inputs.historicalPaceByTaskID,
            forecastEligibleTaskIDs: forecastEligibleTaskIDs,
            postorderTaskIDs: inputs.postorderTaskIDs,
            initialCache: initialCache
        )
    }

    /// Pre-indexed initializer used by `RollupStore` after the initial load.
    /// Keeping raw persistence models out of this path prevents a single
    /// mutation from regrouping the complete ledger or checklist on MainActor.
    init(
        service: TaskRollupService,
        taskByID: [UUID: TaskNode],
        childrenByParent: [UUID?: [TaskNode]],
        ownWorkedSecondsByTaskID: [UUID: Int],
        checklistProgressByTaskID: [UUID: ChecklistProgress],
        historicalPaceByTaskID: [UUID: TaskRollupHistoricalPace],
        forecastEligibleTaskIDs: Set<UUID>?,
        postorderTaskIDs: [UUID],
        initialCache: [UUID: TaskRollup]
    ) {
        self.service = service
        self.taskByID = taskByID
        self.childrenByParent = childrenByParent
        self.ownWorkedSecondsByTaskID = ownWorkedSecondsByTaskID
        self.checklistProgressByTaskID = checklistProgressByTaskID
        self.historicalPaceByTaskID = historicalPaceByTaskID
        self.forecastEligibleTaskIDs = forecastEligibleTaskIDs
        self.postorderTaskIDs = postorderTaskIDs
        self.initialCache = initialCache
    }

    mutating func calculate(buildIDs: Set<UUID>?) -> [UUID: TaskRollup] {
        let idsToBuild = buildIDs ?? Set(taskByID.keys)
        for taskID in postorderTaskIDs {
            guard idsToBuild.contains(taskID) || rollup(for: taskID) == nil else { continue }
            build(taskID: taskID)
        }
        var result = initialCache.filter { taskByID[$0.key] != nil }
        result.merge(updates) { _, updated in updated }
        return result
    }

    /// Returns only rebuilt values. The mutation hot path merges these after
    /// this context releases its read-only cache, avoiding a copy and scan of
    /// every task rollup for a one-branch update.
    mutating func calculateUpdates(buildOrder: [UUID]) -> [UUID: TaskRollup] {
        for taskID in buildOrder where taskByID[taskID] != nil {
            build(taskID: taskID)
        }
        return updates
    }

    private mutating func build(taskID: UUID) {
        guard let task = taskByID[taskID] else { return }
        let childRollups = (childrenByParent[taskID] ?? []).compactMap { rollup(for: $0.id) }
        let ownWorked = ownWorkedSecondsByTaskID[taskID] ?? 0
        let progress = checklistProgress(for: taskID)
        let ownForecast = service.ownChecklistForecast(task: task, ownWorkedSeconds: ownWorked, progress: progress)
        let worked = ownWorked + childRollups.reduce(0) { $0 + $1.workedSeconds }
        let resolver = TaskRollupResolutionService(
            service: service,
            forecastEligibleTaskIDs: forecastEligibleTaskIDs
        )
        let forecast = resolver.resolve(
            task: task,
            progress: progress,
            ownForecast: ownForecast,
            childRollups: childRollups
        )
        let estimate = forecast.remainingSeconds.map { max(worked + $0, worked) }
        let pace = historicalPaceByTaskID[taskID]
        let sourceIDs = Array(
            service.orderedUnique(forecast.sourceIDs)
                .prefix(TaskRollupResolutionService.maximumSampledSourceIDs)
        )

        let rollup = TaskRollup(
            taskID: taskID,
            workedSeconds: worked,
            estimatedTotalSeconds: estimate,
            remainingSeconds: forecast.remainingSeconds,
            projectedDays: service.projectedDays(for: forecast.remainingSeconds, dailyAverageSeconds: pace?.averageSeconds),
            historicalDailyAverageSeconds: pace?.averageSeconds,
            historicalActiveDayCount: pace?.activeDayCount ?? 0,
            checklistProgress: progress,
            confidence: estimate == nil ? .none : resolver.confidence(
                ownForecast: ownForecast,
                childRollups: childRollups,
                estimate: estimate
            ),
            reason: forecast.reason,
            forecastState: forecast.state,
            forecastSourceTaskCount: forecast.sourceCount,
            forecastSourceTaskIDs: sourceIDs,
            forecastSourceLabel: service.sourceLabel(
                sourceCount: forecast.sourceCount,
                sampledSourceIDs: sourceIDs,
                ownTaskID: taskID,
                hasOwnSource: ownForecast.contributesSource
            )
        )
        updates[taskID] = rollup
    }

    private func rollup(for taskID: UUID) -> TaskRollup? {
        updates[taskID] ?? initialCache[taskID]
    }

    private func checklistProgress(for taskID: UUID) -> ChecklistProgress {
        checklistProgressByTaskID[taskID] ?? ChecklistProgress(
            taskID: taskID,
            totalCount: 0,
            completedCount: 0
        )
    }
}
