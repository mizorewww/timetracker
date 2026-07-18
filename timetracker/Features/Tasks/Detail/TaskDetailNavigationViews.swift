import SwiftUI

private struct TaskDetailNavigationModifier: ViewModifier {
    let store: TimeTrackerStore
    let taskID: UUID
    let isEditing: Bool
    let beginEditing: (TaskNode) -> Void
    let preservingDestination: TimeTrackerStore.DesktopDestination
    @State private var isDeleteConfirmationPresented = false

    func body(content: Content) -> some View {
        content
            .navigationTitle(store.task(for: taskID)?.title ?? AppStrings.localized("task.detail.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if !isEditing, let task = store.task(for: taskID) {
                    ToolbarItemGroup(placement: .primaryAction) {
                        editButton(task)
                        moreMenu(task)
                    }
                }
            }
            .confirmationDialog(
                AppStrings.localized("task.delete.confirm.title"),
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(AppStrings.delete, role: .destructive) {
                    store.deleteSelectedTask(
                        taskID: taskID,
                        preservingDestination: preservingDestination
                    )
                }
                Button(AppStrings.cancel, role: .cancel) {}
            } message: {
                Text(.app("task.delete.confirm.message"))
            }
    }

    private func editButton(_ task: TaskNode) -> some View {
        Button {
            beginEditing(task)
        } label: {
            Label(AppStrings.localized("task.detail.editor.expand"), systemImage: "pencil")
        }
        .accessibilityIdentifier("task.detail.edit")
    }

    private func moreMenu(_ task: TaskNode) -> some View {
        Menu {
            TaskContextMenu(
                store: store,
                task: task,
                preservingDestination: preservingDestination,
                editTask: { beginEditing(task) },
                requestDelete: { isDeleteConfirmationPresented = true }
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
