import SwiftUI

struct TaskNotesEditorSection: View {
    @Binding var notes: String
    let validationError: TaskPersistenceValidationError?
    let focusedTextField: FocusState<TaskEditorTextField?>.Binding
    @State private var mode: TaskNotesEditorMode

    init(
        notes: Binding<String>,
        validationError: TaskPersistenceValidationError?,
        startsInPreview: Bool = false,
        focusedTextField: FocusState<TaskEditorTextField?>.Binding
    ) {
        _notes = notes
        self.validationError = validationError
        self.focusedTextField = focusedTextField
        let hasNotes = notes.wrappedValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty == false
        _mode = State(
            initialValue: startsInPreview && hasNotes ? .preview : .source
        )
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                notesContent
                if let validationError {
                    TaskEditorInlineValidationMessage(
                        error: validationError,
                        accessibilityIdentifier: "task.editor.notes.error"
                    )
                }
            }
        } header: {
            HStack {
                Text(.app("editor.task.notes"))
                Spacer()
                Picker(
                    AppStrings.localized("editor.task.notes"),
                    selection: $mode
                ) {
                    Text(AppStrings.edit).tag(TaskNotesEditorMode.source)
                    Text(.app("task.notes.preview")).tag(TaskNotesEditorMode.preview)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("task.editor.notes.mode")
            }
        }
    }

    @ViewBuilder
    private var notesContent: some View {
        switch mode {
        case .source:
            TextEditor(text: $notes)
                .frame(minHeight: 88)
                .focused(focusedTextField, equals: .notes)
                .accessibilityLabel(AppStrings.localized("editor.task.notes"))
                .accessibilityHint(validationError?.localizedDescription ?? "")
                .accessibilityIdentifier("task.editor.notes.field")
        case .preview:
            if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(
                    AppStrings.localized("task.notes.empty"),
                    systemImage: "note.text"
                )
                .foregroundStyle(.secondary)
            } else {
                TaskNotesMarkdownPreview(markdown: notes)
            }
        }
    }
}

private enum TaskNotesEditorMode: Hashable {
    case source
    case preview
}
