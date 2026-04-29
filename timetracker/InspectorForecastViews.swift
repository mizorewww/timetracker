import SwiftUI

struct TaskForecastPanel: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode

    var body: some View {
        if let rollup = forecastRollup {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(.app("forecast.panel.title"))
                        .font(.headline)
                    ForecastInfoButton()
                    Spacer()
                }

                VStack(spacing: 10) {
                    if let displayedTask, displayedTask.id != task.id {
                        Text(String(format: AppStrings.localized("forecast.showingChildFormat"), displayedTask.title))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    InfoRow(title: AppStrings.localized("forecast.worked"), value: DurationFormatter.compact(rollup.workedSeconds))
                    if rollup.isDisplayableForecast {
                        InfoRow(title: AppStrings.localized("forecast.estimatedTotal"), value: estimateText(for: rollup))
                        InfoRow(title: AppStrings.localized("forecast.remaining"), value: remainingText(for: rollup))
                        InfoRow(title: AppStrings.localized("forecast.projectedDays"), value: daysText(for: rollup))
                        if let paceText = rollup.historicalPaceDisplayText {
                            InfoRow(title: AppStrings.localized("forecast.historyPace"), value: paceText)
                        }
                        InfoRow(title: AppStrings.localized("forecast.confidence"), value: rollup.confidence.displayName)
                        if let sourceLabel = rollup.forecastSourceLabel {
                            InfoRow(title: AppStrings.localized("forecast.source"), value: sourceLabel)
                        }
                        Text(rollup.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(rollup.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .appCard(padding: 14)
            }
        }
    }

    private var displayItem: ForecastDisplayItem? {
        store.forecastDisplayItem(for: task.id)
    }

    private var displayedTask: TaskNode? {
        guard let displayItem else { return task }
        return store.task(for: displayItem.taskID) ?? task
    }

    private var forecastRollup: TaskRollup? {
        displayItem?.rollup ?? store.rollup(for: task.id)
    }

    private func estimateText(for rollup: TaskRollup) -> String {
        rollup.estimatedTotalSeconds.map(DurationFormatter.compact) ?? AppStrings.localized("forecast.noEstimate")
    }

    private func remainingText(for rollup: TaskRollup) -> String {
        rollup.remainingDisplayText
    }

    private func daysText(for rollup: TaskRollup) -> String {
        rollup.projectedDaysDisplayText
    }
}
