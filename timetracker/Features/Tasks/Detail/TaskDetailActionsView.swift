import SwiftUI

struct TaskDetailActionsView: View {
    let store: TimeTrackerStore
    let task: TaskNode
    let activeSegment: TimeSegment?
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Section {
            if isAvailableForTracking || activeSegment != nil {
                actionLayout
                    .controlSize(.large)
                    .accessibilityIdentifier("task.detail.actions")
            }

            if !store.isTaskVisible(task) {
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
            presentationRouter.presentManualTime(taskID: task.id, using: store)
        } label: {
            AppActionLabel(title: AppStrings.addTime, systemImage: "calendar.badge.plus")
        }
        .buttonStyle(.bordered)
    }
}
