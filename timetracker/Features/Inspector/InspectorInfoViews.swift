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
                InfoRow(title: AppStrings.localized("task.field.status"), value: activeStatusText, badge: activeStatusText == AppStrings.running)
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

    private var activeStatusText: String {
        store.activeSegments.contains { $0.taskID == task.id } ? AppStrings.running : task.status.displayName
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    var badge: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(minWidth: 54, maxWidth: 86, alignment: .leading)
            Spacer()
            Text(value)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .font(badge ? .caption.weight(.medium) : .subheadline)
                .foregroundStyle(badge ? .green : .primary)
                .padding(.horizontal, badge ? 8 : 0)
                .padding(.vertical, badge ? 4 : 0)
                .background(badge ? Color.green.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .font(.subheadline)
    }
}
