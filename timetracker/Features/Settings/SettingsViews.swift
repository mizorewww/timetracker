import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: TimeTrackerStore
    @State var isResetConfirmationPresented = false
    @State var isClearConfirmationPresented = false
    @State var isResetAllDataConfirmationPresented = false
    @State var isOptimizeConfirmationPresented = false
    @State var isExportPresented = false
    @State var isCheckingSync = false
    @State var isFetchingLLMModels = false
    @State var isForceUploadConfirmationPresented = false
    @State var isForceDownloadConfirmationPresented = false
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
                pendingConflict: store.pendingSyncConflict,
                isCheckingSync: isCheckingSync,
                onCheckSync: checkSyncStatus,
                onForceSync: forceSyncRefresh,
                onForceUploadLocal: {
                    isForceUploadConfirmationPresented = true
                },
                onForceDownloadCloud: {
                    isForceDownloadConfirmationPresented = true
                },
                onUploadLocal: {
                    isForceUploadConfirmationPresented = true
                },
                onDownloadCloud: {
                    isForceDownloadConfirmationPresented = true
                }
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
                allowsDemoDataCreation: AppDemoDataConfiguration.allowsDemoDataCreation,
                onRebuildDemoData: {
                    isResetConfirmationPresented = true
                },
                onClearDemoData: {
                    isClearConfirmationPresented = true
                },
                onResetAllData: {
                    isResetAllDataConfirmationPresented = true
                }
            )

            AboutSettingsSection()
        }
        .formStyle(.grouped)
        .navigationTitle(AppStrings.settings)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("settings.view")
        .fileExporter(
            isPresented: $isExportPresented,
            document: JSONExportDocument(text: store.jsonExport()),
            contentType: .json,
            defaultFilename: "time-tracker-export.json"
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
        .confirmationDialog(AppStrings.localized("dialog.resetData.title"), isPresented: $isResetAllDataConfirmationPresented, titleVisibility: .visible) {
            Button(AppStrings.localized("dialog.resetData.confirm"), role: .destructive) {
                store.clearAllData()
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("dialog.resetData.message"))
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
        .confirmationDialog(AppStrings.localized("dialog.forceUpload.title"), isPresented: $isForceUploadConfirmationPresented, titleVisibility: .visible) {
            Button(role: .destructive) {
                if let result = store.forceUploadLocalDataToCloud() {
                    syncCheckMessage = result == .appliedImmediately
                        ? AppStrings.localized("sync.forceUpload.started")
                        : AppStrings.localized("sync.forceUpload.queued")
                }
            } label: {
                Label(AppStrings.localized("settings.forceUploadICloud"), systemImage: "icloud.and.arrow.up.fill")
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("dialog.forceUpload.message"))
        }
        .confirmationDialog(AppStrings.localized("dialog.forceDownload.title"), isPresented: $isForceDownloadConfirmationPresented, titleVisibility: .visible) {
            Button(role: .destructive) {
                forceDownloadCloudData()
            } label: {
                Label(AppStrings.localized("settings.forceDownloadICloud"), systemImage: "icloud.and.arrow.down.fill")
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("dialog.forceDownload.message"))
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
