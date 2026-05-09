import Foundation

extension TimeTrackerStore {
    func handleWatchCommand(_ command: WatchTimerCommand) {
        do {
            guard let modelContext else { throw StoreError.notConfigured }
            let result = try WatchCommandProcessor().process(
                command,
                allowParallelTimers: preferences.allowParallelTimers,
                context: modelContext
            )
            guard result.isProcessed else { return }
            let event = StoreDomainEvent.ledgerChanged(
                taskID: command.taskID,
                dateInterval: nil,
                isVisible: true
            )
            try refresh(plan: refreshPlanner.plan(after: [event]))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func watchStateSnapshot(now: Date = Date()) -> WatchStateSnapshot {
        let activeTaskIDs = Set(activeSegments.map(\.taskID))
        let widgetSnapshot = WidgetSnapshotCache.snapshot(
            activeSegments: activeSegments,
            taskByID: taskByID,
            taskParentPathByID: taskParentPathByID,
            recentTasks: frequentRecentTasks(excluding: activeTaskIDs, limit: 3),
            todayGrossSeconds: todayGrossSeconds(now: now),
            todayWallSeconds: todayWallSeconds(now: now),
            generatedAt: now
        )
        return WatchStateSnapshot(widgetSnapshot: widgetSnapshot)
    }

    func syncWatchSnapshotIfAvailable(now: Date = Date()) {
        let snapshot = watchStateSnapshot(now: now)
        #if os(iOS) && canImport(WatchConnectivity)
        WatchConnectivityBridge.shared.updateApplicationContext(snapshot)
        WatchConnectivityBridge.shared.sendReachableMessage(snapshot)
        #else
        _ = snapshot
        #endif
    }
}
