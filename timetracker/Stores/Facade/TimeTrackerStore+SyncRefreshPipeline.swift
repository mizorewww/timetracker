import Foundation

extension TimeTrackerStore {
    private static let syncRefreshCoalescingDelay: Duration = .milliseconds(350)

    func scheduleQuietRefresh(reason: SyncRefreshReason) {
        if case let .cloudExportFinished(eventID, succeeded, _, _) = reason {
            completedCloudExportResults[eventID] = succeeded
        }
        var batch = scheduledSyncRefreshBatch ?? SyncRefreshBatch()
        batch.insert(reason)
        scheduledSyncRefreshBatch = batch
        guard scheduledSyncRefreshTask == nil else { return }
        scheduledSyncRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.syncRefreshCoalescingDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            scheduledSyncRefreshTask = nil
            let batch = scheduledSyncRefreshBatch ?? {
                var fallback = SyncRefreshBatch()
                fallback.insert(reason)
                return fallback
            }()
            scheduledSyncRefreshBatch = nil
            var processingFailure: Error?
            do {
                try updateConflictState(after: batch)
            } catch {
                processingFailure = error
            }
            if batch.requiresReadModelCatchUp {
                do {
                    let plan = refreshPlanner.plan(after: [.remoteImportCompleted])
                    if hasCompletedStartupConfiguration {
                        try refresh(plan: plan)
                    } else {
                        try refreshCoordinator.refreshReadModels(self, plan: plan)
                    }
                } catch {
                    processingFailure = processingFailure ?? error
                }
                enqueueCommittedMutationSystemProjections(
                    events: [.remoteImportCompleted]
                )
            }
            guard let activityReason = batch.activityReason else { return }
            if let processingFailure {
                recordSyncActivity(
                    for: activityReason,
                    processingFailureMessage: processingFailure.localizedDescription
                )
            } else {
                recordSyncActivity(for: activityReason)
            }
        }
    }

    func recordCloudExportStart(eventID: UUID) {
        do {
            try syncConflictService.markCloudExportStarted(eventID: eventID)
        } catch {
            recordCloudExportStateFailure(error)
        }
    }

    private func updateConflictState(after batch: SyncRefreshBatch) throws {
        guard let modelContext else { return }
        let shouldHandleCloudImport = AppCloudSync.isCloudImportRecoveryActive
            ? batch.hasSuccessfulCloudImport
            : batch.requiresCloudImportHandling
        if shouldHandleCloudImport {
            try replacePendingSyncConflict(
                syncConflictService.handleCloudImport(
                    context: modelContext
                )
            )
        } else {
            try replacePendingSyncConflict(
                syncConflictService.prompt()
            )
        }
        let completedExports = Array(completedCloudExportResults)
        for (eventID, succeeded) in completedExports {
            try syncConflictService.markCloudExportFinished(eventID: eventID, succeeded: succeeded)
            completedCloudExportResults.removeValue(forKey: eventID)
        }
        persistenceWriteSafety = writeAuthorization.usesApplicationState
            ? AppCloudSync.persistenceWriteSafety
            : .ready
        if persistenceWriteSafety == .ready,
           pendingSyncConflict == nil,
           hasCompletedStartupConfiguration == false
        {
            configureIfNeeded(context: modelContext)
        }
    }

    func refreshCloudRecoveryPresentationState() {
        persistenceWriteSafety = AppCloudSync.persistenceWriteSafety
        do {
            try replacePendingSyncConflict(
                syncConflictService.prompt()
            )
        } catch {
            recordCloudExportStateFailure(error)
            return
        }
        guard persistenceWriteSafety == .ready,
              pendingSyncConflict == nil,
              hasCompletedStartupConfiguration == false,
              let modelContext
        else {
            return
        }
        configureIfNeeded(context: modelContext)
    }
}
