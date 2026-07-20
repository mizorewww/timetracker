import SwiftUI

enum TaskNotesInteractionStyle: Hashable {
    case editor
    case expandablePreview
}

struct TaskNotesEditorSection: View {
    @Binding var notes: String
    let validationError: TaskPersistenceValidationError?
    let interactionStyle: TaskNotesInteractionStyle
    let focusedTextField: FocusState<TaskEditorTextField?>.Binding
    @State private var mode: TaskNotesEditorMode

    init(
        notes: Binding<String>,
        validationError: TaskPersistenceValidationError?,
        interactionStyle: TaskNotesInteractionStyle = .editor,
        focusedTextField: FocusState<TaskEditorTextField?>.Binding
    ) {
        _notes = notes
        self.validationError = validationError
        self.interactionStyle = interactionStyle
        self.focusedTextField = focusedTextField
        _mode = State(
            initialValue: interactionStyle == .expandablePreview
                ? .preview
                : .source
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
                modeControl
            }
        }
    }

    @ViewBuilder
    private var modeControl: some View {
        switch interactionStyle {
        case .editor:
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
            .onChange(of: mode) { _, newMode in
                guard newMode == .preview else { return }
                focusedTextField.wrappedValue = nil
            }
        case .expandablePreview:
            switch mode {
            case .source:
                Button(AppStrings.done, action: finishEditing)
                    .accessibilityLabel(
                        AppStrings.localized("task.notes.doneEditing")
                    )
                    .accessibilityIdentifier("task.editor.notes.done")
            case .preview:
                Button(AppStrings.edit) {
                    mode = .source
                }
                .accessibilityLabel(
                    AppStrings.localized("task.notes.edit")
                )
                .accessibilityIdentifier("task.editor.notes.edit")
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
                .task {
                    guard interactionStyle == .expandablePreview else { return }
                    focusedTextField.wrappedValue = .notes
                }
        case .preview:
            if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(
                    AppStrings.localized("task.notes.empty"),
                    systemImage: "note.text"
                )
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("task.editor.notes.empty")
            } else {
                TaskNotesMarkdownPreview(markdown: notes)
            }
        }
    }

    private func finishEditing() {
        focusedTextField.wrappedValue = nil
        mode = .preview
    }
}

private enum TaskNotesEditorMode: Hashable {
    case source
    case preview
}
