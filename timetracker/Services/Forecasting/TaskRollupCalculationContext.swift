import Foundation

struct TaskRollupCalculationContext {
    private let service: TaskRollupService
    private let aggregationService = TimeAggregationService()
    private let taskByID: [UUID: TaskNode]
    private let childrenByParent: [UUID?: [TaskNode]]
    private let segmentsByTaskID: [UUID: [TimeSegment]]
    private let checklistItemsByTaskID: [UUID: [ChecklistItem]]
    private let forecastEligibleTaskIDs: Set<UUID>?
    private let now: Date
    private var cache: [UUID: TaskRollup]
    private var subtreeCache: [UUID: Set<UUID>] = [:]

    init(
        service: TaskRollupService,
        tasks: [TaskNode],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        forecastEligibleTaskIDs: Set<UUID>?,
        now: Date,
        initialCache: [UUID: TaskRollup]
    ) {
        let tasks = tasks.deduplicatedByID()
        self.service = service
        self.taskByID = tasks.latestByID()
        self.childrenByParent = Dictionary(grouping: tasks, by: \.parentID)
        self.segmentsByTaskID = Dictionary(grouping: segments.deduplicatedByID().filter { $0.deletedAt == nil }, by: \.taskID)
        self.checklistItemsByTaskID = Dictionary(grouping: checklistItems.deduplicatedByID().filter { $0.deletedAt == nil }, by: \.taskID)
        self.forecastEligibleTaskIDs = forecastEligibleTaskIDs
        self.now = now
        self.cache = initialCache
    }

    mutating func calculate(buildIDs: Set<UUID>?) -> [UUID: TaskRollup] {
        let idsToBuild = buildIDs ?? Set(taskByID.keys)
        for taskID in idsToBuild {
            _ = build(taskID: taskID, visited: [])
        }
        return cache.filter { taskByID[$0.key] != nil }
    }

    private mutating func build(taskID: UUID, visited: Set<UUID>) -> TaskRollup? {
        if let cached = cache[taskID] {
            return cached
        }
        guard let task = taskByID[taskID], !visited.contains(taskID) else {
            return nil
        }

        let childRollups = buildChildRollups(for: taskID, visited: visited)
        let ownWorked = aggregationService.grossSeconds(segmentsByTaskID[taskID] ?? [], now: now)
        let progress = checklistProgress(for: taskID)
        let ownForecast = service.ownChecklistForecast(task: task, ownWorkedSeconds: ownWorked, progress: progress)
        let worked = ownWorked + childRollups.reduce(0) { $0 + $1.workedSeconds }
        let forecast = resolvedForecast(task: task, progress: progress, ownForecast: ownForecast, childRollups: childRollups)
        let estimate = forecast.remainingSeconds.map { max(worked + $0, worked) }
        let pace = service.historicalDailyPace(for: subtreeIDs(for: taskID), segmentsByTaskID: segmentsByTaskID, now: now)
        let sourceIDs = service.orderedUnique(forecast.sourceIDs)

        let rollup = TaskRollup(
            taskID: taskID,
            workedSeconds: worked,
            estimatedTotalSeconds: estimate,
            remainingSeconds: forecast.remainingSeconds,
            projectedDays: service.projectedDays(for: forecast.remainingSeconds, dailyAverageSeconds: pace?.averageSeconds),
            historicalDailyAverageSeconds: pace?.averageSeconds,
            historicalActiveDayCount: pace?.activeDayCount ?? 0,
            checklistProgress: progress,
            confidence: estimate == nil ? .none : confidence(task: task, ownForecast: ownForecast, childRollups: childRollups, estimate: estimate),
            reason: forecast.reason,
            forecastState: forecast.state,
            forecastSourceTaskIDs: sourceIDs,
            forecastSourceLabel: service.sourceLabel(for: sourceIDs, ownTaskID: taskID, hasOwnChecklist: progress.totalCount > 0)
        )
        cache[taskID] = rollup
        return rollup
    }

    private mutating func buildChildRollups(for taskID: UUID, visited: Set<UUID>) -> [TaskRollup] {
        (childrenByParent[taskID] ?? []).compactMap {
            build(taskID: $0.id, visited: visited.union([taskID]))
        }
    }

    private func checklistProgress(for taskID: UUID) -> ChecklistProgress {
        let items = checklistItemsByTaskID[taskID] ?? []
        return ChecklistProgress(
            taskID: taskID,
            totalCount: items.count,
            completedCount: items.filter(\.isCompleted).count
        )
    }

    private func resolvedForecast(
        task: TaskNode,
        progress: ChecklistProgress,
        ownForecast: OwnChecklistForecast,
        childRollups: [TaskRollup]
    ) -> TaskRollupForecastResolution {
        let childForecasts = childRollups.filter(\.isDisplayableForecast)
        let childRemaining = childForecasts.compactMap(\.remainingSeconds).reduce(0, +)
        let childSourceIDs = childForecasts.flatMap(\.forecastSourceTaskIDs)

        if forecastEligibleTaskIDs?.contains(task.id) == false {
            return .disabled
        }
        if task.status == .completed {
            return .completed(sourceIDs: (ownForecast.contributesSource ? [task.id] : []) + childSourceIDs)
        }
        if progress.totalCount > 0 {
            return resolutionForTaskWithChecklist(
                taskID: task.id,
                ownForecast: ownForecast,
                childRemaining: childRemaining,
                childSourceIDs: childSourceIDs
            )
        }
        if childForecasts.isEmpty {
            return .needsChecklist
        }
        return .aggregate(remainingSeconds: childRemaining, sourceIDs: childSourceIDs)
    }

    private func resolutionForTaskWithChecklist(
        taskID: UUID,
        ownForecast: OwnChecklistForecast,
        childRemaining: Int,
        childSourceIDs: [UUID]
    ) -> TaskRollupForecastResolution {
        guard let ownRemaining = ownForecast.remainingSeconds else {
            if childSourceIDs.isEmpty {
                return TaskRollupForecastResolution(
                    remainingSeconds: nil,
                    state: ownForecast.state,
                    sourceIDs: [],
                    reason: ownForecast.reason
                )
            }
            return .aggregate(remainingSeconds: childRemaining, sourceIDs: childSourceIDs)
        }

        let sourceIDs = [taskID] + childSourceIDs
        return TaskRollupForecastResolution(
            remainingSeconds: ownRemaining + childRemaining,
            state: childSourceIDs.isEmpty ? ownForecast.state : .aggregate,
            sourceIDs: sourceIDs,
            reason: childSourceIDs.isEmpty ? ownForecast.reason : aggregateReason(sourceIDs.count)
        )
    }

    private mutating func subtreeIDs(for taskID: UUID, visited: Set<UUID> = []) -> Set<UUID> {
        if let cached = subtreeCache[taskID] {
            return cached
        }
        guard !visited.contains(taskID) else {
            return []
        }

        var ids: Set<UUID> = [taskID]
        let nextVisited = visited.union([taskID])
        for child in childrenByParent[taskID] ?? [] {
            ids.formUnion(subtreeIDs(for: child.id, visited: nextVisited))
        }
        subtreeCache[taskID] = ids
        return ids
    }

    private func confidence(
        task: TaskNode,
        ownForecast: OwnChecklistForecast,
        childRollups: [TaskRollup],
        estimate: Int?
    ) -> ForecastConfidence {
        task.status == .completed ? .high : service.confidence(
            ownForecast: ownForecast,
            childRollups: childRollups.filter(\.isDisplayableForecast),
            estimate: estimate
        )
    }
}

private struct TaskRollupForecastResolution {
    let remainingSeconds: Int?
    let state: ForecastState
    let sourceIDs: [UUID]
    let reason: String

    static let disabled = TaskRollupForecastResolution(
        remainingSeconds: nil,
        state: .disabled,
        sourceIDs: [],
        reason: AppStrings.localized("forecast.reason.categoryDisabled")
    )

    static let needsChecklist = TaskRollupForecastResolution(
        remainingSeconds: nil,
        state: .needsChecklist,
        sourceIDs: [],
        reason: AppStrings.localized("forecast.reason.needsChecklist")
    )

    static func completed(sourceIDs: [UUID]) -> TaskRollupForecastResolution {
        TaskRollupForecastResolution(
            remainingSeconds: 0,
            state: .completed,
            sourceIDs: sourceIDs,
            reason: AppStrings.localized("forecast.reason.completed")
        )
    }

    static func aggregate(remainingSeconds: Int, sourceIDs: [UUID]) -> TaskRollupForecastResolution {
        TaskRollupForecastResolution(
            remainingSeconds: remainingSeconds,
            state: .aggregate,
            sourceIDs: sourceIDs,
            reason: aggregateReason(sourceIDs.count)
        )
    }
}

private func aggregateReason(_ sourceCount: Int) -> String {
    String(format: AppStrings.localized("forecast.reason.aggregate"), sourceCount)
}
