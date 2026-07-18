import SwiftUI

enum WatchTaskListKind {
    case quickStart
    case allTasks

    var emptyTitle: String {
        switch self {
        case .quickStart:
            String(localized: "watch.quickStart.empty.title")
        case .allTasks:
            String(localized: "watch.tasks.empty.title")
        }
    }

    var emptyMessage: String {
        switch self {
        case .quickStart:
            String(localized: "watch.quickStart.empty.message")
        case .allTasks:
            String(localized: "watch.tasks.empty.message")
        }
    }

    var emptySystemImage: String {
        switch self {
        case .quickStart:
            "bolt.fill"
        case .allTasks:
            "list.bullet"
        }
    }
}

struct WatchTaskListView: View {
    let kind: WatchTaskListKind
    let tasks: [WatchRecentTaskSnapshot]
    let activeTaskIDs: Set<UUID>
    let hasReceivedSnapshot: Bool
    let commandIndex: WatchCommandPresentationIndex
    let onStartTask: (UUID) -> Void
    let onRetryCommand: (UUID) -> Void
    let onShowActiveTimers: () -> Void

    var body: some View {
        List {
            if tasks.isEmpty {
                WatchEmptyState(
                    title: emptyTitle,
                    message: emptyMessage,
                    systemImage: emptySystemImage
                )
            } else {
                ForEach(tasks) { task in
                    let command = commandIndex.startTask(task.taskID)
                    WatchTaskActionRow(
                        task: task,
                        command: command,
                        isRunning: activeTaskIDs.contains(task.taskID),
                        onStartTask: onStartTask,
                        onRetryCommand: onRetryCommand,
                        onShowActiveTimers: onShowActiveTimers
                    )
                }
            }
        }
    }

    private var emptyTitle: String {
        hasReceivedSnapshot
            ? kind.emptyTitle
            : String(localized: "watch.status.waiting")
    }

    private var emptyMessage: String {
        hasReceivedSnapshot
            ? kind.emptyMessage
            : String(localized: "watch.status.waiting.message")
    }

    private var emptySystemImage: String {
        hasReceivedSnapshot ? kind.emptySystemImage : "iphone.and.arrow.forward"
    }
}

struct WatchTaskActionRow: View {
    let task: WatchRecentTaskSnapshot
    let command: WatchRowCommandPresentation
    let isRunning: Bool
    let onStartTask: (UUID) -> Void
    let onRetryCommand: (UUID) -> Void
    let onShowActiveTimers: () -> Void

    var body: some View {
        WatchTaskShortcutRow(
            task: task,
            commandState: command.state,
            isRunning: isRunning,
            action: {
                if let retryCommandID = command.retryCommandID {
                    onRetryCommand(retryCommandID)
                } else if isRunning {
                    onShowActiveTimers()
                } else {
                    onStartTask(task.taskID)
                }
            }
        )
    }
}
