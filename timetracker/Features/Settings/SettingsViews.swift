import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var isResetConfirmationPresented = false
    @State private var isClearConfirmationPresented = false
    @State private var isOptimizeConfirmationPresented = false
    @State private var isExportPresented = false
    @State private var isCheckingSync = false
    @State private var syncCheckMessage: String?
    @State private var databaseOptimizationMessage: String?

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

    private var currentStorageValue: String {
        store.preferences.cloudSyncEnabled
            ? (store.syncStatus.isCloudBacked ? "iCloud" : AppStrings.localized("settings.localWillRetryCloud"))
            : AppStrings.localized("settings.local")
    }

    private var syncFeedback: SyncFeedback {
        store.syncStatus.feedback(
            preferences: store.preferences,
            isChecking: isCheckingSync,
            lastRefreshAt: store.lastSyncRefreshAt
        )
    }

    private func checkSyncStatus() {
        isCheckingSync = true
        Task {
            await store.refreshCloudAccountStatus()
            syncCheckMessage = store.syncStatus.accountStatus
            isCheckingSync = false
        }
    }

    private func forceSyncRefresh() {
        isCheckingSync = true
        Task {
            syncCheckMessage = await store.forceCloudSyncRefresh()
            isCheckingSync = false
        }
    }

    private var syncCheckPresented: Binding<Bool> {
        Binding {
            syncCheckMessage != nil
        } set: { isPresented in
            if !isPresented {
                syncCheckMessage = nil
            }
        }
    }

    private var optimizationMessagePresented: Binding<Bool> {
        Binding {
            databaseOptimizationMessage != nil
        } set: { isPresented in
            if !isPresented {
                databaseOptimizationMessage = nil
            }
        }
    }

    private var preferredColorSchemeBinding: Binding<String> {
        Binding(
            get: { store.preferences.preferredColorScheme },
            set: { store.setPreferredColorScheme($0) }
        )
    }

    private var pomodoroDefaultModeBinding: Binding<String> {
        Binding(
            get: { store.preferences.pomodoroDefaultMode },
            set: { store.setPomodoroDefaultMode($0) }
        )
    }

    private var defaultFocusMinutesBinding: Binding<Int> {
        Binding(
            get: { store.preferences.defaultFocusMinutes },
            set: { store.setDefaultFocusMinutes($0) }
        )
    }

    private var defaultBreakMinutesBinding: Binding<Int> {
        Binding(
            get: { store.preferences.defaultBreakMinutes },
            set: { store.setDefaultBreakMinutes($0) }
        )
    }

    private var defaultPomodoroRoundsBinding: Binding<Int> {
        Binding(
            get: { store.preferences.defaultPomodoroRounds },
            set: { store.setDefaultPomodoroRounds($0) }
        )
    }

    private var allowParallelTimersBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.allowParallelTimers },
            set: { store.setAllowParallelTimers($0) }
        )
    }

    private var showGrossAndWallTogetherBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.showGrossAndWallTogether },
            set: { store.setShowGrossAndWallTogether($0) }
        )
    }

    private var cloudSyncEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.cloudSyncEnabled },
            set: { store.setCloudSyncEnabled($0) }
        )
    }
}
