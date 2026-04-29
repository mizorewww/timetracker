import Foundation

struct TaskRollupService {
    private let aggregationService = TimeAggregationService()

    private struct OwnChecklistForecast {
        let estimatedTotalSeconds: Int?
        let remainingSeconds: Int?
        let state: ForecastState
        let confidence: ForecastConfidence
        let reason: String
        let contributesSource: Bool
    }

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
        now: Date = Date()
    ) -> [UUID: TaskRollup] {
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let childrenByParent = Dictionary(grouping: tasks, by: \.parentID)
        let segmentsByTaskID = Dictionary(grouping: segments.filter { $0.deletedAt == nil }, by: \.taskID)
        var cache: [UUID: TaskRollup] = [:]
        var subtreeCache: [UUID: Set<UUID>] = [:]

        func subtreeIDs(for taskID: UUID, visited: Set<UUID> = []) -> Set<UUID> {
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

        func build(taskID: UUID, visited: Set<UUID>) -> TaskRollup? {
            if let cached = cache[taskID] {
                return cached
            }
            guard let task = taskByID[taskID], !visited.contains(taskID) else {
                return nil
            }

            let ownWorked = aggregationService.grossSeconds(segmentsByTaskID[taskID] ?? [], now: now)
            let progress = checklistProgress(for: taskID, checklistItems: checklistItems)
            let ownForecast = ownChecklistForecast(task: task, ownWorkedSeconds: ownWorked, progress: progress)
            let childRollups = (childrenByParent[taskID] ?? []).compactMap {
                build(taskID: $0.id, visited: visited.union([taskID]))
            }
            let childWorked = childRollups.reduce(0) { $0 + $1.workedSeconds }
            let childForecasts = childRollups.filter(\.isDisplayableForecast)
            let childRemainingValues = childForecasts.compactMap(\.remainingSeconds)
            let childRemaining = childRemainingValues.reduce(0, +)
            let childSourceIDs = childForecasts.flatMap(\.forecastSourceTaskIDs)
            let worked = ownWorked + childWorked
            let hasChildForecast = !childForecasts.isEmpty
            let hasOwnChecklist = progress.totalCount > 0
            let ownRemaining = ownForecast.remainingSeconds
            let remaining: Int?
            let forecastState: ForecastState
            let sourceIDs: [UUID]
            let reason: String

            if task.status == .completed {
                remaining = 0
                forecastState = .completed
                sourceIDs = (ownForecast.contributesSource ? [taskID] : []) + childSourceIDs
                reason = AppStrings.localized("forecast.reason.completed")
            } else if hasOwnChecklist {
                if let ownRemaining {
                    remaining = ownRemaining + childRemaining
                    forecastState = hasChildForecast ? .aggregate : ownForecast.state
                    sourceIDs = [taskID] + childSourceIDs
                    reason = hasChildForecast
                        ? String(format: AppStrings.localized("forecast.reason.aggregate"), sourceIDs.count)
                        : ownForecast.reason
                } else {
                    if hasChildForecast {
                        remaining = childRemaining
                        forecastState = .aggregate
                        sourceIDs = childSourceIDs
                        reason = String(format: AppStrings.localized("forecast.reason.aggregate"), sourceIDs.count)
                    } else {
                        remaining = nil
                        forecastState = ownForecast.state
                        sourceIDs = []
                        reason = ownForecast.reason
                    }
                }
            } else if hasChildForecast {
                remaining = childRemaining
                forecastState = .aggregate
                sourceIDs = childSourceIDs
                reason = String(format: AppStrings.localized("forecast.reason.aggregate"), sourceIDs.count)
            } else {
                remaining = nil
                forecastState = .needsChecklist
                sourceIDs = []
                reason = AppStrings.localized("forecast.reason.needsChecklist")
            }

            let estimate = remaining.map { max(worked + $0, worked) }
            let pace = historicalDailyPace(
                for: subtreeIDs(for: taskID),
                segmentsByTaskID: segmentsByTaskID,
                now: now
            )
            let projectedDays = projectedDays(for: remaining, dailyAverageSeconds: pace?.averageSeconds)
            let confidence = task.status == .completed ? .high : confidence(ownForecast: ownForecast, childRollups: childForecasts, estimate: estimate)
            let uniqueSourceIDs = orderedUnique(sourceIDs)
            let sourceLabel = sourceLabel(for: uniqueSourceIDs, ownTaskID: taskID, hasOwnChecklist: hasOwnChecklist)

            let rollup = TaskRollup(
                taskID: taskID,
                workedSeconds: worked,
                estimatedTotalSeconds: estimate,
                remainingSeconds: remaining,
                projectedDays: projectedDays,
                historicalDailyAverageSeconds: pace?.averageSeconds,
                historicalActiveDayCount: pace?.activeDayCount ?? 0,
                checklistProgress: progress,
                confidence: estimate == nil ? .none : confidence,
                reason: reason,
                forecastState: forecastState,
                forecastSourceTaskIDs: uniqueSourceIDs,
                forecastSourceLabel: sourceLabel
            )
            cache[taskID] = rollup
            return rollup
        }

        for task in tasks {
            _ = build(taskID: task.id, visited: [])
        }
        return cache
    }

    private func ownChecklistForecast(
        task: TaskNode,
        ownWorkedSeconds: Int,
        progress: ChecklistProgress
    ) -> OwnChecklistForecast {
        guard progress.totalCount > 0 else {
            return OwnChecklistForecast(
                estimatedTotalSeconds: nil,
                remainingSeconds: nil,
                state: .needsChecklist,
                confidence: .none,
                reason: AppStrings.localized("forecast.reason.needsChecklist"),
                contributesSource: false
            )
        }

        if task.status == .completed || progress.completedCount == progress.totalCount {
            return OwnChecklistForecast(
                estimatedTotalSeconds: max(ownWorkedSeconds, 0),
                remainingSeconds: 0,
                state: .completed,
                confidence: .high,
                reason: AppStrings.localized("forecast.reason.completed"),
                contributesSource: true
            )
        }

        guard progress.completedCount > 0 else {
            return OwnChecklistForecast(
                estimatedTotalSeconds: nil,
                remainingSeconds: nil,
                state: .needsCompletedItem,
                confidence: .none,
                reason: AppStrings.localized("forecast.reason.needsCompletedItem"),
                contributesSource: false
            )
        }

        guard ownWorkedSeconds > 0 else {
            return OwnChecklistForecast(
                estimatedTotalSeconds: nil,
                remainingSeconds: nil,
                state: .needsTrackedTime,
                confidence: .none,
                reason: AppStrings.localized("forecast.reason.needsTrackedTime"),
                contributesSource: false
            )
        }

        let remainingCount = max(0, progress.totalCount - progress.completedCount)
        let averagePerCompletedItem = Double(ownWorkedSeconds) / Double(progress.completedCount)
        let remaining = Int((averagePerCompletedItem * Double(remainingCount)).rounded())
        let confidence: ForecastConfidence = progress.completedCount >= 3 ? .high : .medium
        return OwnChecklistForecast(
            estimatedTotalSeconds: ownWorkedSeconds + remaining,
            remainingSeconds: remaining,
            state: .ready,
            confidence: confidence,
            reason: String(
                format: AppStrings.localized("forecast.reason.checklistDetail"),
                progress.completedCount,
                progress.totalCount,
                DurationFormatter.compact(Int(averagePerCompletedItem.rounded()))
            ),
            contributesSource: true
        )
    }

    private func sourceLabel(for sourceIDs: [UUID], ownTaskID: UUID, hasOwnChecklist: Bool) -> String? {
        let uniqueCount = sourceIDs.count
        guard uniqueCount > 0 else { return nil }
        if hasOwnChecklist, uniqueCount == 1, sourceIDs.first == ownTaskID {
            return AppStrings.localized("forecast.source.currentTask")
        }
        return String(format: AppStrings.localized("forecast.source.aggregate"), uniqueCount)
    }

    private func orderedUnique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func projectedDays(for remainingSeconds: Int?, dailyAverageSeconds: Int?) -> Double? {
        guard let remainingSeconds, remainingSeconds > 0 else { return 0 }
        guard let daily = dailyAverageSeconds, daily > 0 else { return nil }
        return max(0.1, Double(remainingSeconds) / Double(daily))
    }

    private func historicalDailyPace(
        for taskIDs: Set<UUID>,
        segmentsByTaskID: [UUID: [TimeSegment]],
        now: Date,
        calendar: Calendar = .current
    ) -> (averageSeconds: Int, activeDayCount: Int)? {
        guard !taskIDs.isEmpty else { return nil }

        var dayTotals: [Date: Int] = [:]
        for taskID in taskIDs {
            for segment in segmentsByTaskID[taskID] ?? [] {
                let end = segment.endedAt ?? now
                guard end > segment.startedAt else { continue }

                var cursor = calendar.startOfDay(for: segment.startedAt)
                while cursor < end {
                    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                    let sliceStart = max(segment.startedAt, cursor)
                    let sliceEnd = min(end, nextDay)
                    if sliceEnd > sliceStart {
                        dayTotals[cursor, default: 0] += Int(sliceEnd.timeIntervalSince(sliceStart))
                    }
                    cursor = nextDay
                }
            }
        }

        let activeTotals = dayTotals.values.filter { $0 > 0 }
        guard !activeTotals.isEmpty else { return nil }
        return (activeTotals.reduce(0, +) / activeTotals.count, activeTotals.count)
    }

    private func confidence(ownForecast: OwnChecklistForecast?, childRollups: [TaskRollup], estimate: Int?) -> ForecastConfidence {
        guard estimate != nil else { return .none }
        let candidates = ([ownForecast?.confidence].compactMap { $0 } + childRollups.map(\.confidence)).filter { $0 != .none }
        if candidates.contains(.high) { return .high }
        if candidates.contains(.medium) { return .medium }
        return candidates.isEmpty ? .none : .low
    }
}
