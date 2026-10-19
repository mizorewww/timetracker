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
            LiveActivitySettingsSection()
            #endif

            TodayHeatmapSettingsSection(
                store: store,
                onChangePeriod: { period in
                    performSettingsMutation(title: AppStrings.localized("heatmap.settings.title")) {
                        try store.setTodayHeatmapPeriod(period)
                    }
                },
                onChangeSelection: { taskIDs in
                    performSettingsMutation(title: AppStrings.localized("heatmap.settings.title")) {
                        try store.setTodayHeatmapTaskIDs(taskIDs)
                    }
                }
            )

            CountdownSettingsSection(
                events: store.countdownEvents,
                onChangeTitle: { event, title in
                    feedbackRouter.perform(title: AppStrings.localized("settings.countdown")) {
                        try store.updateCountdownEvent(event, title: title)
                    } != nil
                },
                onChangeDate: { event, date in
                    performSettingsMutation(title: AppStrings.localized("settings.countdown")) {
                        try store.updateCountdownEvent(event, date: date)
                    }
                },
                onDelete: { event in
                    performSettingsMutation(title: AppStrings.localized("settings.countdown")) {
                        try store.deleteCountdownEvent(event)
                    }
                },
                onAdd: {
                    performSettingsMutation(title: AppStrings.localized("settings.countdown")) {
                        try store.addCountdownEvent()
                    }
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
                    performSettingsMutation(title: AppStrings.localized("task.action.unarchive")) {
                        try store.unarchiveTask(taskID: task.id)
                    }
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

        case .intelligence:
            LLMSettingsSection(
                automaticSuggestionsEnabled: llmAutomaticSuggestionsEnabledBinding,
                isConfigured: store.preferences.isLLMConfigured,
                selectedModel: store.preferences.llmSelectedModel,
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
                allowsDemoDataCreation: allowsDemoDataCreation,
                hasDemoData: hasDemoDataInDebugBuild,
                onRebuildDemoData: { pendingDestructiveConfirmation = .rebuildDemo },
                onClearDemoData: { pendingDestructiveConfirmation = .clearDemo },
                onResetAllData: { pendingDestructiveConfirmation = .resetAllData }
            )
            AboutSettingsSection()
        }
    }
}

extension SettingsView {
    var allowsDemoDataCreation: Bool {
        #if DEBUG
        AppDemoDataConfiguration.allowsDemoDataMutation
        #else
        false
        #endif
    }

    var hasDemoDataInDebugBuild: Bool {
        #if DEBUG
        hasDemoData
        #else
        false
        #endif
    }
}
