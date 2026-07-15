import SwiftUI

struct LLMConfigurationEditor: View {
    let onSave: (LLMConfigurationDraft) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draft: LLMConfigurationDraft
    @State private var feedback: ConnectionFeedback?
    @State private var isTesting = false
    @State private var isDiscardConfirmationPresented = false
    @State private var fetchTask: Task<Void, Never>?
    @State private var fetchRequestID = UUID()

    private let initialDraft: LLMConfigurationDraft

    init(
        endpoint: String,
        apiKey: String,
        selectedModel: String,
        availableModels: [String],
        onSave: @escaping (LLMConfigurationDraft) -> Bool
    ) {
        let initialDraft = LLMConfigurationDraft(
            endpoint: endpoint,
            apiKey: apiKey,
            selectedModel: selectedModel,
            availableModels: availableModels
        ).normalized
        self.initialDraft = initialDraft
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    private var hasUnsavedChanges: Bool {
        draft.normalized != initialDraft
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SettingsTextFieldRow(
                        title: AppStrings.localized("settings.llm.endpoint"),
                        text: $draft.endpoint,
                        systemImage: "link",
                        tint: .purple,
                        fieldAlignment: .leading
                    )

                    SettingsTextFieldRow(
                        title: AppStrings.localized("settings.llm.apiKey"),
                        text: $draft.apiKey,
                        systemImage: "key.fill",
                        tint: .orange,
                        isSecure: true,
                        fieldAlignment: .leading
                    )

                    Button(action: testConnection) {
                        HStack(spacing: 12) {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 28, height: 28)
                            } else {
                                SettingsRowIcon(systemImage: "network", tint: .blue)
                            }
                            Text(AppStrings.localized("settings.llm.testConnection"))
                            Spacer(minLength: 8)
                        }
                        .frame(minHeight: 32)
                    }
                    .disabled(isTesting || !credentialsAreValid)

                    if let feedback {
                        Label(feedback.message, systemImage: feedback.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(feedback.isSuccess ? Color.green : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text(.app("settings.llm.connection"))
                } footer: {
                    Text(.app("settings.llm.connectionFooter"))
                }

                Section {
                    if draft.availableModels.isEmpty {
                        ContentUnavailableView(
                            AppStrings.localized("settings.llm.noModels"),
                            systemImage: "cpu",
                            description: Text(.app("settings.llm.testToLoadModels"))
                        )
                    } else {
                        Picker(AppStrings.localized("settings.llm.model"), selection: $draft.selectedModel) {
                            ForEach(draft.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    }
                } header: {
                    Text(.app("settings.llm.model"))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(AppStrings.localized("settings.llm.configure"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel, action: requestDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save"), action: save)
                        .disabled(!draft.canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 540)
        #endif
        .onChange(of: draft.endpoint) { _, _ in invalidateTestResult() }
        .onChange(of: draft.apiKey) { _, _ in invalidateTestResult() }
        .onDisappear { fetchTask?.cancel() }
        .editorDiscardConfirmation(
            isPresented: $isDiscardConfirmationPresented,
            hasUnsavedChanges: hasUnsavedChanges,
            discard: { dismiss() }
        )
    }

    private var credentialsAreValid: Bool {
        LLMModelService.modelsURL(endpoint: draft.endpoint) != nil &&
            !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func requestDismiss() {
        if hasUnsavedChanges {
            isDiscardConfirmationPresented = true
        } else {
            dismiss()
        }
    }

    private func save() {
        if onSave(draft.normalized) {
            dismiss()
        }
    }

    private func invalidateTestResult() {
        fetchTask?.cancel()
        fetchRequestID = UUID()
        isTesting = false
        feedback = nil

        if draft.credentialFingerprint == initialDraft.credentialFingerprint {
            draft.availableModels = initialDraft.availableModels
            draft.selectedModel = initialDraft.selectedModel
        } else {
            draft.availableModels = []
            draft.selectedModel = ""
        }
    }

    private func testConnection() {
        fetchTask?.cancel()
        let endpoint = draft.endpoint
        let apiKey = draft.apiKey
        let fingerprint = draft.credentialFingerprint
        let requestID = UUID()
        fetchRequestID = requestID
        isTesting = true
        feedback = nil

        fetchTask = Task {
            do {
                let models = try await LLMModelService().fetchModels(endpoint: endpoint, apiKey: apiKey)
                guard !Task.isCancelled,
                      fetchRequestID == requestID,
                      draft.credentialFingerprint == fingerprint else { return }
                draft.availableModels = models
                if !models.contains(draft.selectedModel) {
                    draft.selectedModel = models.first ?? ""
                }
                feedback = ConnectionFeedback(
                    message: models.isEmpty
                        ? AppStrings.localized("settings.llm.noModels")
                        : String(format: AppStrings.localized("settings.llm.fetchSuccess"), models.count),
                    isSuccess: !models.isEmpty
                )
            } catch is CancellationError {
                if fetchRequestID == requestID {
                    isTesting = false
                }
                return
            } catch {
                guard !Task.isCancelled,
                      fetchRequestID == requestID,
                      draft.credentialFingerprint == fingerprint else { return }
                draft.availableModels = []
                draft.selectedModel = ""
                feedback = ConnectionFeedback(
                    message: String(format: AppStrings.localized("settings.llm.fetchFailed"), error.localizedDescription),
                    isSuccess: false
                )
            }
            if fetchRequestID == requestID {
                isTesting = false
            }
        }
    }
}

private struct ConnectionFeedback {
    let message: String
    let isSuccess: Bool
}
