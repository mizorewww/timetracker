import SwiftUI

@main
struct TimeTrackerWatchApp: App {
    @State private var store = WatchAppStore()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView(
                snapshot: store.snapshot,
                isReachable: store.isReachable,
                hasReceivedSnapshot: store.hasReceivedSnapshot,
                pendingCommands: store.pendingCommands,
                failedCommands: store.failedCommands,
                isSnapshotStale: store.isSnapshotStale,
                hasConnectivityError: store.hasConnectivityError,
                onStopTimer: store.stopTimer,
                onStartTask: store.startTask,
                onRetryCommand: store.retryCommand,
                onDiscardCommand: store.discardCommand
            )
            .task {
                store.activate()
            }
        }
    }
}
