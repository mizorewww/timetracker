import SwiftUI

@main
struct TimeTrackerWatchApp: App {
    @StateObject private var store = WatchAppStore()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView(
                snapshot: store.snapshot,
                isReachable: store.isReachable,
                onStopTimer: store.stopTimer,
                onStartTask: store.startTask
            )
            .task {
                store.activate()
            }
        }
    }
}
