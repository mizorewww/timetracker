import SwiftUI

struct TaskCategoryEditorSheet: View {
    let store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: TaskCategoryEditorDraft
    @State private var draft: TaskCategoryEditorDraft
    @State private var isDiscardConfirmationPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var hasRequestedInitialTitleFocus = false
    @FocusState private var isTitleFocused: Bool

    init(store: TimeTrackerStore, initialDraft: TaskCategoryEditorDraft) {
        self.store = store
        self.initialDraft = initialDraft
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        let validationError = categoryValidationMessage

        NavigationStack {
            Form {
                Section(AppStrings.localized("taskCategory.editor.info")) {
                    TextField(AppStrings.localized("taskCategory.name"), text: $draft.title)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isTitleFocused = false
                        }
                    if let validationError {
                        Label(validationError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityAddTraits(.isStaticText)
                            .accessibilityIdentifier("taskCategory.validation")
                    }
                    SymbolColorPickerRow(
                        pickerAccessibilityIdentifier: "symbol.picker.open.category",
                        onOpen: {
                            isTitleFocused = false
                        },
                        symbolName: $draft.iconName,
                        colorHex: $draft.colorHex
                    )
                }

                Section {
                    Toggle(isOn: $draft.includesInForecast) {
                        Label(AppStrings.localized("taskCategory.includesForecast"), systemImage: "chart.line.uptrend.xyaxis")
                    }
                } footer: {
                    Text(.app("taskCategory.includesForecast.footer"))
                }

                if draft.categoryID != nil {
                    Section {
                        Button(role: .destructive) {
                            isDeleteConfirmationPresented = true
                        } label: {
                            Label(AppStrings.localized("taskCategory.delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(initialDraft.categoryID == nil ? AppStrings.localized("taskCategory.new") : AppStrings.localized("taskCategory.edit"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel) {
                        requestCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        if store.saveTaskCategoryDraft(draft) {
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            validationError != nil
                    )
                }
            }
        }
        .platformSheetFrame(width: 460, height: 440)
        .task {
            guard initialDraft.categoryID == nil,
                  hasRequestedInitialTitleFocus == false else { return }
            hasRequestedInitialTitleFocus = true
            isTitleFocused = true
        }
        .editorDiscardConfirmation(
            isPresented: $isDiscardConfirmationPresented,
            hasUnsavedChanges: draft != initialDraft,
            discard: cancel
        )
        .confirmationDialog(
            AppStrings.localized("taskCategory.delete.confirm.title"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(AppStrings.localized("taskCategory.delete"), role: .destructive, action: deleteCategory)
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("taskCategory.delete.confirm.message"))
        }
    }

    private func requestCancel() {
        if draft == initialDraft {
            cancel()
        } else {
            isDiscardConfirmationPresented = true
        }
    }

    private var categoryValidationMessage: String? {
        guard draft.title.isEmpty == false else { return nil }
        do {
            _ = try TaskPersistencePolicy.prepareCategory(
                title: draft.title,
                colorHex: draft.colorHex,
                iconName: draft.iconName
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func cancel() {
        dismiss()
    }

    private func deleteCategory() {
        guard let baseline = draft.baseline else { return }
        if store.deleteTaskCategory(baseline: baseline) {
            dismiss()
        }
    }
}
