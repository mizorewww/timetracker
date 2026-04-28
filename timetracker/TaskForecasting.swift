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

struct TaskRollup: Identifiable, Equatable {
    let taskID: UUID
    let workedSeconds: Int
    let estimatedTotalSeconds: Int?
    let remainingSeconds: Int?
    let projectedDays: Int?
    let checklistProgress: ChecklistProgress
    let confidence: ForecastConfidence
    let reason: String

    var id: UUID { taskID }

    var completionFraction: Double {
        guard let estimatedTotalSeconds, estimatedTotalSeconds > 0 else {
            return checklistProgress.fraction
        }
        return min(1, max(0, Double(workedSeconds) / Double(estimatedTotalSeconds)))
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

    func fallbackEstimatedTotalSeconds(
        for task: TaskNode,
        tasks: [TaskNode],
        segments: [TimeSegment],
        now: Date = Date()
    ) -> (seconds: Int, confidence: ForecastConfidence, reason: String)? {
        let taskWorked = grossSeconds(for: task.id, segments: segments, now: now)
        if taskWorked > 0 {
            return (
                max(taskWorked * 2, taskWorked + 30 * 60),
                .low,
                AppStrings.localized("forecast.reason.ownHistory")
            )
        }

        let completedSiblings = tasks.filter {
            $0.parentID == task.parentID &&
            $0.id != task.id &&
            $0.status == .completed
        }
        let siblingDurations = completedSiblings
            .map { grossSeconds(for: $0.id, segments: segments, now: now) }
            .filter { $0 > 0 }
        if !siblingDurations.isEmpty {
            return (
                siblingDurations.reduce(0, +) / siblingDurations.count,
                .low,
                AppStrings.localized("forecast.reason.siblings")
            )
        }

        let completedDurations = tasks
            .filter { $0.status == .completed }
            .map { grossSeconds(for: $0.id, segments: segments, now: now) }
            .filter { $0 > 0 }
        if !completedDurations.isEmpty {
            return (
                completedDurations.reduce(0, +) / completedDurations.count,
                .low,
                AppStrings.localized("forecast.reason.global")
            )
        }

        return nil
    }

    private func grossSeconds(for taskID: UUID, segments: [TimeSegment], now: Date) -> Int {
        aggregationService.grossSeconds(segments.filter { $0.taskID == taskID }, now: now)
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
    private let forecastingService = ForecastingService()

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

        func build(taskID: UUID, visited: Set<UUID>) -> TaskRollup? {
            if let cached = cache[taskID] {
                return cached
            }
            guard let task = taskByID[taskID], !visited.contains(taskID) else {
                return nil
            }

            let ownWorked = aggregationService.grossSeconds(segments.filter { $0.taskID == taskID }, now: now)
            let progress = checklistProgress(for: taskID, checklistItems: checklistItems)
            let ownEstimate = ownEstimatedTotal(
                task: task,
                ownWorkedSeconds: ownWorked,
                progress: progress,
                tasks: tasks,
                segments: segments,
                now: now
            )
            let childRollups = (childrenByParent[taskID] ?? []).compactMap {
                build(taskID: $0.id, visited: visited.union([taskID]))
            }
            let childWorked = childRollups.reduce(0) { $0 + $1.workedSeconds }
            let childEstimateValues = childRollups.compactMap(\.estimatedTotalSeconds)
            let childEstimate = childEstimateValues.isEmpty ? nil : childEstimateValues.reduce(0, +)
            let worked = ownWorked + childWorked
            let rawEstimate = combineEstimate(ownEstimate?.seconds, childEstimate: childEstimate, hasChildren: !childRollups.isEmpty)
            let estimate = task.status == .completed ? max(rawEstimate ?? worked, worked) : rawEstimate
            let remaining: Int? = task.status == .completed ? 0 : estimate.map { max(0, $0 - worked) }
            let projectedDays = projectedDays(for: remaining, segments: segments, now: now)
            let confidence = confidence(ownEstimate: ownEstimate?.confidence, childRollups: childRollups, estimate: estimate)
            let reason = ownEstimate?.reason ?? childRollups.first(where: { $0.confidence != .none })?.reason ?? AppStrings.localized("forecast.reason.insufficient")

            let rollup = TaskRollup(
                taskID: taskID,
                workedSeconds: worked,
                estimatedTotalSeconds: estimate,
                remainingSeconds: remaining,
                projectedDays: projectedDays,
                checklistProgress: progress,
                confidence: estimate == nil ? .none : confidence,
                reason: estimate == nil ? AppStrings.localized("forecast.reason.insufficient") : reason
            )
            cache[taskID] = rollup
            return rollup
        }

        for task in tasks {
            _ = build(taskID: task.id, visited: [])
        }
        return cache
    }

    private func ownEstimatedTotal(
        task: TaskNode,
        ownWorkedSeconds: Int,
        progress: ChecklistProgress,
        tasks: [TaskNode],
        segments: [TimeSegment],
        now: Date
    ) -> (seconds: Int, confidence: ForecastConfidence, reason: String)? {
        if progress.totalCount > 0, progress.completedCount > 0, ownWorkedSeconds > 0 {
            let estimated = Int((Double(ownWorkedSeconds) / Double(progress.completedCount)) * Double(progress.totalCount))
            let confidence: ForecastConfidence = progress.completedCount >= 3 ? .high : .medium
            return (
                max(estimated, ownWorkedSeconds),
                confidence,
                String(format: AppStrings.localized("forecast.reason.checklist"), progress.completedCount)
            )
        }

        if let estimatedSeconds = task.estimatedSeconds, estimatedSeconds > 0 {
            return (estimatedSeconds, .medium, AppStrings.localized("forecast.reason.manualEstimate"))
        }

        return forecastingService.fallbackEstimatedTotalSeconds(for: task, tasks: tasks, segments: segments, now: now)
    }

    private func combineEstimate(_ ownEstimate: Int?, childEstimate: Int?, hasChildren: Bool) -> Int? {
        switch (ownEstimate, childEstimate, hasChildren) {
        case let (own?, child?, _):
            return own + child
        case let (own?, nil, _):
            return own
        case let (nil, child?, true):
            return child
        default:
            return nil
        }
    }

    private func projectedDays(for remainingSeconds: Int?, segments: [TimeSegment], now: Date) -> Int? {
        guard let remainingSeconds, remainingSeconds > 0 else { return 0 }
        let daily = forecastingService.recentDailyAvailableSeconds(segments: segments, now: now)
        guard daily > 0 else { return nil }
        return max(1, Int(ceil(Double(remainingSeconds) / Double(daily))))
    }

    private func confidence(ownEstimate: ForecastConfidence?, childRollups: [TaskRollup], estimate: Int?) -> ForecastConfidence {
        guard estimate != nil else { return .none }
        let candidates = ([ownEstimate].compactMap { $0 } + childRollups.map(\.confidence)).filter { $0 != .none }
        if candidates.contains(.high) { return .high }
        if candidates.contains(.medium) { return .medium }
        return candidates.isEmpty ? .low : .low
    }
}
