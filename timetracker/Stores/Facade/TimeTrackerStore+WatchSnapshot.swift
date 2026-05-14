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
        let watchTasks = watchTaskShortcuts()
        let widgetSnapshot = WidgetSnapshotCache.snapshot(
            activeSegments: activeSegments,
            taskByID: taskByID,
            taskParentPathByID: taskParentPathByID,
            recentTasks: [],
            todayGrossSeconds: todayGrossSeconds(now: now),
            todayWallSeconds: todayWallSeconds(now: now),
            generatedAt: now
        )
        return WatchStateSnapshot(
            generatedAt: widgetSnapshot.generatedAt,
            todayGrossSeconds: widgetSnapshot.todayGrossSeconds,
            todayWallSeconds: widgetSnapshot.todayWallSeconds,
            activeTimers: widgetSnapshot.activeTimers.map {
                WatchActiveTimerSnapshot(
                    id: $0.id,
                    taskID: $0.taskID,
                    title: $0.title,
                    path: $0.path,
                    startedAt: $0.startedAt,
                    colorHex: $0.colorHex,
                    iconName: $0.iconName
                )
            },
            recentTasks: watchTasks.map {
                WatchRecentTaskSnapshot(
                    taskID: $0.id,
                    title: $0.title,
                    path: taskParentPathByID[$0.id] ?? "",
                    colorHex: $0.colorHex,
                    iconName: $0.iconName
                )
            }
        )
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

    private func watchTaskShortcuts() -> [TaskNode] {
        let availableTasks = tasks.filter {
            $0.deletedAt == nil && $0.status != .archived
        }
        let pinnedTasks = preferences.quickStartTaskIDs
            .compactMap { taskID in availableTasks.first { $0.id == taskID } }

        let pinnedIDs = Set(pinnedTasks.map(\.id))
        let recentFillTasks = frequentRecentTasks(
            excluding: pinnedIDs,
            limit: availableTasks.count
        )
        let rankedIDs = Set((pinnedTasks + recentFillTasks).map(\.id))
        let remainingTasks = availableTasks
            .filter { !rankedIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsPath = taskPathByID[lhs.id] ?? lhs.title
                let rhsPath = taskPathByID[rhs.id] ?? rhs.title
                if lhsPath.localizedStandardCompare(rhsPath) == .orderedSame {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhsPath.localizedStandardCompare(rhsPath) == .orderedAscending
            }

        return pinnedTasks + recentFillTasks + remainingTasks
    }
}
