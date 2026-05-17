import SwiftUI

struct TaskDetailHeader: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode
    let snapshot: TaskAnalyticsSnapshot
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                TaskIcon(task: task, size: 42)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(task.title)
                            .font(.title2.weight(.semibold))
                            .lineLimit(2)
                        if store.activeSegments.contains(where: { $0.taskID == task.id }) {
                            RunningStatusBadge()
                        } else {
                            TaskStatusBadge(status: task.status)
                        }
                    }

                    Text(store.path(for: task))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button(action: edit) {
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(AppStrings.localized("task.detail.editor.expand"))
            }

            HStack(spacing: 10) {
                Button {
                    store.startTask(task)
                } label: {
                    AppActionLabel(title: AppStrings.startTimer, systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    store.presentManualTime(taskID: task.id)
                } label: {
                    AppActionLabel(title: AppStrings.addTime, systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
            }

            if snapshot.overview.grossSeconds == 0 {
                Text(.app("task.detail.emptyAnalysis"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .appCard()
    }
}
