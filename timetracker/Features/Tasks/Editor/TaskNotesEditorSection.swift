import SwiftUI

struct TaskNotesEditorSection: View {
    @Binding var notes: String
    let validationError: TaskPersistenceValidationError?

    var body: some View {
        Section(AppStrings.localized("editor.task.notes")) {
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $notes)
                    .frame(minHeight: 88)
                    .accessibilityLabel(AppStrings.localized("editor.task.notes"))
                    .accessibilityHint(validationError?.localizedDescription ?? "")
                if let validationError {
                    TaskEditorInlineValidationMessage(
                        error: validationError,
                        accessibilityIdentifier: "task.editor.notes.error"
                    )
                }
            }
        }
    }
}
