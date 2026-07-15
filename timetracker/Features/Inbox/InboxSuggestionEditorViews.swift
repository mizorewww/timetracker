import SwiftUI

struct InboxSuggestionEditorSheet: View {
    let store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: InboxSuggestionEditorDraft
    @State private var draft: InboxSuggestionEditorDraft
    @State private var isDiscardConfirmationPresented = false

    init(store: TimeTrackerStore, initialDraft: InboxSuggestionEditorDraft) {
        self.store = store
        self.initialDraft = initialDraft
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    taskPicker
                    SymbolColorPickerRow(
                        colors: TaskColorPalette.hexValues,
                        titleKey: "inbox.suggestion.symbolColor",
                        symbolName: $draft.iconName,
                        colorHex: $draft.colorHex
                    )
                    TextField(AppStrings.localized("inbox.suggestion.reason"), text: $draft.reason, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text(.app("inbox.suggestion.editorTitle"))
                } footer: {
                    Text(.app("inbox.suggestion.editorFooter"))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(AppStrings.localized("inbox.suggestion.editorTitle"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel, action: requestCancel)
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        if store.saveInboxSuggestionDraft(draft) {
                            dismiss()
                        }
                    }
                    .disabled(draft.taskID == nil)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .platformSheetFrame(width: 500, height: 440)
        .presentationDetents([.medium, .large])
        .editorDiscardConfirmation(
            isPresented: $isDiscardConfirmationPresented,
            hasUnsavedChanges: draft != initialDraft,
            discard: discard
        )
    }

    private func requestCancel() {
        if draft == initialDraft {
            discard()
        } else {
            isDiscardConfirmationPresented = true
        }
    }

    private func discard() {
        store.inboxSuggestionEditorDraft = nil
        dismiss()
    }

    private var taskPicker: some View {
        Picker(AppStrings.localized("inbox.suggestion.targetTask"), selection: $draft.taskID) {
            Text(.app("segment.choose")).tag(Optional<UUID>.none)
            ForEach(availableTasks, id: \.id) { task in
                Label {
                    Text(store.taskPath(for: task))
                } icon: {
                    Image(systemName: ChecklistVisualSanitizer.sanitizedIcon(task.iconName))
                        .foregroundStyle(Color(hex: ChecklistVisualSanitizer.sanitizedColor(task.colorHex)) ?? .secondary)
                }
                .tag(Optional(task.id))
            }
        }
    }

    private var availableTasks: [TaskNode] {
        store.tasks.filter(store.isTaskAvailableForTracking)
    }
}
