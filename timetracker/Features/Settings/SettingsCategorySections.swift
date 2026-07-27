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

            #if os(iOS)
            LiveActivitySettingsSection(store: store)
            #endif

            TodayHeatmapSettingsSection(
                store: store,
                onChangePeriod: { period in
                    handleSettingsStoreMutation(
                        store.setTodayHeatmapPeriod(period),
                        title: AppStrings.localized("heatmap.settings.title")
                    )
                },
                onChangeSelection: { taskIDs in
                    handleSettingsStoreMutation(
                        store.setTodayHeatmapTaskIDs(taskIDs),
                        title: AppStrings.localized("heatmap.settings.title")
                    )
                }
            )

            #if os(iOS)
            AppleHealthTimelineSettingsSection(store: store)
            #endif

            CountdownSettingsSection(
                events: store.countdownEvents,
                onChangeTitle: { event, title in
                    store.updateCountdownEvent(event, title: title)
                },
                onChangeDate: { event, date in
                    handleSettingsStoreMutation(
                        store.updateCountdownEvent(event, date: date),
                        title: AppStrings.localized("settings.countdown")
                    )
                },
                onDelete: { event in
                    handleSettingsStoreMutation(
                        store.deleteCountdownEvent(event),
                        title: AppStrings.localized("settings.countdown")
                    )
                },
                onAdd: {
                    handleSettingsStoreMutation(
                        store.addCountdownEvent(),
                        title: AppStrings.localized("settings.countdown")
                    )
                }
            )

        #if os(macOS)
        case .shortcuts:
            MacKeyboardShortcutSettingsSection(settings: shortcutSettings)
        #endif

        case .archivedTasks:
            ArchivedTasksSettingsSection(
                store: store,
                onUnarchive: { task in
                    handleSettingsStoreMutation(
                        store.unarchiveTask(taskID: task.id),
                        title: AppStrings.localized("task.action.unarchive")
                    )
                }
            )

        case .focus:
            PomodoroSettingsSection(plans: pomodoroPlansBinding)

        case .dataAndSync:
            DataSettingsSection(
                allowsPermanentCleanup: AppCloudSync.allowsPermanentTombstonePurge,
                operationMessage: dataOperationMessage,
                onExport: prepareJSONExport,
                onOptimize: { pendingDestructiveConfirmation = .optimizeDatabase }
            )

            SyncSettingsSection(
                cloudSyncEnabled: cloudSyncEnabledBinding,
                currentStorageValue: currentStorageValue,
                feedback: syncFeedback,
                isCheckingSync: isCheckingSync,
                onCheckSync: checkSyncStatus
            )

            SyncRecoverySettingsSection(
                pendingConflict: store.pendingSyncConflict,
                isWorking: isCheckingSync,
                operationMessage: syncOperationMessage,
                onReplaceCloud: {
                    pendingDestructiveConfirmation = .replaceCloud(
                        expectedConflictID: store.pendingSyncConflict?.id
                    )
                },
                onReplaceDevice: {
                    pendingDestructiveConfirmation = .replaceDevice(
                        expectedConflictID: store.pendingSyncConflict?.id
                    )
                }
            )

        case .intelligence:
            LLMSettingsSection(
                automaticSuggestionsEnabled: llmAutomaticSuggestionsEnabledBinding,
                endpoint: store.preferences.llmEndpoint,
                hasAPIKey: !store.preferences.llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                selectedModel: store.preferences.llmSelectedModel,
                availableModels: store.preferences.llmAvailableModelIDs,
                reasoningEffort: store.preferences.llmReasoningEffort,
                onConfigure: presentLLMConfiguration,
                onEditPrompt: presentLLMPrompt
            )

        case .advanced:
            MaintenanceSettingsSection(
                taskCount: store.tasks.count,
                timeRecordCount: store.allSegments.count,
                pomodoroCount: store.pomodoroRuns.count,
                cloudAccount: store.syncStatus.accountStatus,
                cloudContainer: store.syncStatus.containerIdentifier,
                allowsDemoDataCreation: AppDemoDataConfiguration.allowsDemoDataMutation,
                hasDemoData: hasDemoData,
                onRebuildDemoData: { pendingDestructiveConfirmation = .rebuildDemo },
                onClearDemoData: { pendingDestructiveConfirmation = .clearDemo },
                onResetAllData: { pendingDestructiveConfirmation = .resetAllData }
            )
            AboutSettingsSection()
        }
    }
}
