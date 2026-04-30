import SwiftUI

struct TaskContextMenu: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode
    var preservingDestination: TimeTrackerStore.DesktopDestination? = nil

    var body: some View {
        Button {
            store.startTask(task)
        } label: {
            Label(AppStrings.localized("task.action.startTimer"), systemImage: "play.fill")
        }

        Button {
            store.presentNewTask(parentID: task.id, preservingDestination: preservingDestination)
        } label: {
            Label(AppStrings.localized("task.action.newSubtask"), systemImage: "plus")
        }

        Button {
            store.presentManualTime(taskID: task.id)
        } label: {
            Label(AppStrings.localized("task.action.addManualTime"), systemImage: "calendar.badge.plus")
        }

        Menu(AppStrings.localized("task.status.menu")) {
            ForEach(TaskStatus.editableCases, id: \.self) { status in
                Button {
                    store.setTaskStatus(status, taskID: task.id)
                } label: {
                    Label(status.displayName, systemImage: status.symbolName)
                }
            }
        }

        Divider()

        Button {
            store.presentEditTask(task)
        } label: {
            Label(AppStrings.edit, systemImage: "pencil")
        }

        Button {
            store.archiveSelectedTask(taskID: task.id)
        } label: {
            Label(AppStrings.localized("task.action.archive"), systemImage: "archivebox")
        }

        Button(role: .destructive) {
            store.deleteSelectedTask(taskID: task.id, preservingDestination: preservingDestination)
        } label: {
            Label(AppStrings.localized("task.action.softDelete"), systemImage: "trash")
        }
    }
}

enum TaskRowSwipeLabelStyle {
    case titleAndIcon
    case iconOnly
}

struct TaskRowSwipeActions: ViewModifier {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode
    var labelStyle: TaskRowSwipeLabelStyle = .titleAndIcon
    var preservingDestination: TimeTrackerStore.DesktopDestination?

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading) {
                Button {
                    store.startTask(task)
                } label: {
                    actionLabel(AppStrings.localized("task.swipe.start"), systemImage: "play.fill")
                }
                .tint(.blue)

                Button {
                    store.presentNewTask(parentID: task.id, preservingDestination: preservingDestination)
                } label: {
                    actionLabel(AppStrings.localized("task.swipe.subtask"), systemImage: "plus")
                }
                .tint(.green)
            }
            .swipeActions(edge: .trailing) {
                Button {
                    store.presentEditTask(task)
                } label: {
                    actionLabel(AppStrings.edit, systemImage: "pencil")
                }
                .tint(.gray)

                Button(role: .destructive) {
                    store.deleteSelectedTask(taskID: task.id, preservingDestination: preservingDestination)
                } label: {
                    actionLabel(AppStrings.delete, systemImage: "trash")
                }
            }
    }

    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String) -> some View {
        switch labelStyle {
        case .titleAndIcon:
            Label(title, systemImage: systemImage)
        case .iconOnly:
            Image(systemName: systemImage)
                .accessibilityLabel(title)
        }
    }
}

extension View {
    func taskRowSwipeActions(
        store: TimeTrackerStore,
        task: TaskNode,
        labelStyle: TaskRowSwipeLabelStyle = .titleAndIcon,
        preservingDestination: TimeTrackerStore.DesktopDestination? = nil
    ) -> some View {
        modifier(
            TaskRowSwipeActions(
                store: store,
                task: task,
                labelStyle: labelStyle,
                preservingDestination: preservingDestination
            )
        )
    }
}
