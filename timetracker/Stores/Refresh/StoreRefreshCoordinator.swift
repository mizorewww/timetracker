import Foundation

@MainActor
struct StoreRefreshCoordinator {
    func refresh(_ store: TimeTrackerStore, plan: StoreRefreshPlan) throws {
        guard store.taskRepository != nil, store.timeRepository != nil else { return }

        try refreshPrimaryDomains(on: store, plan: plan)
        refreshDerivedDomains(on: store, plan: plan)
        applyPostRefreshEffects(on: store, plan: plan)
    }

    private func refreshPrimaryDomains(on store: TimeTrackerStore, plan: StoreRefreshPlan) throws {
        if plan.refreshTasks {
            try store.refreshTaskDomain()
        }
        if plan.refreshLedger {
            try store.refreshLedgerDomain(includeHistory: plan.includeLedgerHistory)
        }
        if plan.refreshPomodoro {
            try store.refreshPomodoroDomain()
        }
        if plan.refreshPreferences {
            try store.refreshPreferenceDomain()
        }
        if plan.refreshCountdown {
            store.countdownEvents = try store.fetchCountdownEvents()
        }
        if plan.refreshChecklist {
            store.checklistItems = try store.fetchChecklistItems()
        }
        if plan.refreshInbox {
            store.inboxItems = try store.fetchInboxItems()
        }
    }

    private func refreshDerivedDomains(on store: TimeTrackerStore, plan: StoreRefreshPlan) {
        if plan.refreshRollups {
            store.refreshRollupDomain(plan: plan)
        }
        if plan.refreshAnalytics {
            store.refreshAnalyticsDomain(plan: plan)
        }
    }

    private func applyPostRefreshEffects(on store: TimeTrackerStore, plan: StoreRefreshPlan) {
        if plan.validateSelection {
            store.validateSelectedTask()
        }

        if plan.syncLiveActivities {
            store.syncLiveActivitiesIfAvailable()
        }
    }
}
