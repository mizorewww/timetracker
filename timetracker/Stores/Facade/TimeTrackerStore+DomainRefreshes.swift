import Foundation

extension TimeTrackerStore {
    func refreshTaskDomain(plan: StoreRefreshPlan) throws {
        guard let taskRepository else { return }
        if plan.affectedTaskIDs.isEmpty || tasks.isEmpty {
            try taskDomainStore.refresh(repository: taskRepository)
        } else {
            try taskDomainStore.refreshTaskScoped(taskIDs: plan.affectedTaskIDs, repository: taskRepository)
        }
        // Domain-store arrays are the single owner; the facade exposes them as
        // passthroughs, so only the derived facade indexes need rebuilding.
        rebuildTaskIndexes()
        rebuildTaskCategoryIndexes()
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

    func refreshPomodoroDomain(schedulesReconciliation: Bool = true) throws {
        pomodoroRuns = try pomodoroRepository?.runs().deduplicatedByID() ?? []
        if schedulesReconciliation {
            schedulePomodoroReconciliation()
        }
    }

    func refreshPreferenceDomain() throws {
        let previousEndpoint = preferences.llmEndpoint
        let previousAPIKey = preferences.llmAPIKey
        let previousModelID = preferences.llmSelectedModel
        let previousReasoningEffort = preferences.llmReasoningEffort
        let previousInboxInstructions = preferences.llmInboxSuggestionInstructions
        let previousChecklistInstructions = preferences.llmChecklistVisualInstructions
        let automaticSuggestionsWereEnabled = preferences.llmAutomaticSuggestionsEnabled
        try preferenceDomainStore.refresh(
            syncedPreferences: fetchSyncedPreferences(),
            localLLMAPIKey: llmCredentialStore.readAPIKey() ?? "",
            localLLMAutomaticSuggestionsEnabled: AppDefaults.shared.bool(
                forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled
            )
        )
        let configurationChanged = !matchesCurrentLLMConfiguration(
            LLMRequestConfiguration(
                endpoint: previousEndpoint,
                apiKey: previousAPIKey,
                modelID: previousModelID,
                reasoningEffort: previousReasoningEffort
            )
        )
        if configurationChanged {
            cancelAllInboxSuggestionRequests()
            cancelAllChecklistVisualSuggestionRequests()
        } else {
            if previousInboxInstructions != preferences.llmInboxSuggestionInstructions {
                cancelAllInboxSuggestionRequests()
            }
            if previousChecklistInstructions != preferences.llmChecklistVisualInstructions {
                cancelAllChecklistVisualSuggestionRequests()
            }
            if automaticSuggestionsWereEnabled, !preferences.llmAutomaticSuggestionsEnabled {
                cancelAutomaticInboxSuggestionRequests()
                cancelAllChecklistVisualSuggestionRequests()
            }
        }
    }

    func refreshChecklistDomain(plan: StoreRefreshPlan) throws {
        let scopedTaskIDs = plan.directlyAffectedChecklistTaskIDs
        if scopedTaskIDs.isEmpty || checklistDomainStore.isInitialized == false {
            try checklistDomainStore.refresh(
                items: fetchChecklistItems(),
                visuals: fetchChecklistItemVisuals()
            )
            rebuildChecklistIndexes()
            rebuildChecklistVisualIndexes()
        } else {
            let previousItemIDs = Set(
                scopedTaskIDs.flatMap { checklistDomainStore.items(for: $0) }.map(\.id)
            )
            let scopedItems = try fetchChecklistItems(taskIDs: scopedTaskIDs)
            try checklistDomainStore.refreshTaskScoped(
                taskIDs: scopedTaskIDs,
                items: scopedItems,
                visuals: fetchChecklistItemVisuals(checklistItemIDs: Set(scopedItems.map(\.id)))
            )
            let currentItemIDs = Set(
                scopedTaskIDs.flatMap { checklistDomainStore.items(for: $0) }.map(\.id)
            )

            // The domain store already maintains scoped indexes. Update only
            // the affected facade read-model buckets instead of regrouping
            // every checklist item in the facade.
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
        let itemReadModels = try fetchInboxItemReadModels()
        inboxDomainStore.refresh(itemReadModels: itemReadModels, suggestions: inboxSuggestions)
        if plan.affectedInboxItemIDs.isEmpty || inboxSuggestions.isEmpty {
            try inboxDomainStore.refresh(
                itemReadModels: itemReadModels,
                suggestions: fetchInboxSuggestions()
            )
        } else {
            try inboxDomainStore.refreshSuggestionScoped(
                inboxItemIDs: plan.affectedInboxItemIDs,
                suggestions: fetchInboxSuggestions(inboxItemIDs: plan.affectedInboxItemIDs)
            )
        }
        inboxItemReadModelByItemID = Dictionary(
            uniqueKeysWithValues: inboxDomainStore.itemReadModels.map { ($0.item.id, $0) }
        )
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

    var taskRecurrenceRules: [TaskRecurrenceRule] {
        taskDomainStore.recurrenceRules
    }

    var taskRecurrenceOccurrences: [TaskRecurrenceOccurrence] {
        taskDomainStore.recurrenceOccurrences
    }

    var taskQuantityGoals: [TaskQuantityGoal] {
        taskDomainStore.quantityGoals
    }

    var taskQuantityEntries: [TaskQuantityEntry] {
        taskDomainStore.quantityEntries
    }

    var taskIDsWithIncompleteQuantityProgress: Set<UUID> {
        taskDomainStore.incompleteQuantityProgressTaskIDs
    }

    var incompleteRecurrenceTemplateTaskIDs: Set<UUID> {
        taskDomainStore.incompleteRecurrenceTemplateTaskIDs
    }

    var incompleteRecurrenceGeneratedTaskIDs: Set<UUID> {
        taskDomainStore.incompleteRecurrenceGeneratedTaskIDs
    }

    var taskIDsWithIncompleteRecurrence: Set<UUID> {
        incompleteRecurrenceTemplateTaskIDs.union(
            incompleteRecurrenceGeneratedTaskIDs
        )
    }
}
