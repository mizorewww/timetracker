import SwiftUI

struct TaskDetailActionsView: View {
    let store: TimeTrackerStore
    let task: TaskNode
    let activeSegment: TimeSegment?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Section {
            if isAvailableForTracking || activeSegment != nil {
                actionLayout
                    .controlSize(.large)
                    .accessibilityIdentifier("task.detail.actions")
            }

            if completedWorkBlocker != nil {
                completedWorkUnavailableView
            } else if !store.isTaskVisible(task) {
                Label(AppStrings.localized("status.archived"), systemImage: "archivebox")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("task.detail.trackingUnavailable")
            }
        } footer: {
            if !store.isTaskVisible(task) {
                Text(.app("task.archived.trackingUnavailable"))
            }
        }
    }

    @ViewBuilder
    private var actionLayout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                timerAction
                if isAvailableForTracking {
                    manualTimeAction
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    timerAction
                    if isAvailableForTracking {
                        manualTimeAction
                    }
                }
                VStack(spacing: 10) {
                    timerAction
                    if isAvailableForTracking {
                        manualTimeAction
                    }
                }
            }
        }
    }

    private var isAvailableForTracking: Bool {
        store.isTaskAvailableForTracking(task)
    }

    private var completedWorkBlocker: TaskNode? {
        store.completedWorkBlocker(for: task)
    }

    private var completedWorkUnavailableMessage: String {
        guard let completedWorkBlocker, completedWorkBlocker.id != task.id else {
            return AppStrings.localized("task.completed.workUnavailable")
        }
        return String(
            format: AppStrings.localized("task.completed.ancestorUnavailableFormat"),
            completedWorkBlocker.title
        )
    }

    private var reopenActionTitle: String {
        guard let completedWorkBlocker, completedWorkBlocker.id != task.id else {
            return AppStrings.localized("task.action.reopen")
        }
        return String(
            format: AppStrings.localized("task.action.reopenAncestorFormat"),
            completedWorkBlocker.title
        )
    }

    private var completedWorkUnavailableView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                AppStrings.localized("task.status.blockedByCompletion"),
                systemImage: "pause.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(.orange)

            Text(completedWorkUnavailableMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                store.reopenTaskForWork(task.id)
            } label: {
                Label(reopenActionTitle, systemImage: "arrow.uturn.backward.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("task.detail.reopen")
    }

    @ViewBuilder
    private var timerAction: some View {
        if let activeSegment {
            Button {
                store.stop(segment: activeSegment)
            } label: {
                AppActionLabel(
                    title: AppStrings.localized("timer.action.stop"),
                    systemImage: "stop.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        } else if isAvailableForTracking {
            Button {
                store.startTask(task)
            } label: {
                AppActionLabel(title: AppStrings.startTimer, systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var manualTimeAction: some View {
        Button {
            store.presentManualTime(taskID: task.id)
        } label: {
            AppActionLabel(title: AppStrings.addTime, systemImage: "calendar.badge.plus")
        }
        .buttonStyle(.bordered)
    }
}
