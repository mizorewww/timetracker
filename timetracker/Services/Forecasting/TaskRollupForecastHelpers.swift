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
        if progress.totalCount > 0 && progress.completedCount == progress.totalCount {
            return OwnChecklistForecast(
                estimatedTotalSeconds: max(ownWorkedSeconds, 0),
                remainingSeconds: 0,
                state: .completed,
                confidence: .high,
                reason: AppStrings.localized("forecast.reason.completed"),
                contributesSource: true
            )
        }

        if let explicitEstimate = TaskEstimatePolicy.normalized(seconds: task.estimatedSeconds) {
            return OwnChecklistForecast(
                estimatedTotalSeconds: max(explicitEstimate, ownWorkedSeconds),
                remainingSeconds: max(0, explicitEstimate - ownWorkedSeconds),
                state: .ready,
                confidence: .medium,
                reason: AppStrings.localized("forecast.reason.explicitEstimate"),
                contributesSource: true
            )
        }

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

    func sourceLabel(
        sourceCount: Int,
        sampledSourceIDs: [UUID],
        ownTaskID: UUID,
        hasOwnSource: Bool
    ) -> String? {
        guard sourceCount > 0 else { return nil }
        if hasOwnSource, sourceCount == 1, sampledSourceIDs.first == ownTaskID {
            return AppStrings.localized("forecast.source.currentTask")
        }
        return String(format: AppStrings.localized("forecast.source.aggregate"), sourceCount)
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

    func confidence(ownForecast: OwnChecklistForecast?, childRollups: [TaskRollup], estimate: Int?) -> ForecastConfidence {
        guard estimate != nil else { return .none }
        let candidates = ([ownForecast?.confidence].compactMap { $0 } + childRollups.map(\.confidence)).filter { $0 != .none }
        if candidates.contains(.high) { return .high }
        if candidates.contains(.medium) { return .medium }
        return candidates.isEmpty ? .none : .low
    }
}
