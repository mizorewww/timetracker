import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let store: TimeTrackerStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State var isResetConfirmationPresented = false
    @State var isClearConfirmationPresented = false
    @State var isResetAllDataConfirmationPresented = false
    @State var isOptimizeConfirmationPresented = false
    @State var isExportPresented = false
    @State private var exportDocument = JSONExportDocument(text: "")
    @State var isCheckingSync = false
    @State var isForceUploadConfirmationPresented = false
    @State var isForceDownloadConfirmationPresented = false
    @State var isLLMConfigurationPresented = false
    @State var syncCheckMessage: String?
    @State var databaseOptimizationMessage: String?
    @State private var selectedCategory: SettingsCategory? = .general

    var body: some View {
        settingsNavigation
        .navigationTitle(AppStrings.settings)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("settings.view")
        .fileExporter(
            isPresented: $isExportPresented,
            document: exportDocument,
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
        .sheet(isPresented: $isLLMConfigurationPresented) {
            LLMConfigurationEditor(
                endpoint: store.preferences.llmEndpoint,
                apiKey: store.preferences.llmAPIKey,
                selectedModel: store.preferences.llmSelectedModel,
                availableModels: store.preferences.llmAvailableModelIDs,
                onSave: saveLLMConfiguration
            )
        }
    }

    @ViewBuilder
    private var settingsNavigation: some View {
        #if os(macOS)
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                SettingsCategoryRow(category: category)
                    .tag(category)
            }
            .navigationTitle(AppStrings.settings)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            settingsForm(for: selectedCategory ?? .general)
        }
        #else
        List {
            Section {
                ForEach(SettingsCategory.allCases) { category in
                    NavigationLink(value: category) {
                        SettingsCategoryRow(category: category)
                    }
                }
            } footer: {
                Text(.app("settings.categories.footer"))
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, dynamicTypeSize.isAccessibilitySize ? 112 : 16, for: .scrollContent)
        .navigationDestination(for: SettingsCategory.self) { category in
            settingsForm(for: category)
        }
        #endif
    }

    private func settingsForm(for category: SettingsCategory) -> some View {
        Form {
            settingsSections(for: category)
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.view")
        .navigationTitle(category.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    func prepareJSONExport() {
        exportDocument = JSONExportDocument(text: store.jsonExport())
        isExportPresented = true
    }

    private func saveLLMConfiguration(_ configuration: LLMConfigurationDraft) -> Bool {
        store.setLLMConfiguration(
            endpoint: configuration.endpoint,
            apiKey: configuration.apiKey,
            selectedModel: configuration.selectedModel,
            availableModelIDs: configuration.availableModels
        )
    }
}
