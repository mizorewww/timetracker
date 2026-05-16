import Foundation

extension TimeTrackerStore {
    func refreshTaskDomain(plan: StoreRefreshPlan) throws {
        guard let taskRepository else { return }
        if plan.affectedTaskIDs.isEmpty || tasks.isEmpty {
            try taskDomainStore.refresh(repository: taskRepository)
        } else {
            try taskDomainStore.refreshTaskScoped(taskIDs: plan.affectedTaskIDs, repository: taskRepository)
        }
        tasks = taskDomainStore.tasks
        taskCategories = taskDomainStore.categories
        taskCategoryAssignments = taskDomainStore.categoryAssignments
    }

    func refreshLedgerDomain(plan: StoreRefreshPlan) throws {
        guard let timeRepository else { return }
        if plan.includeLedgerHistory, plan.affectedLedgerRanges.isEmpty == false {
            try ledgerDomainStore.refreshVisible(repository: timeRepository)
            try ledgerDomainStore.refreshHistoryRanges(
                repository: timeRepository,
                ranges: plan.affectedLedgerRanges
            )
        } else if plan.includeLedgerHistory {
            try ledgerDomainStore.refresh(repository: timeRepository)
        } else {
            try ledgerDomainStore.refreshVisible(repository: timeRepository)
        }
        activeSegments = ledgerDomainStore.activeSegments
        allSegments = ledgerDomainStore.allSegments
        sessions = ledgerDomainStore.sessions
        todaySegments = ledgerDomainStore.todaySegments
    }

    func refreshPomodoroDomain() throws {
        pomodoroRuns = try pomodoroRepository?.runs().deduplicatedByID() ?? []
    }

    func refreshPreferenceDomain() throws {
        preferenceDomainStore.refresh(syncedPreferences: try fetchSyncedPreferences())
        syncedPreferences = preferenceDomainStore.syncedPreferences
        preferences = preferenceDomainStore.preferences
    }

    func refreshChecklistDomain(plan: StoreRefreshPlan) throws {
        if plan.affectedTaskIDs.isEmpty || checklistItems.isEmpty {
            checklistDomainStore.refresh(
                items: try fetchChecklistItems(),
                visuals: try fetchChecklistItemVisuals()
            )
        } else {
            let scopedItems = try fetchChecklistItems(taskIDs: plan.affectedTaskIDs)
            checklistDomainStore.refreshTaskScoped(
                taskIDs: plan.affectedTaskIDs,
                items: scopedItems,
                visuals: try fetchChecklistItemVisuals(checklistItemIDs: Set(scopedItems.map(\.id)))
            )
        }
        checklistItems = checklistDomainStore.items
        checklistItemVisuals = checklistDomainStore.visuals
    }

    func refreshInboxDomain(plan: StoreRefreshPlan) throws {
        inboxDomainStore.refresh(items: try fetchInboxItems(), suggestions: inboxSuggestions)
        if plan.affectedInboxItemIDs.isEmpty || inboxSuggestions.isEmpty {
            inboxDomainStore.refresh(
                items: inboxDomainStore.items,
                suggestions: try fetchInboxSuggestions()
            )
        } else {
            inboxDomainStore.refreshSuggestionScoped(
                inboxItemIDs: plan.affectedInboxItemIDs,
                suggestions: try fetchInboxSuggestions(inboxItemIDs: plan.affectedInboxItemIDs)
            )
        }
        inboxItems = inboxDomainStore.items
        inboxSuggestions = inboxDomainStore.suggestions
    }

    func refreshRollupDomain(plan: StoreRefreshPlan) {
        var store = rollupDomainStore
        if plan.refreshTasks || plan.affectedTaskIDs.isEmpty {
            store.refresh(
                tasks: tasks,
                segments: allSegments,
                checklistItems: checklistItems,
                forecastEligibleTaskIDs: forecastEligibleTaskIDs(),
                now: Date()
            )
        } else {
            store.refreshAffected(
                taskIDs: plan.affectedTaskIDs,
                tasks: tasks,
                segments: allSegments,
                checklistItems: checklistItems,
                forecastEligibleTaskIDs: forecastEligibleTaskIDs(),
                now: Date()
            )
        }
        rollupDomainStore = store
    }

    func refreshAnalyticsDomain(plan: StoreRefreshPlan) {
        refreshCachedAnalyticsSnapshots(
            now: Date(),
            invalidatedIntervals: plan.affectedLedgerRanges.map {
                DateInterval(start: $0.start, end: $0.end)
            }
        )
    }
}
