import Foundation

extension TimeTrackerStore {
    private static let syncRefreshCoalescingDelay: Duration = .milliseconds(350)

    /// Persistent history narrows the catch-up to the models that changed;
    /// a window with no new transactions (an export or setup event) refreshes
    /// nothing.
    private func remoteChangeRefreshPlan() -> StoreRefreshPlan {
        guard let modelContext else {
            return StoreRefreshPlanner.plan(after: [.remoteImportCompleted])
        }
        return StoreRefreshPlan(scopes: remoteChangeHistory.scopesSinceLastCatchUp(in: modelContext))
    }

    /// Coalesces CloudKit and remote-store notifications into one read-model
    /// catch-up per window; the window's highest-priority event becomes the
    /// reported Cloud activity.
    func scheduleQuietRefresh(reason: SyncRefreshReason) {
        if pendingSyncActivityReason.map({ reason.priority >= $0.priority }) ?? true {
            pendingSyncActivityReason = reason
        }
        guard scheduledSyncRefreshTask == nil else { return }
        scheduledSyncRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.syncRefreshCoalescingDelay)
            } catch {
                return
            }
            guard let self else { return }
            scheduledSyncRefreshTask = nil
            let activityReason = pendingSyncActivityReason
            pendingSyncActivityReason = nil
            var processingFailureMessage: String?
            let plan = remoteChangeRefreshPlan()
            if plan.scopes.isEmpty == false {
                do {
                    if hasCompletedStartupConfiguration {
                        try refresh(plan: plan)
                    } else {
                        try StoreRefreshCoordinator.refreshReadModels(self, plan: plan)
                    }
                } catch {
                    processingFailureMessage = error.localizedDescription
                }
                enqueueCommittedMutationSystemProjections(
                    events: [.remoteImportCompleted]
                )
            }
            if let outcome = activityReason?.activityOutcome(
                completedAt: Date(),
                processingFailureMessage: processingFailureMessage
            ) {
                lastSyncActivity = outcome
            }
        }
    }
}
