import SwiftUI

struct TaskForecastsCard: View {
    @ObservedObject var store: TimeTrackerStore

    private var forecastItems: [ForecastDisplayItem] {
        store.forecastDisplayItems(limit: 6)
    }

    var body: some View {
        AnalyticsChartCard(title: AppStrings.localized("analytics.forecasts.title"), subtitle: AppStrings.localized("analytics.forecasts.subtitle")) {
            if forecastItems.isEmpty {
                EmptyStateRow(title: AppStrings.localized("analytics.forecasts.empty"), icon: "checklist")
            } else {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 8) {
                        ForecastExplanationCallout()
                        ForecastInfoButton()
                    }

                    VStack(spacing: 0) {
                        ForEach(forecastItems) { item in
                            if let task = store.task(for: item.taskID) {
                                ForecastAnalyticsRow(store: store, task: task, rollup: item.rollup)
                            }
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
    let task: TaskNode
    let rollup: TaskRollup

    var body: some View {
        HStack(spacing: 12) {
            TaskIcon(task: task, size: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(rollup.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let sourceLabel = rollup.forecastSourceLabel {
                    Text(sourceLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let paceText = rollup.historicalPaceDisplayText {
                    Text(paceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ProgressView(value: rollup.completionFraction)
                    .tint(Color(hex: task.colorHex) ?? .blue)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(rollup.remainingDisplayText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(daysText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectTask(task.id)
        }
        .padding(.vertical, 10)
    }

    private var daysText: String {
        rollup.projectedDays == nil ? rollup.forecastState.displayName : rollup.projectedDaysDisplayText
    }
}
