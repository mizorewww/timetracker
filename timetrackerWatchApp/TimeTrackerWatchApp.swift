import SwiftUI

@main
struct TimeTrackerWatchApp: App {
    @State private var store = WatchAppStore()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--watch-ui-audit-large-text") {
                WatchUIAuditRoot()
                    .environment(\.dynamicTypeSize, .accessibility3)
            } else if ProcessInfo.processInfo.arguments.contains(where: {
                $0.hasPrefix("--watch-ui-audit")
            }) {
                WatchUIAuditRoot()
            } else {
                dashboard
            }
            #else
            dashboard
            #endif
        }
    }

    private var dashboard: some View {
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
