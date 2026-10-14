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
        materializeCurrentDailyTaskRecurrences()
        reconcileActivePomodoro(now: Date())
        enqueueCommittedMutationSystemProjections(
            events: [.fullSync]
        )
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
