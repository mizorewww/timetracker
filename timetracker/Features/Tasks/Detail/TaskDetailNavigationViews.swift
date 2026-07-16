import SwiftUI

private struct TaskDetailNavigationModifier: ViewModifier {
    let store: TimeTrackerStore
    let taskID: UUID
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @State private var isDeleteConfirmationPresented = false

    func body(content: Content) -> some View {
        content
            .navigationTitle(store.task(for: taskID)?.title ?? AppStrings.localized("task.detail.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if let task = store.task(for: taskID) {
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
                    store.deleteSelectedTask(taskID: taskID, preservingDestination: .tasks)
                }
                Button(AppStrings.cancel, role: .cancel) {}
            } message: {
                Text(.app("task.delete.confirm.message"))
            }
    }

    private func editButton(_ task: TaskNode) -> some View {
        Button {
            presentationRouter.presentEditTask(task, using: store)
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
                preservingDestination: .tasks,
                requestDelete: { isDeleteConfirmationPresented = true }
            )
        } label: {
            Label(AppStrings.localized("common.more"), systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("task.detail.more")
    }
}

extension View {
    func taskDetailNavigation(store: TimeTrackerStore, taskID: UUID) -> some View {
        modifier(TaskDetailNavigationModifier(store: store, taskID: taskID))
    }
}
