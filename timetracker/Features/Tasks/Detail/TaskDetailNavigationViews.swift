import SwiftUI

private struct TaskDetailNavigationModifier: ViewModifier {
    let store: TimeTrackerStore
    let taskID: UUID
    let preservingDestination: TimeTrackerStore.DesktopDestination
    @Environment(AppPresentationRouter.self) private var presentationRouter

    func body(content: Content) -> some View {
        content
            .navigationTitle(store.task(for: taskID)?.title ?? AppStrings.localized("task.detail.title"))
            .appInlineNavigationTitle()
            .toolbar {
                if let task = store.task(for: taskID) {
                    ToolbarItemGroup(placement: .primaryAction) {
                        if store.isTaskAvailableForTracking(task) {
                            addTimeButton(task)
                        }
                        moreMenu(task)
                    }
                }
            }
    }

    private func addTimeButton(_ task: TaskNode) -> some View {
        Button {
            presentationRouter.presentManualTime(taskID: task.id, using: store)
        } label: {
            Label(AppStrings.addTime, systemImage: "calendar.badge.plus")
        }
        .accessibilityIdentifier("task.detail.addTime")
    }

    private func moreMenu(_ task: TaskNode) -> some View {
        Menu {
            TaskMenuContent(
                store: store,
                task: task,
                preservingDestination: preservingDestination,
                surface: .pullDown
            )
        } label: {
            Label(AppStrings.localized("common.more"), systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("task.detail.more")
    }
}

extension View {
    func taskDetailNavigation(
        store: TimeTrackerStore,
        taskID: UUID,
        preservingDestination: TimeTrackerStore.DesktopDestination
    ) -> some View {
        modifier(
            TaskDetailNavigationModifier(
                store: store,
                taskID: taskID,
                preservingDestination: preservingDestination
            )
        )
    }
}
