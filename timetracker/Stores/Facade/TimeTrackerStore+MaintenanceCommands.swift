import Foundation

extension TimeTrackerStore {
    func replaceWithDemoData() {
        let didReplace = perform {
            guard let modelContext else { throw StoreError.notConfigured }
            try SeedData.replaceWithDemoData(context: modelContext)
        }
        if didReplace {
            tasksRoute = nil
            todayTaskRoute = nil
        }
    }

    func clearAllData() {
        let previousAPIKey: String?
        do {
            previousAPIKey = try llmCredentialStore.readAPIKey()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let defaults = AppDefaults.shared
        let previousAutomaticSuggestions = defaults.object(
            forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled
        )
        let previousAppleHealthTimelineEnabled =
            appleHealthTimelinePreferenceStore.isTimelineEnabled
        let previousAppleHealthTaskCatalogClearRecoveryTaskIDs =
            appleHealthTimelinePreferenceStore
                .taskCatalogClearRecoveryTaskIDs
        var localSettingsWereCleared = false
        let didClear = perform {
            guard let modelContext else { throw StoreError.notConfigured }
            try llmCredentialStore.writeAPIKey("")
            defaults.removeObject(forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled)
            appleHealthTimelinePreferenceStore.isTimelineEnabled = false
            localSettingsWereCleared = true
            appleHealthTimelinePreferenceStore
                .taskCatalogClearRecoveryTaskIDs =
                try visibleAppleHealthTaskCatalogTaskIDsForClear()
            try appleHealthReplicaRepository.clear()
            appleHealthReplicaSyncService?.markNeedsSynchronization()
            try SeedData.clearAll(context: modelContext)
        }
        if !didClear, localSettingsWereCleared {
            do {
                try llmCredentialStore.writeAPIKey(previousAPIKey ?? "")
            } catch {
                errorMessage = error.localizedDescription
            }
            if let previousAutomaticSuggestions {
                defaults.set(
                    previousAutomaticSuggestions,
                    forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled
                )
            } else {
                defaults.removeObject(forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled)
            }
            appleHealthTimelinePreferenceStore.isTimelineEnabled =
                previousAppleHealthTimelineEnabled
            appleHealthTimelinePreferenceStore
                .taskCatalogClearRecoveryTaskIDs =
                previousAppleHealthTaskCatalogClearRecoveryTaskIDs
        }
        if didClear {
            selectedTaskID = nil
            tasksRoute = nil
            todayTaskRoute = nil
            hideAppleHealthFromTimeline()
        }
    }

    func clearDemoData() {
        let selectedDemoTaskID = selectedTaskID.flatMap { selectedID in
            tasks.first { $0.id == selectedID && $0.deviceID == "demo" }?.id
        }
        let routedDemoTaskID = (tasksRoute?.taskID).flatMap { routedID in
            tasks.first { $0.id == routedID && $0.deviceID == "demo" }?.id
        }
        let todayRoutedDemoTaskID = (todayTaskRoute?.taskID).flatMap { routedID in
            tasks.first { $0.id == routedID && $0.deviceID == "demo" }?.id
        }
        let replacementSelectionID = activeSegments.first(where: {
            taskByID[$0.taskID].map { $0.deviceID != "demo" } == true
        })?.taskID ?? tasks.first(where: {
            $0.deviceID != "demo" && isTaskAvailableForTracking($0)
        })?.id
        let didClear = perform {
            guard let modelContext else { throw StoreError.notConfigured }
            try SeedData.clearDemoData(context: modelContext)
        }
        if didClear, selectedDemoTaskID != nil {
            selectedTaskID = replacementSelectionID
        }
        if didClear, routedDemoTaskID != nil {
            tasksRoute = nil
        }
        if didClear, todayRoutedDemoTaskID != nil {
            todayTaskRoute = nil
        }
    }

    @discardableResult
    func optimizeDatabase() throws -> Int {
        try performThrowingMutation(eventsForOutcome: { removedCount in
            removedCount == 0 ? [] : [.fullSync]
        }) {
            guard let modelContext else { throw StoreError.notConfigured }
            return try databaseMaintenanceService.optimizeDatabase(context: modelContext)
        }
    }

    func jsonExport() throws -> String {
        guard let modelContext else { throw StoreError.notConfigured }
        return try syncConflictService.exportUserData(
            context: modelContext,
            appleHealthReplica: appleHealthReplicaRepository
        )
    }
}
