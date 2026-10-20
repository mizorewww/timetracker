import Foundation
import SwiftData

extension TimeTrackerStore {
    func refreshQuietly() {
        do {
            try refresh()
        } catch {
            logUnpresentedFailure("Refresh", error)
        }
    }

    func refreshForForeground(
        cloudAccountStatusClient: CloudAccountStatusClient? = nil
    ) async {
        // Reloading every read model here cost seconds on a long history;
        // persistent history names what changed while the app was away, and
        // reconciling Pomodoro re-converges today's window and live timers.
        refreshChangesSinceLastCatchUp()
        materializeCurrentDailyTaskRecurrences()
        reconcileActivePomodoro(now: Date())
        enqueueCommittedMutationSystemProjections(
            events: [.fullSync]
        )
        if AppCloudSync.opensSyncableStore {
            await refreshCloudAccountStatus(client: cloudAccountStatusClient)
        }
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

    func refresh() throws {
        try refresh(plan: StoreRefreshPlanner.plan(after: [.fullSync]))
    }

    func refresh(plan: StoreRefreshPlan) throws {
        try StoreRefreshCoordinator.refresh(self, plan: plan)
    }

    func validateSelectedTask() {
        if selectedTaskID == nil {
            selectedTaskID = preferredTaskIDForSelection()
        } else if let selectedTaskID, isTaskDetailRouteValid(selectedTaskID) == false {
            self.selectedTaskID = preferredTaskIDForSelection()
        }

        if let detailTaskID = tasksRoute?.taskID,
           isTaskDetailRouteValid(detailTaskID) == false
        {
            tasksRoute = nil
        }
        if let detailTaskID = todayTaskRoute?.taskID,
           isTaskDetailRouteValid(detailTaskID) == false
        {
            todayTaskRoute = nil
        }
    }
}
