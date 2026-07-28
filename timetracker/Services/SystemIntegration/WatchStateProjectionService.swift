import Foundation

private nonisolated struct WatchRankedTaskProjection {
    let rank: Int
    let snapshot: WatchRecentTaskSnapshot
    let textByteCount: Int
}

/// Builds the bounded, backward-compatible Watch transport value from already
/// loaded facts. It owns the single source of truth for selection priority,
/// byte budgeting, rank metadata, and legacy wire order.
nonisolated struct WatchStateProjectionService {
    func snapshot(
        widgetSnapshot: WidgetSnapshot,
        rankedTasks: [TaskNode],
        legacyOrderedTasks: [TaskNode],
        taskParentPathByID: [UUID: String],
        quickStartTaskIDs: [UUID]
    ) -> WatchStateSnapshot {
        let availableTaskIDs = Set(rankedTasks.map(\.id))
        var quickStartRankByTaskID: [UUID: Int] = [:]
        for taskID in quickStartTaskIDs
            where availableTaskIDs.contains(taskID)
        {
            guard quickStartRankByTaskID[taskID] == nil,
                  quickStartRankByTaskID.count <
                  WatchTransportLimits.maximumQuickStartTasks
            else {
                continue
            }
            quickStartRankByTaskID[taskID] =
                quickStartRankByTaskID.count
        }

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
        var remainingTextBytes =
            WatchTransportLimits.maximumSnapshotTextBytes
        for timer in activeTimers {
            remainingTextBytes -= WatchTransportLimits.textByteCount(
                title: timer.title,
                path: timer.path,
                colorHex: timer.colorHex,
                iconName: timer.iconName
            )
        }

        let projections = rankedTasks.enumerated().map {
            rank,
            task in
            let snapshot = WatchRecentTaskSnapshot(
                taskID: task.id,
                title: WatchTransportLimits.boundedUTF8Prefix(
                    task.title,
                    maximumUTF8Bytes:
                    WatchTransportLimits.maximumProjectedTitleBytes
                ),
                path: WatchTransportLimits.boundedUTF8Prefix(
                    taskParentPathByID[task.id] ?? "",
                    maximumUTF8Bytes:
                    WatchTransportLimits.maximumProjectedPathBytes
                ),
                colorHex:
                WatchTransportLimits.boundedProjectedStyleValue(
                    task.colorHex
                ),
                iconName:
                WatchTransportLimits.boundedProjectedStyleValue(
                    task.iconName
                ),
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
            uniqueKeysWithValues: projections.map {
                ($0.snapshot.taskID, $0)
            }
        )
        let quickStartProjections = quickStartRankByTaskID
            .sorted { $0.value < $1.value }
            .compactMap { projectionByTaskID[$0.key] }
        let legacyOrderedProjections = legacyOrderedTasks.compactMap {
            projectionByTaskID[$0.id]
        }
        let activeTaskIDs = Set(activeTimers.map(\.taskID))
        let activeTaskProjections = activeTaskIDs.compactMap {
            projectionByTaskID[$0]
        }.sorted {
            $0.rank < $1.rank
        }
        let legacyQuickStartProjections = Array(
            legacyOrderedProjections
                .filter {
                    activeTaskIDs.contains($0.snapshot.taskID) == false
                }
                .prefix(
                    WatchTransportLimits.legacyQuickStartTaskLimit
                )
        )
        var selectedProjections: [WatchRankedTaskProjection] = []
        var selectedTaskIDs = Set<UUID>()

        func include(_ projection: WatchRankedTaskProjection) {
            guard selectedProjections.count <
                WatchTransportLimits.maximumRecentTasks,
                selectedTaskIDs.contains(
                    projection.snapshot.taskID
                ) == false,
                projection.textByteCount <= remainingTextBytes
            else {
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
        let legacySelectedProjections =
            legacyOrderedProjections.compactMap {
                selectedProjectionByTaskID[$0.snapshot.taskID]
            }
        let legacySelectedTaskIDs = Set(
            legacySelectedProjections.map(\.snapshot.taskID)
        )
        let wireOrderedProjections = legacySelectedProjections +
            selectedProjections.filter {
                legacySelectedTaskIDs.contains(
                    $0.snapshot.taskID
                ) == false
            }
        let allTasksRankByTaskID = Dictionary(
            uniqueKeysWithValues: selectedProjections
                .sorted { $0.rank < $1.rank }
                .enumerated()
                .map {
                    ($0.element.snapshot.taskID, $0.offset)
                }
        )
        let quickStartRankBySelectedTaskID = Dictionary(
            uniqueKeysWithValues: selectedProjections
                .filter { $0.snapshot.quickStartRank != nil }
                .sorted {
                    ($0.snapshot.quickStartRank ?? .max) <
                        ($1.snapshot.quickStartRank ?? .max)
                }
                .enumerated()
                .map {
                    ($0.element.snapshot.taskID, $0.offset)
                }
        )
        let recentTasks = wireOrderedProjections.map {
            projection in
            var snapshot = projection.snapshot
            snapshot.quickStartRank =
                quickStartRankBySelectedTaskID[snapshot.taskID]
            snapshot.allTasksRank =
                allTasksRankByTaskID[snapshot.taskID]
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
}
