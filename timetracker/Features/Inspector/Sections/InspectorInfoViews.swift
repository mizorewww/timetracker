import SwiftUI

struct InspectorInfoGrid: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.app("task.section.info"))
                .font(.headline)

            VStack(spacing: 10) {
                InfoRow(title: AppStrings.localized("task.field.path"), value: store.path(for: task))
                InfoStatusRow(task: task, isRunning: store.activeSegments.contains { $0.taskID == task.id })
                InfoRow(
                    title: AppStrings.localized("task.field.total"),
                    value: DurationFormatter.compact(store.rollup(for: task.id)?.workedSeconds ?? store.secondsForTaskTotalRollup(task))
                )
                InfoRow(title: AppStrings.localized("task.field.today"), value: DurationFormatter.compact(store.secondsForTaskTodayRollup(task)))
                InfoRow(title: AppStrings.localized("task.field.week"), value: DurationFormatter.compact(store.secondsForTaskThisWeekRollup(task)))
            }
            .appCard(padding: 14)
        }
    }

}

struct InfoStatusRow: View {
    let task: TaskNode
    let isRunning: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(AppStrings.localized("task.field.status"))
                .foregroundStyle(.secondary)
                .frame(minWidth: 54, maxWidth: 86, alignment: .leading)
            Spacer()
            if isRunning {
                RunningStatusBadge()
            } else {
                TaskStatusBadge(status: task.status)
            }
        }
        .font(.subheadline)
    }
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(minWidth: 54, maxWidth: 86, alignment: .leading)
            Spacer()
            Text(value)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
    }
}
