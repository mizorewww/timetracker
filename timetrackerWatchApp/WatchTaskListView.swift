import SwiftUI

struct WatchTaskListView: View {
    let tasks: [WatchRecentTaskSnapshot]
    let commandIndex: WatchCommandPresentationIndex
    let onStartTask: (UUID) -> Void
    let onRetryCommand: (UUID) -> Void

    var body: some View {
        List {
            ForEach(tasks) { task in
                let command = commandIndex.startTask(task.taskID)
                WatchTaskActionRow(
                    task: task,
                    command: command,
                    onStartTask: onStartTask,
                    onRetryCommand: onRetryCommand
                )
            }
        }
        .navigationTitle("watch.tasks.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WatchTaskActionRow: View {
    let task: WatchRecentTaskSnapshot
    let command: WatchRowCommandPresentation
    let onStartTask: (UUID) -> Void
    let onRetryCommand: (UUID) -> Void

    var body: some View {
        WatchTaskShortcutRow(
            task: task,
            commandState: command.state,
            action: {
                if let retryCommandID = command.retryCommandID {
                    onRetryCommand(retryCommandID)
                } else {
                    onStartTask(task.taskID)
                }
            }
        )
    }
}
