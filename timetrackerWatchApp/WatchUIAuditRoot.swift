#if DEBUG
import SwiftUI

struct WatchUIAuditRoot: View {
    private let activeTimerID = UUID()
    private let taskID = UUID()
    private let feedbackTaskID = UUID()
    private let readingTaskID = UUID()
    private let failedCommandID = UUID()
    private let pendingCommandID = UUID()

    var body: some View {
        WatchDashboardView(
            snapshot: snapshot,
            isReachable: arguments.contains("--watch-ui-audit-reachable"),
            hasReceivedSnapshot: true,
            pendingCommands: pendingCommands,
            failedCommands: showsFailure ? [failedCommand] : [],
            isSnapshotStale: arguments.contains("--watch-ui-audit-stale"),
            hasConnectivityError: arguments.contains(
                "--watch-ui-audit-connection-error"
            ),
            onStopTimer: { _ in },
            onStartTask: { _ in },
            onRetryCommand: { _ in },
            onDiscardCommand: { _ in }
        )
    }

    private var arguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    private var showsFailure: Bool {
        arguments.contains("--watch-ui-audit") ||
            arguments.contains("--watch-ui-audit-failure")
    }

    private var hidesActiveTimer: Bool {
        arguments.contains("--watch-ui-audit-no-active")
    }

    private var showsPendingCommand: Bool {
        arguments.contains("--watch-ui-audit-pending")
    }

    private var pendingCommands: [WatchTimerCommand] {
        guard showsPendingCommand else { return [] }
        return [
            WatchTimerCommand(
                id: pendingCommandID,
                type: .startTask,
                taskID: feedbackTaskID,
                segmentID: nil,
                issuedAt: Date(),
                deviceID: "watch-ui-audit"
            )
        ]
    }

    private var snapshot: WatchStateSnapshot {
        WatchStateSnapshot(
            generatedAt: Date(),
            todayGrossSeconds: 0,
            todayWallSeconds: 0,
            activeTimers: hidesActiveTimer ? [] : [
                WatchActiveTimerSnapshot(
                    id: activeTimerID,
                    taskID: taskID,
                    title: "Prepare quarterly presentation",
                    path: "Work · Planning",
                    startedAt: Date().addingTimeInterval(-5_423),
                    colorHex: "0A84FF",
                    iconName: "rectangle.on.rectangle"
                )
            ],
            recentTasks: [
                WatchRecentTaskSnapshot(
                    taskID: taskID,
                    title: "Prepare quarterly presentation",
                    path: "Work · Planning",
                    colorHex: "0A84FF",
                    iconName: "rectangle.on.rectangle"
                ),
                WatchRecentTaskSnapshot(
                    taskID: feedbackTaskID,
                    title: "Review customer feedback",
                    path: "Work",
                    colorHex: "30D158",
                    iconName: "text.bubble"
                ),
                WatchRecentTaskSnapshot(
                    taskID: readingTaskID,
                    title: "Read design notes",
                    path: "Personal",
                    colorHex: "BF5AF2",
                    iconName: "book"
                )
            ]
        )
    }

    private var failedCommand: WatchFailedCommand {
        let command = WatchTimerCommand(
            id: failedCommandID,
            type: .startTask,
            taskID: taskID,
            segmentID: nil,
            issuedAt: Date().addingTimeInterval(-30),
            deviceID: "watch-ui-audit"
        )
        return WatchFailedCommand(
            command: command,
            result: WatchCommandResult(
                commandID: failedCommandID,
                status: .timeout,
                completedAt: Date(),
                relatedID: taskID,
                failureCode: "audit"
            )
        )
    }
}
#endif
