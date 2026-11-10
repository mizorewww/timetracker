import MarkdownView
import SwiftUI

struct TaskNotesMarkdownPreview: View {
    let markdown: String

    var body: some View {
        MarkdownView(markdown)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
            .accessibilityValue(markdown)
            .accessibilityIdentifier("task.detail.notes.markdown")
    }
}
