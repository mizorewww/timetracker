import MarkdownView
import SwiftUI

struct LLMPromptInstructionsEditor: View {
    let kind: LLMPromptKind
    let onSave: (String) -> Bool
    private let isEmbeddedInNavigationStack: Bool
    private let onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var mode = LLMPromptInstructionsEditorMode.edit
    @State private var validationError: LLMPromptInstructionsValidationError?
    @State private var isDiscardConfirmationPresented = false
    @State private var isSaving = false

    private let initialInstructions: String

    init(
        kind: LLMPromptKind,
        instructions: String,
        isEmbeddedInNavigationStack: Bool = false,
        onDismiss: (() -> Void)? = nil,
        onSave: @escaping (String) -> Bool
    ) {
        let initialInstructions = (
            try? AppPreferenceValueSanitizer.llmPromptInstructions(
                instructions,
                for: kind
            )
        ) ?? kind.defaultInstructions
        self.kind = kind
        self.initialInstructions = initialInstructions
        self.isEmbeddedInNavigationStack = isEmbeddedInNavigationStack
        self.onDismiss = onDismiss
        self.onSave = onSave
        _draft = State(initialValue: initialInstructions)
        _validationError = State(
            initialValue: Self.validationError(for: initialInstructions, kind: kind)
        )
    }

    private var hasUnsavedChanges: Bool {
        guard let normalizedDraft else { return true }
        return normalizedDraft != initialInstructions
    }

    private var byteCount: Int {
        if let normalizedDraft {
            return normalizedDraft.utf8.count
        }
        if case let .some(.byteLimitExceeded(actual, _)) = validationError {
            return actual
        }
        return draft.utf8.count
    }

    private var normalizedDraft: String? {
        try? AppPreferenceValueSanitizer.llmPromptInstructions(
            draft,
            for: kind
        )
    }

    private var accessibilityID: String {
        kind.settingsAccessibilityID
    }

    var body: some View {
        Group {
            if isEmbeddedInNavigationStack {
                editorContent
            } else {
                NavigationStack {
                    editorContent
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 520)
        #endif
        .onChange(of: draft) { _, newValue in
            validationError = Self.validationError(for: newValue, kind: kind)
        }
        .editorDiscardConfirmation(
            isPresented: $isDiscardConfirmationPresented,
            hasUnsavedChanges: hasUnsavedChanges,
            discard: dismissEditor
        )
    }

    private var editorContent: some View {
        Form {
            Section {
                Picker(
                    AppStrings.localized(kind.settingsTitleKey),
                    selection: $mode
                ) {
                    Text(AppStrings.edit)
                        .tag(LLMPromptInstructionsEditorMode.edit)
                    Text(.app("task.notes.preview"))
                        .tag(LLMPromptInstructionsEditorMode.preview)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityIdentifier("\(accessibilityID).mode")

                instructionsContent

                VStack(alignment: .leading, spacing: 6) {
                    if let validationError {
                        Label(
                            validationError.localizedDescription,
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("\(accessibilityID).error")
                    }

                    Text(
                        String.localizedStringWithFormat(
                            AppStrings.localized(
                                "settings.llm.prompt.byteCountFormat"
                            ),
                            Int64(byteCount),
                            Int64(
                                AppPreferenceValueSanitizer
                                    .maximumLLMPromptInstructionsByteCount
                            )
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(
                        validationError == nil ? Color.secondary : Color.red
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier("\(accessibilityID).byteCount")
                }

                Button(action: restoreDefault) {
                    Label(
                        AppStrings.localized(
                            "settings.llm.prompt.restoreDefault"
                        ),
                        systemImage: "arrow.counterclockwise"
                    )
                }
                .disabled(draft == kind.defaultInstructions)
                .accessibilityIdentifier("\(accessibilityID).restoreDefault")
            } header: {
                Text(AppStrings.localized(kind.settingsTitleKey))
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.localized(kind.settingsFooterKey))
                    Text(AppStrings.localized("settings.llm.prompt.footer"))
                }
            }

            Section {
                DisclosureGroup {
                    Text(kind.fixedResponseContract)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } label: {
                    Text(AppStrings.localized("settings.llm.prompt.fixedRules"))
                }
                .accessibilityIdentifier("\(accessibilityID).fixedRules")

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 28), spacing: 8),
                            ],
                            spacing: 8
                        ) {
                            ForEach(
                                SymbolCatalog.aiSuggestionSymbolNames,
                                id: \.self
                            ) { symbol in
                                Image(systemName: symbol)
                                    .font(.body)
                                    .frame(width: 28, height: 28)
                                    .accessibilityLabel(symbol)
                            }
                        }
                        HStack(spacing: 8) {
                            ForEach(
                                TaskColorPalette.hexValues,
                                id: \.self
                            ) { hex in
                                Circle()
                                    .fill(TaskColorPalette.pickerColor(for: hex))
                                    .frame(width: 20, height: 20)
                                    .accessibilityLabel(
                                        TaskColorPalette.accessibilityName(
                                            for: hex
                                        )
                                    )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text(AppStrings.localized("settings.llm.prompt.allowedVisuals"))
                }
                .accessibilityIdentifier("\(accessibilityID).allowedVisuals")
            } header: {
                Text(AppStrings.localized("settings.llm.prompt.contractSection"))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(
            AppStrings.localized(kind.settingsEditorTitleKey)
        )
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEmbeddedInNavigationStack)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppStrings.cancel, action: requestDismiss)
                    .disabled(isSaving)
                    .accessibilityIdentifier("\(accessibilityID).cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(AppStrings.localized("common.save"))
                    }
                }
                .disabled(validationError != nil || !hasUnsavedChanges || isSaving)
                .accessibilityIdentifier("\(accessibilityID).save")
            }
        }
    }

    @ViewBuilder
    private var instructionsContent: some View {
        if mode == .preview {
            MarkdownView(draft)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .accessibilityIdentifier("\(accessibilityID).preview")
        } else {
            TextEditor(text: $draft)
                .font(.body)
                .frame(minHeight: 220)
                .accessibilityLabel(
                    AppStrings.localized(kind.settingsTitleKey)
                )
                .accessibilityIdentifier("\(accessibilityID).editor")
        }
    }

    private func requestDismiss() {
        if hasUnsavedChanges {
            isDiscardConfirmationPresented = true
        } else {
            dismissEditor()
        }
    }

    private func save() {
        guard let normalized = try? AppPreferenceValueSanitizer
            .llmPromptInstructions(draft, for: kind)
        else {
            validationError = Self.validationError(for: draft, kind: kind)
            return
        }
        isSaving = true
        Task { @MainActor in
            // Let the saving state render before the synchronous store commit
            // (locked cross-process file IO) runs.
            await Task.yield()
            let didSave = onSave(normalized)
            isSaving = false
            if didSave {
                dismissEditor()
            }
        }
    }

    private func dismissEditor() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private func restoreDefault() {
        draft = kind.defaultInstructions
    }

    private static func validationError(
        for value: String,
        kind: LLMPromptKind
    ) -> LLMPromptInstructionsValidationError? {
        do {
            _ = try AppPreferenceValueSanitizer.llmPromptInstructions(
                value,
                for: kind
            )
            return nil
        } catch let error as LLMPromptInstructionsValidationError {
            return error
        } catch {
            assertionFailure("Unexpected prompt instructions validation error: \(error)")
            return nil
        }
    }
}

private enum LLMPromptInstructionsEditorMode: Hashable {
    case edit
    case preview
}
