import Foundation

extension TimeTrackerStore {
    @discardableResult
    func handleWatchCommand(_ command: WatchTimerCommand) -> WatchCommandResult {
        handleWatchCommand(command, recordingWith: syncConflictService)
    }

    @discardableResult
    func handleWatchCommand(
        _ command: WatchTimerCommand,
        recordingWith snapshotService: SyncConflictService
    ) -> WatchCommandResult {
        do {
            guard let modelContext else { throw StoreError.notConfigured }
            let outcome = try WatchCommandProcessor(
                writeAuthorization: writeAuthorization
            ).processWithMutationOutcome(
                command,
                context: modelContext
            )
            let result = outcome.result
            let terminalResult = result.terminalResult(commandID: command.id)

            if result.isProcessed {
                var postCommitError: Error?
                do {
                    if let surfaceError = try refreshCommittedMutationSurfaces(
                        events: outcome.events
                    ) {
                        postCommitError = surfaceError
                    }
                } catch {
                    postCommitError = error
                }
                if let snapshotError = CommittedMutationSnapshotRecorder(
                    syncConflictService: snapshotService
                ).recordLocalMutation(context: modelContext, events: outcome.events) {
                    postCommitError = postCommitError ?? snapshotError
                } else {
                    do {
                        pendingSyncConflict = try snapshotService.prompt()
                    } catch {
                        postCommitError = postCommitError ?? error
                    }
                }

                if let postCommitError {
                    errorMessage = String(
                        format: AppStrings.localized("error.savedRefreshFailed"),
                        postCommitError.localizedDescription
                    )
                }
            }

            // Always publish after a terminal outcome. This also covers duplicate,
            // missing, and invalid commands whose watch may hold a stale snapshot.
            syncWatchSnapshotIfAvailable()
            return terminalResult
        } catch {
            errorMessage = error.localizedDescription
            // A failed command still receives a terminal result and a best-effort
            // state refresh, allowing the watch row to unlock immediately.
            syncWatchSnapshotIfAvailable()
            return .failed(commandID: command.id)
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
        var recentTasks: [WatchRecentTaskSnapshot] = []
        for task in watchTasks.prefix(WatchTransportLimits.maximumRecentTasks) {
            let recentTask = WatchRecentTaskSnapshot(
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
                iconName: WatchTransportLimits.boundedProjectedStyleValue(task.iconName)
            )
            let textByteCount = WatchTransportLimits.textByteCount(
                title: recentTask.title,
                path: recentTask.path,
                colorHex: recentTask.colorHex,
                iconName: recentTask.iconName
            )
            guard textByteCount <= remainingTextBytes else { break }
            recentTasks.append(recentTask)
            remainingTextBytes -= textByteCount
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

    private func watchTaskShortcuts() -> [TaskNode] {
        let availableTasks = tasks.filter {
            isTaskAvailableForTracking($0)
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
