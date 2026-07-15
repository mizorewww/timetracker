import SwiftUI

struct WatchTaskListView: View {
    let tasks: [WatchRecentTaskSnapshot]
    let pendingCommands: [WatchTimerCommand]
    let failedCommands: [WatchFailedCommand]
    let onStartTask: (UUID) -> Void
    let onRetryCommand: (UUID) -> Void

    var body: some View {
        List {
            ForEach(tasks) { task in
                WatchTaskActionRow(
                    task: task,
                    pendingCommands: pendingCommands,
                    failedCommands: failedCommands,
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
    let pendingCommands: [WatchTimerCommand]
    let failedCommands: [WatchFailedCommand]
    let onStartTask: (UUID) -> Void
    let onRetryCommand: (UUID) -> Void

    var body: some View {
        let failedCommand = failedStartCommand
        WatchTaskShortcutRow(
            task: task,
            commandState: rowState(
                isPending: isStartPending,
                hasFailed: failedCommand != nil
            ),
            action: {
                if let failedCommand {
                    onRetryCommand(failedCommand.id)
                } else {
                    onStartTask(task.taskID)
                }
            }
        )
    }

    private var isStartPending: Bool {
        pendingCommands.contains { $0.type == .startTask && $0.taskID == task.taskID }
    }

    private var failedStartCommand: WatchFailedCommand? {
        failedCommands.first {
            $0.command.type == .startTask && $0.command.taskID == task.taskID
        }
    }

    private func rowState(isPending: Bool, hasFailed: Bool) -> WatchRowCommandState {
        if isPending { return .pending }
        if hasFailed { return .failed }
        return .idle
    }
}
