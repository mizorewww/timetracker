import SwiftUI

struct TaskQuantityEntryEditorSheet: View {
    let store: TimeTrackerStore
    let route: TaskQuantityEntryEditorRoute
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskQuantityEntryEditorDraft
    @State private var isDiscardConfirmationPresented = false
    @State private var isDeleteConfirmationPresented = false
    @FocusState private var isAmountFocused: Bool

    init(store: TimeTrackerStore, route: TaskQuantityEntryEditorRoute) {
        self.store = store
        self.route = route
        _draft = State(initialValue: route.initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        TextField(
                            AppStrings.localized(
                                "task.quantity.entry.editor.amount"
                            ),
                            value: $draft.amount,
                            format: .number.grouping(.never)
                        )
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .focused($isAmountFocused)
                        .accessibilityIdentifier(
                            "task.detail.quantity.amount"
                        )
                    } label: {
                        Text(.app("task.quantity.entry.editor.amount"))
                    }
                    LabeledContent(
                        AppStrings.localized(
                            "task.quantity.entry.editor.unit"
                        ),
                        value: route.unitLabel
                    )
                    DatePicker(
                        AppStrings.localized(
                            "task.quantity.entry.editor.date"
                        ),
                        selection: $draft.recordedAt,
                        in: TaskQuantityEntryEditorActions.allowedDateRange,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityIdentifier("task.detail.quantity.date")

                    if draft.isValid == false {
                        TaskEditorInlineErrorMessage(
                            message: TaskQuantityEntryEditorActions
                                .validationMessage(for: draft),
                            accessibilityIdentifier:
                                "task.detail.quantity.validation"
                        )
                    }
                } header: {
                    Text(.app("task.quantity.entry.editor.section"))
                }

                if route.isEditing {
                    Section {
                        Button(role: .destructive) {
                            isDeleteConfirmationPresented = true
                        } label: {
                            Label(
                                AppStrings.localized(
                                    "task.quantity.entry.editor.delete"
                                ),
                                systemImage: "trash"
                            )
                        }
                        .accessibilityIdentifier(
                            "task.detail.quantity.delete"
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(
                AppStrings.localized(
                    route.isEditing
                        ? "task.quantity.entry.editor.editTitle"
                        : "task.quantity.entry.editor.addTitle"
                )
            )
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel, action: requestCancel)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier(
                            "task.detail.quantity.cancel"
                        )
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save"), action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.isValid == false)
                        .accessibilityIdentifier(
                            "task.detail.quantity.save"
                        )
                }
            }
        }
        .platformSheetFrame(width: 480, height: 500)
        .presentationDetents([.large])
        .editorDiscardConfirmation(
            isPresented: $isDiscardConfirmationPresented,
            hasUnsavedChanges: draft != route.initialDraft,
            discard: dismiss.callAsFunction
        )
        .confirmationDialog(
            AppStrings.localized("task.quantity.entry.editor.deleteTitle"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                AppStrings.localized(
                    "task.quantity.entry.editor.deleteConfirm"
                ),
                role: .destructive,
                action: delete
            )
            .accessibilityIdentifier(
                "task.detail.quantity.delete.confirm"
            )
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("task.quantity.entry.editor.deleteMessage"))
        }
    }

    private func requestCancel() {
        isAmountFocused = false
        if draft == route.initialDraft {
            dismiss()
        } else {
            isDiscardConfirmationPresented = true
        }
    }

    private func save() {
        isAmountFocused = false
        if TaskQuantityEntryEditorActions.save(
            store: store,
            route: route,
            draft: draft
        ) {
            dismiss()
        }
    }

    private func delete() {
        if TaskQuantityEntryEditorActions.delete(
            store: store,
            route: route
        ) {
            dismiss()
        }
    }
}
