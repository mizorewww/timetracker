import SwiftUI

struct TaskNotesEditorSection: View {
    @Binding var notes: String

    var body: some View {
        Section(AppStrings.localized("editor.task.notes")) {
            TextField(AppStrings.localized("editor.task.notes"), text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)
        }
    }
}
