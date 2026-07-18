import Foundation

private struct WatchRankedTaskProjection {
    let rank: Int
    let snapshot: WatchRecentTaskSnapshot
    let textByteCount: Int
}

extension TimeTrackerStore {
    func watchStateSnapshot(now: Date = Date()) -> WatchStateSnapshot {
        let watchTasks = rankedTrackableTasks()
        let availableTaskIDs = Set(watchTasks.map(\.id))
        var quickStartRankByTaskID: [UUID: Int] = [:]
        for taskID in preferences.quickStartTaskIDs
        where availableTaskIDs.contains(taskID) {
            guard quickStartRankByTaskID[taskID] == nil,
                  quickStartRankByTaskID.count <
                    WatchTransportLimits.maximumQuickStartTasks else {
                continue
            }
            quickStartRankByTaskID[taskID] = quickStartRankByTaskID.count
        }
        let widgetSnapshot = WidgetSnapshotCache.snapshot(
            activeSegments: activeSegments,
            taskByID: taskByID,
            taskParentPathByID: taskParentPathByID,
            recentTasks: [],
            todayGrossSeconds: todayGrossSeconds(now: now),
            todayWallSeconds: todayWallSeconds(now: now),
            generatedAt: now
        )
        let activeTimers = widgetSnapshot.activeTimers.map {
            WatchActiveTimerSnapshot(
                id: $0.id,
                taskID: $0.taskID,
                title: $0.title,
                path: $0.path,
                startedAt: $0.startedAt,
                colorHex: $0.colorHex,
                iconName: $0.iconName
            )
        }
        var remainingTextBytes = WatchTransportLimits.maximumSnapshotTextBytes
        for timer in activeTimers {
            remainingTextBytes -= WatchTransportLimits.textByteCount(
                title: timer.title,
                path: timer.path,
                colorHex: timer.colorHex,
                iconName: timer.iconName
            )
        }

        let projections = watchTasks.enumerated().map { rank, task in
            let snapshot = WatchRecentTaskSnapshot(
                taskID: task.id,
                title: WatchTransportLimits.boundedUTF8Prefix(
                    task.title,
                    maximumUTF8Bytes: WatchTransportLimits.maximumProjectedTitleBytes
                ),
                path: WatchTransportLimits.boundedUTF8Prefix(
                    taskParentPathByID[task.id] ?? "",
                    maximumUTF8Bytes: WatchTransportLimits.maximumProjectedPathBytes
                ),
                colorHex: WatchTransportLimits.boundedProjectedStyleValue(task.colorHex),
                iconName: WatchTransportLimits.boundedProjectedStyleValue(task.iconName),
                quickStartRank: quickStartRankByTaskID[task.id],
                allTasksRank: nil
            )
            return WatchRankedTaskProjection(
                rank: rank,
                snapshot: snapshot,
                textByteCount: WatchTransportLimits.textByteCount(
                    title: snapshot.title,
                    path: snapshot.path,
                    colorHex: snapshot.colorHex,
                    iconName: snapshot.iconName
                )
            )
        }
        let projectionByTaskID = Dictionary(
            uniqueKeysWithValues: projections.map { ($0.snapshot.taskID, $0) }
        )
        let quickStartProjections = quickStartRankByTaskID
            .sorted { $0.value < $1.value }
            .compactMap { projectionByTaskID[$0.key] }
        let legacyOrderedProjections = legacyWatchTaskOrder()
            .compactMap { projectionByTaskID[$0.id] }
        let activeTaskIDs = Set(activeTimers.map(\.taskID))
        let activeTaskProjections = activeTaskIDs.compactMap {
            projectionByTaskID[$0]
        }.sorted { $0.rank < $1.rank }
        let legacyQuickStartProjections = Array(
            legacyOrderedProjections
                .filter { activeTaskIDs.contains($0.snapshot.taskID) == false }
                .prefix(WatchTransportLimits.legacyQuickStartTaskLimit)
        )
        var selectedProjections: [WatchRankedTaskProjection] = []
        var selectedTaskIDs: Set<UUID> = []

        func include(_ projection: WatchRankedTaskProjection) {
            guard selectedProjections.count < WatchTransportLimits.maximumRecentTasks,
                  selectedTaskIDs.contains(projection.snapshot.taskID) == false,
                  projection.textByteCount <= remainingTextBytes else {
                return
            }
            selectedTaskIDs.insert(projection.snapshot.taskID)
            selectedProjections.append(projection)
            remainingTextBytes -= projection.textByteCount
        }

        activeTaskProjections.forEach(include)
        quickStartProjections.forEach(include)
        legacyQuickStartProjections.forEach(include)
        projections.forEach(include)
        let selectedProjectionByTaskID = Dictionary(
            uniqueKeysWithValues: selectedProjections.map {
                ($0.snapshot.taskID, $0)
            }
        )
        let legacySelectedProjections = legacyOrderedProjections.compactMap {
            selectedProjectionByTaskID[$0.snapshot.taskID]
        }
        let legacySelectedTaskIDs = Set(
            legacySelectedProjections.map(\.snapshot.taskID)
        )
        let wireOrderedProjections = legacySelectedProjections +
            selectedProjections.filter {
                legacySelectedTaskIDs.contains($0.snapshot.taskID) == false
            }
        let allTasksRankByTaskID = Dictionary(
            uniqueKeysWithValues: selectedProjections
            .sorted { $0.rank < $1.rank }
            .enumerated()
            .map { ($0.element.snapshot.taskID, $0.offset) }
        )
        let quickStartRankBySelectedTaskID = Dictionary(
            uniqueKeysWithValues: selectedProjections
                .filter { $0.snapshot.quickStartRank != nil }
                .sorted {
                    ($0.snapshot.quickStartRank ?? .max) <
                        ($1.snapshot.quickStartRank ?? .max)
                }
                .enumerated()
                .map { ($0.element.snapshot.taskID, $0.offset) }
        )
        let recentTasks = wireOrderedProjections.map { projection in
            var snapshot = projection.snapshot
            snapshot.quickStartRank =
                quickStartRankBySelectedTaskID[snapshot.taskID]
            snapshot.allTasksRank = allTasksRankByTaskID[snapshot.taskID]
            return snapshot
        }

        return WatchStateSnapshot(
            generatedAt: widgetSnapshot.generatedAt,
            todayGrossSeconds: widgetSnapshot.todayGrossSeconds,
            todayWallSeconds: widgetSnapshot.todayWallSeconds,
            activeTimers: activeTimers,
            recentTasks: recentTasks
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

    /// Keep the legacy pinned-first wire order so an older Watch app continues
    /// to derive the same Quick Start rows while newer builds use allTasksRank.
    private func legacyWatchTaskOrder() -> [TaskNode] {
        let availableTasks = tasks.filter(isTaskAvailableForTracking)
        let pinnedTasks = preferences.quickStartTaskIDs.compactMap { taskID in
            availableTasks.first { $0.id == taskID }
        }
        let pinnedIDs = Set(pinnedTasks.map(\.id))
        let recentFillTasks = frequentRecentTasks(
            excluding: pinnedIDs,
            limit: availableTasks.count
        )
        let rankedIDs = Set((pinnedTasks + recentFillTasks).map(\.id))
        let remainingTasks = availableTasks
            .filter { rankedIDs.contains($0.id) == false }
            .sorted { lhs, rhs in
                let lhsPath = taskPathByID[lhs.id] ?? lhs.title
                let rhsPath = taskPathByID[rhs.id] ?? rhs.title
                let comparison = lhsPath.localizedStandardCompare(rhsPath)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        return pinnedTasks + recentFillTasks + remainingTasks
    }

}
