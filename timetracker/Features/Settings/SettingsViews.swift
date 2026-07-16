import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let store: TimeTrackerStore
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State var pendingDestructiveConfirmation: SettingsDestructiveConfirmation?
    @State var isExportPresented = false
    @State private var exportDocument = JSONExportDocument(text: "")
    @State var isCheckingSync = false
    @State var syncOperationMessage: String?
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
        .alert(AppStrings.localized("alert.optimize.title"), isPresented: optimizationMessagePresented) {
            Button(AppStrings.localized("common.ok")) {
                databaseOptimizationMessage = nil
            }
        } message: {
            Text(databaseOptimizationMessage ?? "")
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
                    NavigationLink {
                        settingsForm(for: category)
                    } label: {
                        SettingsCategoryRow(category: category)
                    }
                    .accessibilityIdentifier("settings.category.\(category.rawValue)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, dynamicTypeSize.isAccessibilitySize ? 112 : 16, for: .scrollContent)
        #endif
    }

    private func settingsForm(for category: SettingsCategory) -> some View {
        Form {
            settingsSections(for: category)
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.view")
        .navigationTitle(category.title)
        .confirmationDialog(
            pendingDestructiveConfirmation.map { AppStrings.localized($0.titleKey) } ?? "",
            isPresented: destructiveConfirmationPresented,
            titleVisibility: .visible,
            presenting: pendingDestructiveConfirmation
        ) { confirmation in
            Button(AppStrings.localized(confirmation.confirmKey), role: .destructive) {
                performDestructiveConfirmation(confirmation)
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: { confirmation in
            Text(.app(confirmation.messageKey))
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    func prepareJSONExport() {
        guard let json = store.jsonExport() else { return }
        exportDocument = JSONExportDocument(text: json)
        isExportPresented = true
    }

    func presentLLMConfiguration() {
        presentationRouter.presentLLMConfiguration(using: store)
    }
}
