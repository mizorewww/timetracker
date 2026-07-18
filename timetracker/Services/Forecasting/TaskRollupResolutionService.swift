import Foundation

struct TaskRollupForecastResolution {
    let remainingSeconds: Int?
    let state: ForecastState
    let sourceIDs: [UUID]
    let sourceCount: Int
    let reason: String

    static let disabled = TaskRollupForecastResolution(
        remainingSeconds: nil,
        state: .disabled,
        sourceIDs: [],
        sourceCount: 0,
        reason: AppStrings.localized("forecast.reason.categoryDisabled")
    )

    static let needsChecklist = TaskRollupForecastResolution(
        remainingSeconds: nil,
        state: .needsChecklist,
        sourceIDs: [],
        sourceCount: 0,
        reason: AppStrings.localized("forecast.reason.needsChecklist")
    )

    static func aggregate(remainingSeconds: Int, sourceIDs: [UUID], sourceCount: Int) -> Self {
        Self(
            remainingSeconds: remainingSeconds,
            state: .aggregate,
            sourceIDs: sourceIDs,
            sourceCount: sourceCount,
            reason: aggregateForecastReason(sourceCount)
        )
    }
}

struct TaskRollupResolutionService {
    static let maximumSampledSourceIDs = 32

    let service: TaskRollupService
    let forecastEligibleTaskIDs: Set<UUID>?

    func resolve(
        task: TaskNode,
        progress: ChecklistProgress,
        ownForecast: OwnChecklistForecast,
        childRollups: [TaskRollup]
    ) -> TaskRollupForecastResolution {
        let childForecasts = childRollups.filter(\.isDisplayableForecast)
        let childRemaining = childForecasts.compactMap(\.remainingSeconds).reduce(0, +)
        let childSourceCount = childForecasts.reduce(0) { $0 + $1.forecastSourceTaskCount }
        let childSourceIDs = sampledSourceIDs(from: childForecasts)

        if forecastEligibleTaskIDs?.contains(task.id) == false {
            return .disabled
        }
        if ownForecast.remainingSeconds != nil {
            return resolutionForTaskWithOwnForecast(
                taskID: task.id,
                ownForecast: ownForecast,
                childRemaining: childRemaining,
                childSourceIDs: childSourceIDs,
                childSourceCount: childSourceCount
            )
        }
        if progress.totalCount > 0 {
            if childSourceCount > 0 {
                return .aggregate(
                    remainingSeconds: childRemaining,
                    sourceIDs: childSourceIDs,
                    sourceCount: childSourceCount
                )
            }
            return TaskRollupForecastResolution(
                remainingSeconds: nil,
                state: ownForecast.state,
                sourceIDs: [],
                sourceCount: 0,
                reason: ownForecast.reason
            )
        }
        if childForecasts.isEmpty {
            return .needsChecklist
        }
        return .aggregate(
            remainingSeconds: childRemaining,
            sourceIDs: childSourceIDs,
            sourceCount: childSourceCount
        )
    }

    func confidence(
        ownForecast: OwnChecklistForecast,
        childRollups: [TaskRollup],
        estimate: Int?
    ) -> ForecastConfidence {
        service.confidence(
            ownForecast: ownForecast,
            childRollups: childRollups.filter(\.isDisplayableForecast),
            estimate: estimate
        )
    }

    private func resolutionForTaskWithOwnForecast(
        taskID: UUID,
        ownForecast: OwnChecklistForecast,
        childRemaining: Int,
        childSourceIDs: [UUID],
        childSourceCount: Int
    ) -> TaskRollupForecastResolution {
        guard let ownRemaining = ownForecast.remainingSeconds else {
            if childSourceCount == 0 {
                return TaskRollupForecastResolution(
                    remainingSeconds: nil,
                    state: ownForecast.state,
                    sourceIDs: [],
                    sourceCount: 0,
                    reason: ownForecast.reason
                )
            }
            return .aggregate(
                remainingSeconds: childRemaining,
                sourceIDs: childSourceIDs,
                sourceCount: childSourceCount
            )
        }

        let sourceIDs = Array(
            ([taskID] + childSourceIDs).prefix(Self.maximumSampledSourceIDs)
        )
        let sourceCount = 1 + childSourceCount
        return TaskRollupForecastResolution(
            remainingSeconds: ownRemaining + childRemaining,
            state: childSourceCount == 0 ? ownForecast.state : .aggregate,
            sourceIDs: sourceIDs,
            sourceCount: sourceCount,
            reason: childSourceCount == 0 ? ownForecast.reason : aggregateForecastReason(sourceCount)
        )
    }

    private func sampledSourceIDs(from rollups: [TaskRollup]) -> [UUID] {
        var sampled: [UUID] = []
        var seen = Set<UUID>()
        for rollup in rollups {
            for sourceID in rollup.forecastSourceTaskIDs
            where sampled.count < Self.maximumSampledSourceIDs && seen.insert(sourceID).inserted {
                sampled.append(sourceID)
            }
            if sampled.count == Self.maximumSampledSourceIDs { break }
        }
        return sampled
    }
}

private func aggregateForecastReason(_ sourceCount: Int) -> String {
    String(format: AppStrings.localized("forecast.reason.aggregate"), sourceCount)
}
