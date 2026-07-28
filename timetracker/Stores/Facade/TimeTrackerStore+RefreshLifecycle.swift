import Foundation
import SwiftData

extension TimeTrackerStore {
    func refreshQuietly() {
        do {
            try refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshForForeground(
        cloudAccountStatusClient: CloudAccountStatusClient? = nil
    ) async {
        refreshQuietly()
        scheduleSyncConflictPromptRefresh()
        materializeCurrentDailyTaskRecurrences()
        reconcileActivePomodoro(now: Date())
        enqueueCommittedMutationSystemProjections(
            events: [.fullSync]
        )
        appleHealthReplicaSyncService?.markNeedsSynchronization()
        await refreshAppleHealthTimelineIfEnabled()
        await refreshCloudAccountStatus(
            client: cloudAccountStatusClient
        )
    }

    @discardableResult
    func refreshCloudAccountStatus(
        client: CloudAccountStatusClient? = nil,
        checkedAt: Date = Date()
    ) async -> CloudAccountCheckOutcome {
        let resolvedClient: CloudAccountStatusClient = if let client {
            client
        } else {
            .live(containerIdentifier: AppCloudSync.containerIdentifier)
        }
        let requestID = UUID()
        cloudAccountCheckRequestID = requestID
        let outcome = await AppCloudSync.checkAccountStatus(
            client: resolvedClient,
            checkedAt: checkedAt
        )
        if cloudAccountCheckRequestID == requestID {
            cloudAccountCheck = outcome
        }
        return outcome
    }

    @discardableResult
    func resolveSyncConflict(
        expectedConflictID: UUID?,
        resolution: SyncConflictResolution
    ) throws -> SyncConflictResolutionResult {
        guard let modelContext else { throw StoreError.notConfigured }
        let result = try syncConflictService.resolveSyncConflict(
            expectedConflictID: expectedConflictID,
            resolution: resolution,
            context: modelContext
        )
        guard result != .conflictChanged else {
            try replacePendingSyncConflict(
                syncConflictService.prompt()
            )
            return result
        }
        replacePendingSyncConflict(nil)
        SyncConflictPromptChangeBroadcaster.publish()
        if hasCompletedStartupConfiguration {
            try refresh()
            enqueueCommittedMutationSystemProjections(
                events: [.fullSync]
            )
        } else {
            configureIfNeeded(context: modelContext)
        }
        return result
    }

    func refresh() throws {
        try refresh(plan: refreshPlanner.plan(after: [.fullSync]))
    }

    func refresh(plan: StoreRefreshPlan) throws {
        try refreshCoordinator.refresh(self, plan: plan)
    }

    func validateSelectedTask() {
        if selectedTaskID == nil {
            selectedTaskID = preferredTaskIDForSelection()
        } else if let selectedTaskID, isTaskDetailRouteValid(selectedTaskID) == false {
            self.selectedTaskID = preferredTaskIDForSelection()
        }

        if let detailTaskID = tasksRoute?.taskID,
           shouldRetainTaskDetailRoute(detailTaskID) == false
        {
            tasksRoute = nil
        }
        if let detailTaskID = todayTaskRoute?.taskID,
           shouldRetainTaskDetailRoute(detailTaskID) == false
        {
            todayTaskRoute = nil
        }
    }
}
