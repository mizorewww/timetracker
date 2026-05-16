import SwiftUI

struct HomeSelectedTaskSummaryCard: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        if let task = store.selectedTask {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(AppStrings.localized("task.snapshot"), systemImage: "smallcircle.filled.circle")
                        .foregroundStyle(.blue)
                    Spacer()
                    if store.activeSegments.contains(where: { $0.taskID == task.id }) {
                        RunningStatusBadge(compact: false)
                    } else {
                        TaskStatusBadge(status: task.status, compact: false)
                    }
                }

                Text(task.title)
                    .font(.title3.weight(.semibold))
                Text(store.path(for: task))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    HomeSummaryStat(
                        title: AppStrings.localized("task.field.total"),
                        value: DurationFormatter.compact(store.rollup(for: task.id)?.workedSeconds ?? store.secondsForTaskTotalRollup(task))
                    )
                    Divider()
                    HomeSummaryStat(title: AppStrings.localized("task.field.today"), value: DurationFormatter.compact(store.secondsForTaskTodayRollup(task)))
                }

                if !store.children(of: task).isEmpty,
                   let rollup = store.rollup(for: task.id),
                   rollup.isDisplayableForecast {
                    Divider()
                    HStack {
                        HomeSummaryStat(title: AppStrings.localized("forecast.remaining"), value: rollup.remainingSeconds.map(DurationFormatter.compact) ?? AppStrings.localized("forecast.noEstimate"))
                        Divider()
                        HomeSummaryStat(title: AppStrings.localized("forecast.projectedDays"), value: rollup.projectedDaysDisplayText)
                    }
                }

                Text(task.notes ?? AppStrings.localized("task.notes.empty"))
                    .font(.subheadline)
                    .foregroundStyle(task.notes == nil ? .secondary : .primary)
                    .foregroundStyle(.secondary)
            }
            .appCard(padding: 18)
        }
    }
}

private struct HomeSummaryStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}
