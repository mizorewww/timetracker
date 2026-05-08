import Foundation

struct OwnChecklistForecast {
    let estimatedTotalSeconds: Int?
    let remainingSeconds: Int?
    let state: ForecastState
    let confidence: ForecastConfidence
    let reason: String
    let contributesSource: Bool
}

extension TaskRollupService {
    func ownChecklistForecast(
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

    func sourceLabel(for sourceIDs: [UUID], ownTaskID: UUID, hasOwnChecklist: Bool) -> String? {
        let uniqueCount = sourceIDs.count
        guard uniqueCount > 0 else { return nil }
        if hasOwnChecklist, uniqueCount == 1, sourceIDs.first == ownTaskID {
            return AppStrings.localized("forecast.source.currentTask")
        }
        return String(format: AppStrings.localized("forecast.source.aggregate"), uniqueCount)
    }

    func orderedUnique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    func projectedDays(for remainingSeconds: Int?, dailyAverageSeconds: Int?) -> Double? {
        guard let remainingSeconds, remainingSeconds > 0 else { return 0 }
        guard let daily = dailyAverageSeconds, daily > 0 else { return nil }
        return max(0.1, Double(remainingSeconds) / Double(daily))
    }

    func historicalDailyPace(
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

    func confidence(ownForecast: OwnChecklistForecast?, childRollups: [TaskRollup], estimate: Int?) -> ForecastConfidence {
        guard estimate != nil else { return .none }
        let candidates = ([ownForecast?.confidence].compactMap { $0 } + childRollups.map(\.confidence)).filter { $0 != .none }
        if candidates.contains(.high) { return .high }
        if candidates.contains(.medium) { return .medium }
        return candidates.isEmpty ? .none : .low
    }
}
