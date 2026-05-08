import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: TimeTrackerStore
    @State var isResetConfirmationPresented = false
    @State var isClearConfirmationPresented = false
    @State var isOptimizeConfirmationPresented = false
    @State var isExportPresented = false
    @State var isCheckingSync = false
    @State var isFetchingLLMModels = false
    @State var syncCheckMessage: String?
    @State var databaseOptimizationMessage: String?
    @State var llmModelFetchMessage: String?

    var body: some View {
        Form {
            DisplayTimingSettingsSection(
                preferredColorScheme: preferredColorSchemeBinding,
                allowParallelTimers: allowParallelTimersBinding,
                showGrossAndWallTogether: showGrossAndWallTogetherBinding
            )

            PomodoroSettingsSection(
                defaultMode: pomodoroDefaultModeBinding,
                focusMinutes: defaultFocusMinutesBinding,
                breakMinutes: defaultBreakMinutesBinding,
                rounds: defaultPomodoroRoundsBinding
            ) { preset in
                store.setDefaultFocusMinutes(preset.focusMinutes)
                store.setDefaultBreakMinutes(preset.breakMinutes)
            }

            CountdownSettingsSection(
                events: store.countdownEvents,
                onChangeTitle: { event, title in
                    store.updateCountdownEvent(event, title: title)
                },
                onChangeDate: { event, date in
                    store.updateCountdownEvent(event, date: date)
                },
                onDelete: { event in
                    store.deleteCountdownEvent(event)
                },
                onAdd: {
                    store.addCountdownEvent()
                }
            )

            DataSettingsSection(
                onExport: {
                    isExportPresented = true
                },
                onAddTime: {
                    store.presentManualTime()
                },
                onOptimize: {
                    isOptimizeConfirmationPresented = true
                }
            )

            SyncSettingsSection(
                cloudSyncEnabled: cloudSyncEnabledBinding,
                currentStorageValue: currentStorageValue,
                feedback: syncFeedback,
                isCheckingSync: isCheckingSync,
                onCheckSync: checkSyncStatus,
                onForceSync: forceSyncRefresh
            )

            LLMSettingsSection(
                endpoint: llmEndpointBinding,
                apiKey: llmAPIKeyBinding,
                selectedModel: llmSelectedModelBinding,
                availableModels: store.preferences.llmAvailableModelIDs,
                feedbackMessage: llmModelFetchMessage,
                isFetchingModels: isFetchingLLMModels,
                onFetchModels: fetchLLMModels
            )

            MaintenanceSettingsSection(
                taskCount: store.tasks.count,
                timeRecordCount: store.allSegments.count,
                pomodoroCount: store.pomodoroRuns.count,
                cloudAccount: store.syncStatus.accountStatus,
                cloudContainer: store.syncStatus.containerIdentifier,
                onRebuildDemoData: {
                    isResetConfirmationPresented = true
                },
                onClearDemoData: {
                    isClearConfirmationPresented = true
                }
            )

            AboutSettingsSection()
        }
        .formStyle(.grouped)
        .navigationTitle(AppStrings.settings)
        .accessibilityIdentifier("settings.view")
        .onAppear(perform: fetchLLMModelsIfNeeded)
        .fileExporter(
            isPresented: $isExportPresented,
            document: CSVExportDocument(text: store.csvExport()),
            contentType: .commaSeparatedText,
            defaultFilename: "time-tracker-export.csv"
        ) { result in
            if case let .failure(error) = result {
                store.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(AppStrings.localized("dialog.rebuildDemo.title"), isPresented: $isResetConfirmationPresented, titleVisibility: .visible) {
            Button(AppStrings.localized("dialog.rebuildDemo.confirm"), role: .destructive) {
                store.replaceWithDemoData()
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("dialog.rebuildDemo.message"))
        }
        .confirmationDialog(AppStrings.localized("dialog.clearDemo.title"), isPresented: $isClearConfirmationPresented, titleVisibility: .visible) {
            Button(AppStrings.localized("dialog.clearDemo.confirm"), role: .destructive) {
                store.clearDemoData()
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("dialog.clearDemo.message"))
        }
        .confirmationDialog(AppStrings.localized("dialog.optimize.title"), isPresented: $isOptimizeConfirmationPresented, titleVisibility: .visible) {
            Button(AppStrings.localized("dialog.optimize.confirm"), role: .destructive) {
                let removedCount = store.optimizeDatabase()
                databaseOptimizationMessage = removedCount == 0 ? AppStrings.localized("dialog.optimize.none") : String(format: AppStrings.localized("dialog.optimize.removed"), removedCount)
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("dialog.optimize.message"))
        }
        .alert(AppStrings.localized("alert.sync.title"), isPresented: syncCheckPresented) {
            Button(AppStrings.localized("common.ok")) {
                syncCheckMessage = nil
            }
        } message: {
            Text(syncCheckMessage ?? "")
        }
        .alert(AppStrings.localized("alert.optimize.title"), isPresented: optimizationMessagePresented) {
            Button(AppStrings.localized("common.ok")) {
                databaseOptimizationMessage = nil
            }
        } message: {
            Text(databaseOptimizationMessage ?? "")
        }
    }
}
