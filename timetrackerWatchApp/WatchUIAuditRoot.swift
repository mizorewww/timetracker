#if DEBUG
import SwiftUI

struct WatchUIAuditRoot: View {
    private let activeTimerID = UUID()
    private let taskID = UUID()
    private let feedbackTaskID = UUID()
    private let readingTaskID = UUID()
    private let failedCommandID = UUID()

    var body: some View {
        WatchDashboardView(
            snapshot: snapshot,
            isReachable: false,
            hasReceivedSnapshot: true,
            pendingCommands: [],
            failedCommands: showsFailure ? [failedCommand] : [],
            isSnapshotStale: false,
            hasConnectivityError: false,
            onStopTimer: { _ in },
            onStartTask: { _ in },
            onRetryCommand: { _ in },
            onDiscardCommand: { _ in }
        )
    }

    private var showsFailure: Bool {
        ProcessInfo.processInfo.arguments.contains("--watch-ui-audit")
    }

    private var snapshot: WatchStateSnapshot {
        WatchStateSnapshot(
            generatedAt: Date(),
            todayGrossSeconds: 0,
            todayWallSeconds: 0,
            activeTimers: [
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
