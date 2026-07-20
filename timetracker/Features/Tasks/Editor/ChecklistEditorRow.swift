import SwiftUI

struct ChecklistEditorRow: View {
    @Binding var item: ChecklistEditorDraft
    let isSorting: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void
    let toggleCompletion: () -> Void
    let focus: FocusState<UUID?>.Binding
    let submit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ChecklistCompletionButton(
                isCompleted: item.isCompleted,
                colorHex: item.colorHex,
                action: toggleCompletion
            )
            .padding(.top, 2)
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

            TextField(AppStrings.localized("editor.checklist.itemPlaceholder"), text: $item.title, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .focused(focus, equals: item.id)
                .submitLabel(.done)
                .onSubmit(submit)
                .labelsHidden()
                .accessibilityLabel(AppStrings.localized("editor.checklist.itemPlaceholder"))
                .accessibilityIdentifier(
                    "task.editor.checklist.title.\(item.id.uuidString)"
                )
                .onChange(of: item.title) { _, newValue in
                    guard newValue.contains(where: \.isNewline) else { return }
                    item.title = ChecklistInputTextNormalizer.collapsingNewlines(in: newValue)
                    submit()
                }

            sortingControls
            Button(role: .destructive) {
                delete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .frame(
                        width: AppLayout.minimumInteractiveTarget,
                        height: AppLayout.minimumInteractiveTarget
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.delete)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .opacity(isSorting ? 0.98 : 1)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var sortingControls: some View {
        #if os(macOS)
        if isSorting {
            HStack(spacing: 4) {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                        .frame(width: 28, height: 28)
                }
                .disabled(!canMoveUp)
                .accessibilityLabel(AppStrings.localized("common.moveUp"))

                Button(action: moveDown) {
                    Image(systemName: "chevron.down")
                        .frame(width: 28, height: 28)
                }
                .disabled(!canMoveDown)
                .accessibilityLabel(AppStrings.localized("common.moveDown"))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        #endif
    }
}
