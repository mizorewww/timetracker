import SwiftUI

struct TaskForecastsContent: View {
    let store: TimeTrackerStore

    var body: some View {
        let displayedItems = store.forecastDisplayItems(limit: 6)

        if displayedItems.isEmpty {
            EmptyStateRow(title: AppStrings.localized("analytics.forecasts.empty"), icon: "checklist")
        } else {
            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    ForecastInfoButton()
                }

                VStack(spacing: 0) {
                    ForEach(displayedItems) { item in
                        if let task = store.task(for: item.taskID) {
                            ForecastAnalyticsRow(store: store, task: task, rollup: item.rollup)
                        }
                        if item.id != displayedItems.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct ForecastAnalyticsRow: View {
    let store: TimeTrackerStore
    let task: TaskNode
    let rollup: TaskRollup

    var body: some View {
        Button {
            store.openTaskDetail(task.id)
        } label: {
            HStack(spacing: 12) {
                TaskIcon(task: task, size: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    ProgressView(value: rollup.completionFraction)
                        .tint(Color(hex: task.colorHex) ?? .blue)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(rollup.remainingDisplayText)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text(daysText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityHint(AppStrings.localized("tasks.openDetail"))
    }

    private var daysText: String {
        rollup.projectedDays == nil ? rollup.forecastState.displayName : rollup.projectedDaysDisplayText
    }
}
