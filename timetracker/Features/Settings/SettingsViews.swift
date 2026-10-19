import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let store: TimeTrackerStore
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @Environment(AppSceneFeedbackRouter.self) var feedbackRouter
    #if os(macOS)
    @Environment(MacKeyboardShortcutSettings.self) var shortcutSettings
    #endif
    @State var pendingDestructiveConfirmation: SettingsDestructiveConfirmation?
    @State var isExportPresented = false
    @State private var exportDocument = JSONExportDocument(text: "")
    @State var isCheckingSync = false
    @State var dataOperationMessage: String?
    @State private var selectedCategory: SettingsCategory? = .general
    #if os(iOS)
    @State private var selectedLLMPromptKind: LLMPromptKind?
    #endif

    var body: some View {
        settingsNavigation
            .navigationTitle(AppStrings.settings)
            .appInlineNavigationTitle()
            .accessibilityIdentifier("settings.view")
            .fileExporter(
                isPresented: $isExportPresented,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "time-tracker-user-data.json"
            ) { result in
                handleExportResult(result)
            }
    }

    @ViewBuilder
    private var settingsNavigation: some View {
        #if os(macOS)
        NavigationSplitView(columnVisibility: fixedSettingsColumnVisibility) {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                SettingsCategoryRow(category: category)
                    .tag(category)
                    .accessibilityIdentifier("settings.category.\(category.rawValue)")
            }
            .listStyle(.sidebar)
            .toolbar(removing: .sidebarToggle)
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
        .bottomScrollClearance()
        #endif
    }

    #if os(macOS)
    private var fixedSettingsColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { .all },
            set: { _ in }
        )
    }
    #endif

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
        .navigationDestination(item: $selectedLLMPromptKind) { kind in
            LLMPromptInstructionsEditor(
                kind: kind,
                instructions: store.preferences.llmInstructions(for: kind),
                isEmbeddedInNavigationStack: true,
                onDismiss: { selectedLLMPromptKind = nil }
            ) { instructions in
                feedbackRouter.perform {
                    try store.setLLMPromptInstructions(instructions, for: kind)
                } != nil
            }
        }
        #endif
    }

    func prepareJSONExport() {
        dataOperationMessage = nil
        do {
            exportDocument = try JSONExportDocument(text: store.jsonExport())
            isExportPresented = true
        } catch {
            presentExportError(error)
        }
    }

    func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            dataOperationMessage = AppStrings.localized("settings.export.saved")
        case let .failure(error):
            guard (error as? CocoaError)?.code != .userCancelled else { return }
            dataOperationMessage = nil
            presentExportError(error)
        }
    }

    func presentExportError(_ error: Error) {
        feedbackRouter.present(
            title: AppStrings.localized("settings.exportJSON"),
            message: error.localizedDescription
        )
    }

    func performSettingsMutation(title: String, _ mutation: () throws -> Void) {
        feedbackRouter.perform(title: title, mutation)
    }

    func presentLLMConfiguration() {
        presentationRouter.presentLLMConfiguration(using: store)
    }

    func presentLLMPrompt(_ kind: LLMPromptKind) {
        #if os(iOS)
        selectedLLMPromptKind = kind
        #else
        presentationRouter.presentLLMPrompt(kind, using: store)
        #endif
    }
}
