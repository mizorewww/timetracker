import SwiftUI

struct TaskContextMenu: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode

    var body: some View {
        Button {
            store.startTask(task)
        } label: {
            Label(AppStrings.localized("task.action.startTimer"), systemImage: "play.fill")
        }

        Button {
            store.presentNewTask(parentID: task.id)
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
            store.deleteSelectedTask(taskID: task.id)
        } label: {
            Label(AppStrings.localized("task.action.softDelete"), systemImage: "trash")
        }
    }
}
