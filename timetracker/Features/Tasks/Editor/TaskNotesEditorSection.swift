import SwiftUI

struct TaskNotesEditorSection: View {
    @Binding var notes: String

    var body: some View {
        Section(AppStrings.localized("editor.task.notes")) {
            TextEditor(text: $notes)
                .frame(minHeight: 88)
        }
    }
}
