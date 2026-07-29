import SwiftUI

struct ChecklistEditorRow: View {
    @Binding var item: ChecklistEditorDraft
    let delete: () -> Void
    let toggleCompletion: () -> Void
    let focus: FocusState<UUID?>.Binding
    let submit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ChecklistCompletionButton(
                isCompleted: item.isCompleted,
                colorHex: item.colorHex,
                action: toggleCompletion
            )
            .accessibilityLabel(
                item.title.isEmpty
                    ? AppStrings.localized("editor.checklist.completionControl")
                    : item.title
            )
            .accessibilityIdentifier(
                "task.editor.checklist.completion.\(item.id.uuidString)"
            )

            SymbolColorPickerButton(
                symbolName: $item.iconName,
                colorHex: $item.colorHex,
                showsTitle: false,
                pickerAccessibilityIdentifier:
                "symbol.picker.open.checklist.\(item.id.uuidString)",
                onOpen: {
                    focus.wrappedValue = nil
                }
            )
            .buttonStyle(.plain)
            .frame(
                width: AppLayout.minimumInteractiveTarget,
                height: AppLayout.minimumInteractiveTarget
            )

            ChecklistTitleTextField(
                title: $item.title,
                isCompleted: item.isCompleted,
                boundedLineLimit: nil,
                accessibilityIdentifier:
                "task.editor.checklist.title.\(item.id.uuidString)",
                submit: submit
            )
            .focused(focus, equals: item.id)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        #if os(iOS)
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                deleteAction(source: "swipe")
            }
        #endif
            .contextMenu {
                deleteAction(source: "context")
            }
            .accessibilityElement(children: .contain)
    }

    private func deleteAction(source: String) -> some View {
        Button(role: .destructive, action: delete) {
            Label(AppStrings.delete, systemImage: "trash")
        }
        .accessibilityIdentifier(
            "task.editor.checklist.delete.\(source).\(item.id.uuidString)"
        )
    }
}
