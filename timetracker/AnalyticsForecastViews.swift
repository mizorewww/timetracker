import SwiftUI

struct TaskForecastsCard: View {
    @ObservedObject var store: TimeTrackerStore

    private var forecastItems: [AnalyticsForecastItem] {
        store.tasks.compactMap { task -> AnalyticsForecastItem? in
            guard task.deletedAt == nil,
                  task.status != .archived,
                  task.status != .completed,
                  let rollup = store.rollup(for: task.id),
                  rollup.isDisplayableForecast else {
                return nil
            }
            return AnalyticsForecastItem(task: task, rollup: rollup)
        }
        .sorted {
            ($0.rollup.remainingSeconds ?? 0) > ($1.rollup.remainingSeconds ?? 0)
        }
        .prefix(6)
        .map { $0 }
    }

    var body: some View {
        AnalyticsChartCard(title: AppStrings.localized("analytics.forecasts.title"), subtitle: AppStrings.localized("analytics.forecasts.subtitle")) {
            if forecastItems.isEmpty {
                EmptyStateRow(title: AppStrings.localized("analytics.forecasts.empty"), icon: "checklist")
            } else {
                VStack(spacing: 12) {
                    ForecastExplanationCallout()

                    VStack(spacing: 0) {
                        ForEach(forecastItems) { item in
                            ForecastAnalyticsRow(store: store, item: item)
                            if item.id != forecastItems.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ForecastAnalyticsRow: View {
    @ObservedObject var store: TimeTrackerStore
    let item: AnalyticsForecastItem

    var body: some View {
        HStack(spacing: 12) {
            TaskIcon(task: item.task, size: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.task.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(item.rollup.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let paceText = item.rollup.historicalPaceDisplayText {
                    Text(paceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ProgressView(value: item.rollup.completionFraction)
                    .tint(Color(hex: item.task.colorHex) ?? .blue)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(item.rollup.remainingDisplayText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(daysText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectTask(item.task.id)
        }
        .padding(.vertical, 10)
    }

    private var daysText: String {
        item.rollup.projectedDays == nil ? item.rollup.confidence.displayName : item.rollup.projectedDaysDisplayText
    }
}

private struct AnalyticsForecastItem: Identifiable {
    let task: TaskNode
    let rollup: TaskRollup

    var id: UUID { task.id }
}
