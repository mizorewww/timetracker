import SwiftUI

extension SettingsView {
    @ViewBuilder
    func settingsSections(for category: SettingsCategory) -> some View {
        switch category {
        case .general:
            DisplayTimingSettingsSection(
                allowParallelTimers: allowParallelTimersBinding,
                showGrossAndWallTogether: showGrossAndWallTogetherBinding
            )

            CountdownSettingsSection(
                events: store.countdownEvents,
                onChangeTitle: { event, title in
                    store.updateCountdownEvent(event, title: title)
                },
                onChangeDate: { event, date in
                    store.updateCountdownEvent(event, date: date)
                },
                onDelete: store.deleteCountdownEvent,
                onAdd: store.addCountdownEvent
            )

        case .focus:
            PomodoroSettingsSection(plans: pomodoroPlansBinding)

        case .dataAndSync:
            DataSettingsSection(
                allowsPermanentCleanup: AppCloudSync.allowsPermanentTombstonePurge,
                onExport: prepareJSONExport,
                onAddTime: { store.presentManualTime() },
                onOptimize: { isOptimizeConfirmationPresented = true }
            )

            SyncSettingsSection(
                cloudSyncEnabled: cloudSyncEnabledBinding,
                currentStorageValue: currentStorageValue,
                feedback: syncFeedback,
                pendingConflict: store.pendingSyncConflict,
                isCheckingSync: isCheckingSync,
                onCheckSync: checkSyncStatus,
                onForceSync: forceSyncRefresh,
                onForceUploadLocal: { isForceUploadConfirmationPresented = true },
                onForceDownloadCloud: { isForceDownloadConfirmationPresented = true },
                onUploadLocal: { isForceUploadConfirmationPresented = true },
                onDownloadCloud: { isForceDownloadConfirmationPresented = true }
            )

        case .intelligence:
            LLMSettingsSection(
                automaticSuggestionsEnabled: llmAutomaticSuggestionsEnabledBinding,
                endpoint: store.preferences.llmEndpoint,
                hasAPIKey: !store.preferences.llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                selectedModel: store.preferences.llmSelectedModel,
                availableModels: store.preferences.llmAvailableModelIDs,
                onConfigure: { isLLMConfigurationPresented = true }
            )

        case .advanced:
            MaintenanceSettingsSection(
                taskCount: store.tasks.count,
                timeRecordCount: store.allSegments.count,
                pomodoroCount: store.pomodoroRuns.count,
                cloudAccount: store.syncStatus.accountStatus,
                cloudContainer: store.syncStatus.containerIdentifier,
                allowsDemoDataCreation: AppDemoDataConfiguration.allowsDemoDataCreation,
                hasDemoData: hasDemoData,
                onRebuildDemoData: { isResetConfirmationPresented = true },
                onClearDemoData: { isClearConfirmationPresented = true },
                onResetAllData: { isResetAllDataConfirmationPresented = true }
            )
            AboutSettingsSection()
        }
    }
}
