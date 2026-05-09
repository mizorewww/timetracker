import Foundation

@MainActor
struct StoreRefreshCoordinator {
    func refresh(_ store: TimeTrackerStore, plan: StoreRefreshPlan) throws {
        guard store.taskRepository != nil, store.timeRepository != nil else { return }

        try PerformanceSignpost.interval("Store refresh") {
            try refreshPrimaryDomains(on: store, plan: plan)
            refreshDerivedDomains(on: store, plan: plan)
            applyPostRefreshEffects(on: store, plan: plan)
        }
    }

    private func refreshPrimaryDomains(on store: TimeTrackerStore, plan: StoreRefreshPlan) throws {
        if plan.refreshTasks {
            try PerformanceSignpost.interval("Task domain refresh") {
                try store.refreshTaskDomain(plan: plan)
            }
        }
        if plan.refreshLedger {
            try PerformanceSignpost.interval("Ledger domain refresh") {
                try store.refreshLedgerDomain(plan: plan)
            }
        }
        if plan.refreshPomodoro {
            try PerformanceSignpost.interval("Pomodoro domain refresh") {
                try store.refreshPomodoroDomain()
            }
        }
        if plan.refreshPreferences {
            try PerformanceSignpost.interval("Preference domain refresh") {
                try store.refreshPreferenceDomain()
            }
        }
        if plan.refreshCountdown {
            try PerformanceSignpost.interval("Countdown fetch") {
                store.countdownEvents = try store.fetchCountdownEvents()
            }
        }
        if plan.refreshChecklist {
            try PerformanceSignpost.interval("Checklist fetch") {
                try store.refreshChecklistDomain(plan: plan)
            }
        }
        if plan.refreshInbox {
            try PerformanceSignpost.interval("Inbox fetch") {
                try store.refreshInboxDomain(plan: plan)
            }
        }
    }

    private func refreshDerivedDomains(on store: TimeTrackerStore, plan: StoreRefreshPlan) {
        if plan.refreshRollups {
            PerformanceSignpost.interval("Rollup refresh") {
                store.refreshRollupDomain(plan: plan)
            }
        }
        if plan.refreshAnalytics {
            PerformanceSignpost.interval("Analytics cache refresh") {
                store.refreshAnalyticsDomain(plan: plan)
            }
        }
    }

    private func applyPostRefreshEffects(on store: TimeTrackerStore, plan: StoreRefreshPlan) {
        if plan.validateSelection {
            store.validateSelectedTask()
        }

        if plan.syncLiveActivities {
            store.syncLiveActivitiesIfAvailable()
        }

        if plan.refreshLedger || plan.refreshTasks {
            store.syncWidgetSnapshotIfAvailable()
            store.syncWatchSnapshotIfAvailable()
        }

        if plan.refreshInbox || plan.refreshTasks || plan.refreshPreferences {
            store.autoSuggestInboxItemsIfNeeded()
        }

        if plan.refreshChecklist || plan.refreshTasks || plan.refreshPreferences {
            store.autoSuggestChecklistVisualsIfNeeded()
        }
    }
}
