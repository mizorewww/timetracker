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

    func refreshForForeground() async {
        refreshQuietly()
        reconcileActivePomodoro(now: Date())
        await refreshAppleHealthTimelineIfEnabled()
        await refreshCloudAccountStatus()
    }

    @discardableResult
    func refreshCloudAccountStatus(
        client: CloudAccountStatusClient? = nil,
        checkedAt: Date = Date()
    ) async -> CloudAccountCheckOutcome {
        let resolvedClient: CloudAccountStatusClient
        if let client {
            resolvedClient = client
        } else {
            resolvedClient = .live(containerIdentifier: AppCloudSync.containerIdentifier)
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
            pendingSyncConflict = try syncConflictService.prompt()
            return result
        }
        pendingSyncConflict = nil
        if hasCompletedStartupConfiguration {
            try refresh()
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

        if let detailTaskID = tasksRoute?.taskID, isTaskDetailRouteValid(detailTaskID) == false {
            tasksRoute = nil
        }
    }
}
