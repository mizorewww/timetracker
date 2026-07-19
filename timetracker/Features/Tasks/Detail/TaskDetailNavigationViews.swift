import SwiftUI

private struct TaskDetailNavigationModifier: ViewModifier {
    let store: TimeTrackerStore
    let taskID: UUID
    let isEditing: Bool
    let beginEditing: (TaskNode) -> Void
    let preservingDestination: TimeTrackerStore.DesktopDestination
    @Environment(AppPresentationRouter.self) private var presentationRouter

    func body(content: Content) -> some View {
        content
            .navigationTitle(store.task(for: taskID)?.title ?? AppStrings.localized("task.detail.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if !isEditing, let task = store.task(for: taskID) {
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
            TaskContextMenu(
                store: store,
                task: task,
                preservingDestination: preservingDestination,
                editTask: { beginEditing(task) }
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
        isEditing: Bool,
        beginEditing: @escaping (TaskNode) -> Void,
        preservingDestination: TimeTrackerStore.DesktopDestination
    ) -> some View {
        modifier(
            TaskDetailNavigationModifier(
                store: store,
                taskID: taskID,
                isEditing: isEditing,
                beginEditing: beginEditing,
                preservingDestination: preservingDestination
            )
        )
    }
}
