import SwiftUI

struct TaskStatusPicker: View {
    @Binding var selection: TaskStatus

    var body: some View {
        Picker(AppStrings.localized("editor.task.status"), selection: $selection) {
            ForEach(TaskStatus.editableCases, id: \.self) { status in
                TaskStatusPickerOption(status: status)
                    .tag(status)
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

struct ChecklistEditorRow: View {
    @Binding var item: ChecklistEditorDraft
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void
    let focus: FocusState<UUID?>.Binding
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ChecklistCompletionButton(isCompleted: item.isCompleted) {
                withAnimation(.snappy(duration: 0.22)) {
                    item.isCompleted.toggle()
                }
            }

            TextField(AppStrings.localized("editor.checklist.itemPlaceholder"), text: $item.title)
                .textFieldStyle(.plain)
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .focused(focus, equals: item.id)
                .submitLabel(.next)
                .onSubmit(submit)

            Menu {
                Button {
                    moveUp()
                } label: {
                    Label(AppStrings.localized("common.moveUp"), systemImage: "chevron.up")
                }
                .disabled(!canMoveUp)

                Button {
                    moveDown()
                } label: {
                    Label(AppStrings.localized("common.moveDown"), systemImage: "chevron.down")
                }
                .disabled(!canMoveDown)

                Divider()

                Button(role: .destructive) {
                    delete()
                } label: {
                    Label(AppStrings.delete, systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }
}
