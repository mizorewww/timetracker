import SwiftUI

struct TaskForecastSummarySection: View {
    @ObservedObject var store: TimeTrackerStore

    private var forecasts: [ForecastDisplayItem] {
        let candidates = store.forecastDisplayItems()
        guard let selectedTaskID = store.selectedTaskID,
              let selectedItem = store.forecastDisplayItem(for: selectedTaskID) else {
            return Array(candidates.prefix(3))
        }

        let withoutSelected = candidates.filter { $0.taskID != selectedItem.taskID }
        return Array(([selectedItem] + withoutSelected).prefix(3))
    }

    var body: some View {
        if !forecasts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(title: AppStrings.localized("forecast.today.title"))
                    ForecastInfoButton()
                }
                ForecastExplanationCallout()

                VStack(spacing: 0) {
                    ForEach(forecasts) { item in
                        if let task = store.task(for: item.taskID) {
                            ForecastSummaryRow(store: store, task: task, rollup: item.rollup)
                            if item.taskID != forecasts.last?.taskID {
                                Divider().padding(.leading, 54)
                            }
                        }
                    }
                }
                .appCard(padding: 0)
            }
            .accessibilityIdentifier("home.forecasts")
        }
    }
}

private struct ForecastSummaryRow: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode
    let rollup: TaskRollup

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TaskIcon(task: task, size: 34)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if rollup.checklistProgress.totalCount > 0 {
                        Text(rollup.checklistProgress.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                Text(store.path(for: task))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: rollup.completionFraction)
                    .tint(Color(hex: task.colorHex) ?? .blue)
                if let sourceLabel = rollup.forecastSourceLabel {
                    Text(sourceLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(rollup.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let paceText = rollup.historicalPaceDisplayText {
                    Text(paceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                Text(remainingText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                Text(daysText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectTask(task.id)
        }
        .padding(14)
    }

    private var remainingText: String {
        rollup.remainingDisplayText
    }

    private var daysText: String {
        rollup.projectedDays == nil ? rollup.confidence.displayName : rollup.projectedDaysDisplayText
    }
}
