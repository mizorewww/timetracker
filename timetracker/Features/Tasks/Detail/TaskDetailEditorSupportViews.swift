import SwiftUI

struct TaskDetailEditorSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

struct TaskDetailStatusControl: View {
    @Binding var selection: TaskStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.app("editor.task.status"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(AppStrings.localized("editor.task.status"), selection: $selection) {
                ForEach(TaskStatus.editableCases, id: \.self) { status in
                    Text(status.displayName)
                        .tag(status)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
