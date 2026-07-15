import SwiftUI

struct TaskStatusPicker: View {
    @Binding var selection: TaskStatus
    var disabledStatuses: Set<TaskStatus> = []

    var body: some View {
        Picker(AppStrings.localized("editor.task.status"), selection: $selection) {
            ForEach(TaskStatus.editableCases, id: \.self) { status in
                TaskStatusPickerOption(status: status)
                    .tag(status)
                    .disabled(disabledStatuses.contains(status))
            }
        }
        .pickerStyle(.inline)
    }
}

struct TaskStatusPickerOption: View {
    let status: TaskStatus

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.displayName)
                Text(status.exampleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: status.symbolName)
                .foregroundStyle(Color(hex: status.colorHex) ?? .secondary)
        }
    }
}
