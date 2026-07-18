import SwiftUI

struct LLMTaskPlanInstructionsEditor: View {
    let onSave: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var validationError: LLMTaskPlanInstructionsValidationError?
    @State private var isDiscardConfirmationPresented = false

    private let initialInstructions: String

    init(
        instructions: String,
        onSave: @escaping (String) -> Bool
    ) {
        let initialInstructions = (
            try? AppPreferenceValueSanitizer.llmTaskPlanInstructions(instructions)
        ) ?? LLMTaskPlanPrompt.defaultInstructions
        self.initialInstructions = initialInstructions
        self.onSave = onSave
        _draft = State(initialValue: initialInstructions)
        _validationError = State(initialValue: Self.validationError(for: initialInstructions))
    }

    private var hasUnsavedChanges: Bool {
        draft != initialInstructions
    }

    private var byteCount: Int {
        draft.utf8.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $draft)
                        .font(.body)
                        .frame(minHeight: 220)
                        .accessibilityLabel(
                            AppStrings.localized("settings.llm.taskPlanInstructions")
                        )
                        .accessibilityIdentifier("settings.llm.taskPlanInstructions.editor")

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
                            .accessibilityIdentifier(
                                "settings.llm.taskPlanInstructions.error"
                            )
                        }

                        Text(
                            String.localizedStringWithFormat(
                                AppStrings.localized(
                                    "settings.llm.taskPlanInstructions.byteCountFormat"
                                ),
                                Int64(byteCount),
                                Int64(
                                    AppPreferenceValueSanitizer
                                        .maximumLLMTaskPlanInstructionsByteCount
                                )
                            )
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(
                            validationError == nil ? Color.secondary : Color.red
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityIdentifier(
                            "settings.llm.taskPlanInstructions.byteCount"
                        )
                    }

                    Button(action: restoreDefault) {
                        Label(
                            AppStrings.localized(
                                "settings.llm.taskPlanInstructions.restoreDefault"
                            ),
                            systemImage: "arrow.counterclockwise"
                        )
                    }
                    .disabled(draft == LLMTaskPlanPrompt.defaultInstructions)
                    .accessibilityIdentifier(
                        "settings.llm.taskPlanInstructions.restoreDefault"
                    )
                } header: {
                    Text(.app("settings.llm.taskPlanInstructions"))
                } footer: {
                    Text(.app("settings.llm.taskPlanInstructions.footer"))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(
                AppStrings.localized("settings.llm.taskPlanInstructions.editorTitle")
            )
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel, action: requestDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save"), action: save)
                        .disabled(validationError != nil || !hasUnsavedChanges)
                        .accessibilityIdentifier(
                            "settings.llm.taskPlanInstructions.save"
                        )
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 520)
        #endif
        .onChange(of: draft) { _, newValue in
            validationError = Self.validationError(for: newValue)
        }
        .editorDiscardConfirmation(
            isPresented: $isDiscardConfirmationPresented,
            hasUnsavedChanges: hasUnsavedChanges,
            discard: { dismiss() }
        )
    }

    private func requestDismiss() {
        if hasUnsavedChanges {
            isDiscardConfirmationPresented = true
        } else {
            dismiss()
        }
    }

    private func save() {
        guard let normalized = try? AppPreferenceValueSanitizer
            .llmTaskPlanInstructions(draft) else {
            validationError = Self.validationError(for: draft)
            return
        }
        if onSave(normalized) {
            dismiss()
        }
    }

    private func restoreDefault() {
        draft = LLMTaskPlanPrompt.defaultInstructions
    }

    private static func validationError(
        for value: String
    ) -> LLMTaskPlanInstructionsValidationError? {
        do {
            _ = try AppPreferenceValueSanitizer.llmTaskPlanInstructions(value)
            return nil
        } catch let error as LLMTaskPlanInstructionsValidationError {
            return error
        } catch {
            assertionFailure("Unexpected task-plan instructions validation error: \(error)")
            return nil
        }
    }
}
