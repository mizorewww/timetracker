import Foundation

struct ChecklistProgress: Equatable {
    let taskID: UUID
    let totalCount: Int
    let completedCount: Int

    var fraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var label: String {
        "\(completedCount)/\(totalCount)"
    }
}

enum ForecastConfidence: String, CaseIterable {
    case high
    case medium
    case low
    case none

    var displayName: String {
        switch self {
        case .high: return AppStrings.localized("forecast.confidence.high")
        case .medium: return AppStrings.localized("forecast.confidence.medium")
        case .low: return AppStrings.localized("forecast.confidence.low")
        case .none: return AppStrings.localized("forecast.confidence.none")
        }
    }
}

enum ForecastState: String, CaseIterable {
    case ready
    case needsChecklist
    case needsCompletedItem
    case needsTrackedTime
    case completed
    case aggregate

    var displayName: String {
        switch self {
        case .ready:
            return AppStrings.localized("forecast.state.ready")
        case .needsChecklist:
            return AppStrings.localized("forecast.state.needsChecklist")
        case .needsCompletedItem:
            return AppStrings.localized("forecast.state.needsCompletedItem")
        case .needsTrackedTime:
            return AppStrings.localized("forecast.state.needsTrackedTime")
        case .completed:
            return AppStrings.localized("forecast.state.completed")
        case .aggregate:
            return AppStrings.localized("forecast.state.aggregate")
        }
    }
}

struct TaskRollup: Identifiable, Equatable {
    let taskID: UUID
    let workedSeconds: Int
    let estimatedTotalSeconds: Int?
    let remainingSeconds: Int?
    let projectedDays: Double?
    let historicalDailyAverageSeconds: Int?
    let historicalActiveDayCount: Int
    let checklistProgress: ChecklistProgress
    let confidence: ForecastConfidence
    let reason: String
    let forecastState: ForecastState
    let forecastSourceTaskIDs: [UUID]
    let forecastSourceLabel: String?

    var id: UUID { taskID }

    var completionFraction: Double {
        if checklistProgress.totalCount > 0 {
            return checklistProgress.fraction
        }
        guard let estimatedTotalSeconds, estimatedTotalSeconds > 0 else {
            return 0
        }
        return min(1, max(0, Double(workedSeconds) / Double(estimatedTotalSeconds)))
    }

    var isDisplayableForecast: Bool {
        switch forecastState {
        case .ready, .aggregate:
            return estimatedTotalSeconds != nil && remainingSeconds != nil && confidence != .none
        case .needsChecklist, .needsCompletedItem, .needsTrackedTime, .completed:
            return false
        }
    }

    var remainingDisplayText: String {
        guard let remainingSeconds else {
            return AppStrings.localized("forecast.noEstimate")
        }
        return String(format: AppStrings.localized("forecast.remainingFormat"), DurationFormatter.compact(remainingSeconds))
    }

    var projectedDaysDisplayText: String {
        guard let projectedDays else {
            return AppStrings.localized("forecast.noEstimate")
        }
        return String(format: AppStrings.localized("forecast.daysFormat"), projectedDays)
    }

    var historicalPaceDisplayText: String? {
        guard let historicalDailyAverageSeconds, historicalDailyAverageSeconds > 0, historicalActiveDayCount > 0 else {
            return nil
        }
        return String(
            format: AppStrings.localized("forecast.historyPaceFormat"),
            DurationFormatter.compact(historicalDailyAverageSeconds),
            historicalActiveDayCount
        )
    }
}

struct ForecastingService {
    private let aggregationService = TimeAggregationService()

    func recentDailyAvailableSeconds(segments: [TimeSegment], now: Date = Date(), days: Int = 14) -> Int {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
        guard let start = calendar.date(byAdding: .day, value: -max(1, days), to: end) else { return 0 }
        let interval = DateInterval(start: start, end: end)
        let recent = segments.filter { segment in
            segment.deletedAt == nil &&
            segment.startedAt < interval.end &&
            (segment.endedAt ?? now) > interval.start
        }
        guard !recent.isEmpty else { return 0 }

        var dayTotals: [Date: Int] = [:]
        for segment in recent {
            guard let clipped = clippedInterval(for: segment, in: interval, now: now) else { continue }
            var cursor = calendar.startOfDay(for: clipped.start)
            while cursor < clipped.end {
                let next = min(calendar.date(byAdding: .day, value: 1, to: cursor) ?? clipped.end, clipped.end)
                let dayStart = max(cursor, clipped.start)
                let seconds = max(0, Int(next.timeIntervalSince(dayStart)))
                dayTotals[cursor, default: 0] += seconds
                cursor = next
            }
        }

        let activeDays = dayTotals.values.filter { $0 > 0 }
        guard !activeDays.isEmpty else { return 0 }
        return activeDays.reduce(0, +) / activeDays.count
    }

    private func clippedInterval(for segment: TimeSegment, in interval: DateInterval, now: Date) -> DateInterval? {
        let end = segment.endedAt ?? now
        let start = max(segment.startedAt, interval.start)
        let clippedEnd = min(end, interval.end)
        guard clippedEnd > start else { return nil }
        return DateInterval(start: start, end: clippedEnd)
    }
}

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

            let ownWorked = aggregationService.grossSeconds(segments.filter { $0.taskID == taskID }, now: now)
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
            let pace = historicalDailyPace(for: subtreeIDs(for: taskID), segments: segments, now: now)
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
        segments: [TimeSegment],
        now: Date,
        calendar: Calendar = .current
    ) -> (averageSeconds: Int, activeDayCount: Int)? {
        guard !taskIDs.isEmpty else { return nil }

        var dayTotals: [Date: Int] = [:]
        for segment in segments where taskIDs.contains(segment.taskID) && segment.deletedAt == nil {
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

struct ForecastDisplayItem: Identifiable, Equatable {
    let taskID: UUID
    let rollup: TaskRollup

    var id: UUID { taskID }
}

struct ForecastDisplayService {
    func displayItems(tasks: [TaskNode], rollups: [UUID: TaskRollup], limit: Int? = nil) -> [ForecastDisplayItem] {
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let childrenByParent = Dictionary(grouping: visibleTasks(tasks), by: \.parentID)
        let roots = (childrenByParent[nil] ?? []).sorted(by: taskSort)
        var emitted = Set<UUID>()
        var items: [ForecastDisplayItem] = []

        func append(_ item: ForecastDisplayItem) {
            guard emitted.insert(item.taskID).inserted else { return }
            items.append(item)
        }

        func visit(_ task: TaskNode) {
            guard isVisible(task), let rollup = rollups[task.id] else {
                for child in (childrenByParent[task.id] ?? []).sorted(by: taskSort) {
                    visit(child)
                }
                return
            }

            if rollup.isDisplayableForecast {
                if rollup.checklistProgress.totalCount > 0 {
                    append(ForecastDisplayItem(taskID: task.id, rollup: rollup))
                    return
                }

                let sourceIDs = rollup.forecastSourceTaskIDs.filter { sourceID in
                    guard let source = taskByID[sourceID] else { return false }
                    return isVisible(source)
                }
                if sourceIDs.count == 1,
                   let sourceID = sourceIDs.first,
                   let sourceTask = taskByID[sourceID],
                   let sourceRollup = rollups[sourceTask.id],
                   sourceRollup.isDisplayableForecast {
                    append(ForecastDisplayItem(taskID: sourceTask.id, rollup: sourceRollup))
                    return
                }

                append(ForecastDisplayItem(taskID: task.id, rollup: rollup))
                return
            }

            for child in (childrenByParent[task.id] ?? []).sorted(by: taskSort) {
                visit(child)
            }
        }

        for root in roots {
            visit(root)
        }

        let sorted = items.sorted {
            let leftRemaining = $0.rollup.remainingSeconds ?? 0
            let rightRemaining = $1.rollup.remainingSeconds ?? 0
            if leftRemaining != rightRemaining {
                return leftRemaining > rightRemaining
            }
            let leftUpdated = taskByID[$0.taskID]?.updatedAt ?? .distantPast
            let rightUpdated = taskByID[$1.taskID]?.updatedAt ?? .distantPast
            return leftUpdated > rightUpdated
        }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

    func displayItem(for taskID: UUID, tasks: [TaskNode], rollups: [UUID: TaskRollup]) -> ForecastDisplayItem? {
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        guard let task = taskByID[taskID], isVisible(task), let rollup = rollups[taskID] else { return nil }
        if rollup.isDisplayableForecast, rollup.checklistProgress.totalCount > 0 {
            return ForecastDisplayItem(taskID: taskID, rollup: rollup)
        }
        if rollup.checklistProgress.totalCount > 0 {
            return nil
        }
        if rollup.isDisplayableForecast,
           rollup.forecastSourceTaskIDs.count > 1 {
            return ForecastDisplayItem(taskID: taskID, rollup: rollup)
        }
        if let sourceID = rollup.forecastSourceTaskIDs.first,
           let source = taskByID[sourceID],
           isVisible(source),
           let sourceRollup = rollups[sourceID],
           sourceRollup.isDisplayableForecast {
            return ForecastDisplayItem(taskID: sourceID, rollup: sourceRollup)
        }
        return nil
    }

    private func visibleTasks(_ tasks: [TaskNode]) -> [TaskNode] {
        tasks.filter(isVisible)
    }

    private func isVisible(_ task: TaskNode) -> Bool {
        task.deletedAt == nil && task.status != .archived && task.status != .completed
    }

    private func taskSort(_ lhs: TaskNode, _ rhs: TaskNode) -> Bool {
        if lhs.sortOrder == rhs.sortOrder {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.sortOrder < rhs.sortOrder
    }
}
