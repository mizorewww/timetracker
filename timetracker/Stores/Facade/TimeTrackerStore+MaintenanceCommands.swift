import Foundation
import SwiftData

extension TimeTrackerStore {
    func clearAllData() throws {
        let previousAPIKey = try llmCredentialStore.readAPIKey()
        let defaults = AppDefaults.shared
        let previousAutomaticSuggestions = defaults.object(
            forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled
        )
        var localSettingsWereCleared = false
        do {
            try perform(events: [.fullSync]) {
                guard let modelContext else { throw StoreError.notConfigured }
                try llmCredentialStore.writeAPIKey("")
                defaults.removeObject(forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled)
                localSettingsWereCleared = true
                try SeedData.clearAll(context: modelContext)
            }
        } catch {
            if localSettingsWereCleared {
                // The clear failure is the one to report; a failed key restore
                // leaves the key empty, which the user can re-enter.
                try? llmCredentialStore.writeAPIKey(previousAPIKey ?? "")
                if let previousAutomaticSuggestions {
                    defaults.set(
                        previousAutomaticSuggestions,
                        forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled
                    )
                } else {
                    defaults.removeObject(forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled)
                }
            }
            throw error
        }
        selectedTaskID = nil
        tasksRoute = nil
        todayTaskRoute = nil
    }

    @discardableResult
    func optimizeDatabase() throws -> Int {
        try performThrowingMutation(eventsForOutcome: { removedCount in
            removedCount == 0 ? [] : [.fullSync]
        }) {
            guard let modelContext else { throw StoreError.notConfigured }
            return try DatabaseMaintenanceService.optimizeDatabase(context: modelContext)
        }
    }

    func jsonExport() throws -> String {
        guard let modelContext else { throw StoreError.notConfigured }
        return try UserDataExport.encodedJSON(container: modelContext.container)
    }
}

#if DEBUG
extension TimeTrackerStore {
    func replaceWithDemoData() throws {
        try perform(events: [.fullSync]) {
            guard let modelContext else { throw StoreError.notConfigured }
            try SeedData.replaceWithDemoData(context: modelContext)
        }
        tasksRoute = nil
        todayTaskRoute = nil
    }

    func clearDemoData() throws {
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
        try perform(events: [.fullSync]) {
            guard let modelContext else { throw StoreError.notConfigured }
            try SeedData.clearDemoData(context: modelContext)
        }
        if selectedDemoTaskID != nil {
            selectedTaskID = replacementSelectionID
        }
        if routedDemoTaskID != nil {
            tasksRoute = nil
        }
        if todayRoutedDemoTaskID != nil {
            todayTaskRoute = nil
        }
    }
}
#endif
