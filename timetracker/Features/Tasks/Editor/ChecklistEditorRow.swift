import SwiftUI

struct ChecklistEditorRow: View {
    @Binding var item: ChecklistEditorDraft
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
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

            macOSOrderingControls
            actionsMenu
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        #if os(iOS)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                deleteAction(source: "swipe")
            }
        #else
            .contextMenu {
                contextMenuActions
            }
        #endif
            .accessibilityElement(children: .contain)
    }

    private var actionsMenu: some View {
        Menu {
            orderingActions
            Divider()
            deleteAction(source: "menu")
        } label: {
            TrailingMenuLabel(systemImage: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .menuIndicator(.hidden)
        .frame(
            width: AppLayout.minimumInteractiveTarget,
            height: AppLayout.minimumInteractiveTarget
        )
        .contentShape(Rectangle())
        .accessibilityLabel(AppStrings.localized("common.more"))
        .accessibilityIdentifier(
            "task.editor.checklist.more.\(item.id.uuidString)"
        )
    }

    @ViewBuilder
    private var orderingActions: some View {
        Button(action: moveUp) {
            Label(
                AppStrings.localized("common.moveUp"),
                systemImage: "chevron.up"
            )
        }
        .disabled(!canMoveUp)

        Button(action: moveDown) {
            Label(
                AppStrings.localized("common.moveDown"),
                systemImage: "chevron.down"
            )
        }
        .disabled(!canMoveDown)
    }

    @ViewBuilder
    private var contextMenuActions: some View {
        if canMoveUp {
            Button(action: moveUp) {
                Label(
                    AppStrings.localized("common.moveUp"),
                    systemImage: "chevron.up"
                )
            }
        }
        if canMoveDown {
            Button(action: moveDown) {
                Label(
                    AppStrings.localized("common.moveDown"),
                    systemImage: "chevron.down"
                )
            }
        }
        if canMoveUp || canMoveDown {
            Divider()
        }
        deleteAction(source: "context")
    }

    private func deleteAction(source: String) -> some View {
        Button(role: .destructive, action: delete) {
            Label(AppStrings.delete, systemImage: "trash")
        }
        .accessibilityIdentifier(
            "task.editor.checklist.delete.\(source).\(item.id.uuidString)"
        )
    }

    @ViewBuilder
    private var macOSOrderingControls: some View {
        #if os(macOS)
        HStack(spacing: 4) {
            Button(action: moveUp) {
                Image(systemName: "chevron.up")
                    .frame(width: 28, height: 28)
            }
            .disabled(!canMoveUp)
            .accessibilityLabel(AppStrings.localized("common.moveUp"))
            .accessibilityIdentifier(
                "task.editor.checklist.moveUp.\(item.id.uuidString)"
            )

            Button(action: moveDown) {
                Image(systemName: "chevron.down")
                    .frame(width: 28, height: 28)
            }
            .disabled(!canMoveDown)
            .accessibilityLabel(AppStrings.localized("common.moveDown"))
            .accessibilityIdentifier(
                "task.editor.checklist.moveDown.\(item.id.uuidString)"
            )
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        #endif
    }
}
