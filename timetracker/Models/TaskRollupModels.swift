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
    case disabled

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
        case .disabled:
            return AppStrings.localized("forecast.state.disabled")
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
        case .needsChecklist, .needsCompletedItem, .needsTrackedTime, .completed, .disabled:
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
