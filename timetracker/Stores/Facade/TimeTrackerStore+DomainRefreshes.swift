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
        try refreshLedgerRelationshipVisibility()
        cancelInvalidChecklistVisualSuggestionRequests()
    }

    func refreshLedgerDomain(plan: StoreRefreshPlan) throws {
        guard let timeRepository else { return }
        ledgerDomainStore.resetRollupChanges()
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
        try refreshLedgerRelationshipVisibility()
    }

    func refreshPomodoroDomain() throws {
        pomodoroRuns = try pomodoroRepository?.runs().deduplicatedByID() ?? []
        schedulePomodoroReconciliation()
    }

    func refreshPreferenceDomain() throws {
        let previousEndpoint = preferences.llmEndpoint
        let previousAPIKey = preferences.llmAPIKey
        let previousModelID = preferences.llmSelectedModel
        let automaticSuggestionsWereEnabled = preferences.llmAutomaticSuggestionsEnabled
        preferenceDomainStore.refresh(
            syncedPreferences: try fetchSyncedPreferences(),
            localLLMAPIKey: try llmCredentialStore.readAPIKey() ?? "",
            localLLMAutomaticSuggestionsEnabled: UserDefaults.standard.bool(
                forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled
            )
        )
        syncedPreferences = preferenceDomainStore.syncedPreferences
        preferences = preferenceDomainStore.preferences
        if !matchesCurrentLLMConfiguration(
            endpoint: previousEndpoint,
            apiKey: previousAPIKey,
            modelID: previousModelID
        ) {
            cancelAllInboxSuggestionRequests()
            cancelAllChecklistVisualSuggestionRequests()
        } else if automaticSuggestionsWereEnabled && !preferences.llmAutomaticSuggestionsEnabled {
            cancelAutomaticInboxSuggestionRequests()
            cancelAllChecklistVisualSuggestionRequests()
        }
    }

    func refreshChecklistDomain(plan: StoreRefreshPlan) throws {
        let scopedTaskIDs = plan.directlyAffectedChecklistTaskIDs
        if scopedTaskIDs.isEmpty || checklistDomainStore.isInitialized == false {
            checklistDomainStore.refresh(
                items: try fetchChecklistItems(),
                visuals: try fetchChecklistItemVisuals()
            )
            checklistItems = checklistDomainStore.items
            checklistItemVisuals = checklistDomainStore.visuals
        } else {
            let previousItemIDs = Set(
                scopedTaskIDs.flatMap { checklistDomainStore.items(for: $0) }.map(\.id)
            )
            let scopedItems = try fetchChecklistItems(taskIDs: scopedTaskIDs)
            checklistDomainStore.refreshTaskScoped(
                taskIDs: scopedTaskIDs,
                items: scopedItems,
                visuals: try fetchChecklistItemVisuals(checklistItemIDs: Set(scopedItems.map(\.id)))
            )
            let currentItemIDs = Set(
                scopedTaskIDs.flatMap { checklistDomainStore.items(for: $0) }.map(\.id)
            )

            // The domain store already maintains scoped indexes. Publish its
            // arrays without immediately regrouping every checklist item in
            // the facade, then update only the affected read-model buckets.
            suppressChecklistIndexRebuild = true
            suppressChecklistVisualIndexRebuild = true
            checklistItems = checklistDomainStore.items
            checklistItemVisuals = checklistDomainStore.visuals
            suppressChecklistIndexRebuild = false
            suppressChecklistVisualIndexRebuild = false

            for taskID in scopedTaskIDs {
                let taskItems = checklistDomainStore.items(for: taskID)
                if taskItems.isEmpty {
                    checklistByTaskID.removeValue(forKey: taskID)
                } else {
                    checklistByTaskID[taskID] = taskItems
                }
            }
            for itemID in previousItemIDs.union(currentItemIDs) {
                if let visual = checklistDomainStore.visual(for: itemID) {
                    checklistVisualByItemID[itemID] = visual
                } else {
                    checklistVisualByItemID.removeValue(forKey: itemID)
                }
            }
        }
        cancelInvalidChecklistVisualSuggestionRequests()
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
        suppressInboxSuggestionIndexRebuild = true
        inboxItems = inboxDomainStore.items
        inboxSuggestions = inboxDomainStore.suggestions
        suppressInboxSuggestionIndexRebuild = false
        rebuildInboxSuggestionIndexes()
        cancelInvalidInboxSuggestionRequests()
    }

    func refreshRollupDomain(plan: StoreRefreshPlan) {
        let requiresFullLedgerReindex = plan.includeLedgerHistory && plan.affectedLedgerRanges.isEmpty
        if plan.refreshTasks || plan.directlyAffectedTaskIDs.isEmpty || requiresFullLedgerReindex {
            rollupDomainStore.refresh(
                tasks: tasks,
                segments: allSegments,
                checklistItems: checklistItems,
                forecastEligibleTaskIDs: forecastEligibleTaskIDs(),
                now: Date()
            )
        } else {
            let scopedChecklistItems = plan.directlyAffectedChecklistTaskIDs.reduce(
                into: [UUID: [ChecklistItem]]()
            ) { result, taskID in
                result[taskID] = checklistDomainStore.items(for: taskID)
            }
            rollupDomainStore.refreshAffected(
                directTaskIDs: plan.directlyAffectedTaskIDs,
                explicitAncestorTaskIDs: plan.explicitlyAffectedAncestorTaskIDs,
                segmentChanges: plan.refreshLedger ? ledgerDomainStore.rollupChanges : [],
                checklistItemsByTaskID: scopedChecklistItems,
                forecastEligibleTaskIDs: forecastEligibleTaskIDs(),
                now: Date()
            )
        }
    }

    func refreshAnalyticsDomain(plan: StoreRefreshPlan) {
        invalidateAnalyticsSnapshots(
            invalidatedIntervals: plan.affectedLedgerRanges.map(\.dateInterval)
        )
        analyticsRevision &+= 1
    }
}
