import SwiftUI

struct TaskEditorForm: View {
    @ObservedObject var store: TimeTrackerStore
    @Binding var draft: TaskEditorDraft
    let colors: [String]
    let focusedChecklistDraftID: FocusState<UUID?>.Binding
    let orderedChecklistIndices: [Int]
    let moveChecklistItem: (Int, Int) -> Void
    let addChecklistItem: (Int?) -> Void

    var body: some View {
        Form {
            TaskInfoEditorSection(
                store: store,
                draft: $draft,
                colors: colors
            )
            TaskPlanEditorSection(draft: $draft)
            TaskChecklistEditorSection(
                checklistItems: $draft.checklistItems,
                focusedChecklistDraftID: focusedChecklistDraftID,
                orderedChecklistIndices: orderedChecklistIndices,
                moveChecklistItem: moveChecklistItem,
                addChecklistItem: addChecklistItem
            )
            TaskNotesEditorSection(notes: $draft.notes)
        }
        .formStyle(.grouped)
    }
}

private struct TaskInfoEditorSection: View {
    @ObservedObject var store: TimeTrackerStore
    @Binding var draft: TaskEditorDraft
    let colors: [String]

    var body: some View {
        Section(AppStrings.localized("editor.task.info")) {
            TextField(AppStrings.localized("editor.task.name"), text: $draft.title)
            TaskStatusPicker(selection: $draft.status)
            parentPicker
            SymbolColorPickerRow(
                colors: colors,
                symbolName: $draft.iconName,
                colorHex: $draft.colorHex
            )
        }
    }

    private var parentPicker: some View {
        Picker(AppStrings.localized("editor.task.parent"), selection: $draft.parentID) {
            Text(.app("editor.task.rootLevel")).tag(Optional<UUID>.none)
            ForEach(store.validParentTasks(for: draft.taskID), id: \.id) { task in
                Text(indentedTitle(task)).tag(Optional(task.id))
            }
        }
    }

    private func indentedTitle(_ task: TaskNode) -> String {
        String(repeating: "  ", count: task.depth) + task.title
    }
}

private struct TaskPlanEditorSection: View {
    @Binding var draft: TaskEditorDraft

    var body: some View {
        Section(AppStrings.localized("editor.task.plan")) {
            Stepper(value: estimatedMinutesBinding, in: 0...600, step: 15) {
                LabeledContent(
                    AppStrings.localized("editor.task.estimate"),
                    value: estimatedMinutesLabel
                )
            }

            Toggle(AppStrings.localized("editor.task.setDue"), isOn: $draft.hasDueDate)
            if draft.hasDueDate {
                DatePicker(
                    AppStrings.localized("editor.task.due"),
                    selection: $draft.dueAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
        }
    }

    private var estimatedMinutesBinding: Binding<Int> {
        Binding {
            draft.estimatedMinutes ?? 0
        } set: { value in
            draft.estimatedMinutes = value == 0 ? nil : value
        }
    }

    private var estimatedMinutesLabel: String {
        draft.estimatedMinutes.map {
            String(format: AppStrings.localized("common.minutes"), $0)
        } ?? AppStrings.localized("editor.task.notSet")
    }
}

private struct TaskChecklistEditorSection: View {
    @Binding var checklistItems: [ChecklistEditorDraft]
    let focusedChecklistDraftID: FocusState<UUID?>.Binding
    let orderedChecklistIndices: [Int]
    let moveChecklistItem: (Int, Int) -> Void
    let addChecklistItem: (Int?) -> Void

    var body: some View {
        Section {
            checklistRows
            addButton
        } header: {
            Text(.app("editor.checklist.title"))
        } footer: {
            Text(.app("editor.checklist.footer"))
        }
    }

    @ViewBuilder
    private var checklistRows: some View {
        if checklistItems.isEmpty {
            Text(.app("editor.checklist.empty"))
                .foregroundStyle(.secondary)
        }

        ForEach(Array(orderedChecklistIndices.enumerated()), id: \.element) { visualIndex, index in
            ChecklistEditorRow(
                item: $checklistItems[index],
                canMoveUp: visualIndex > 0,
                canMoveDown: visualIndex < orderedChecklistIndices.count - 1,
                moveUp: { moveChecklistItem(atVisualIndex: visualIndex, direction: -1) },
                moveDown: { moveChecklistItem(atVisualIndex: visualIndex, direction: 1) },
                delete: { checklistItems.remove(at: index) },
                focus: focusedChecklistDraftID,
                submit: { addChecklistItem(visualIndex) }
            )
        }
    }

    private var addButton: some View {
        Button {
            addChecklistItem(nil)
        } label: {
            Label(AppStrings.localized("editor.checklist.add"), systemImage: "plus")
        }
    }

    private func moveChecklistItem(atVisualIndex visualIndex: Int, direction: Int) {
        let targetVisualIndex = visualIndex + direction
        guard orderedChecklistIndices.indices.contains(visualIndex),
              orderedChecklistIndices.indices.contains(targetVisualIndex) else {
            return
        }
        moveChecklistItem(
            orderedChecklistIndices[visualIndex],
            orderedChecklistIndices[targetVisualIndex]
        )
    }
}

private struct TaskNotesEditorSection: View {
    @Binding var notes: String

    var body: some View {
        Section(AppStrings.localized("editor.task.notes")) {
            TextEditor(text: $notes)
                .frame(minHeight: 88)
        }
    }
}

private struct SymbolColorPickerRow: View {
    let colors: [String]
    @Binding var symbolName: String
    @Binding var colorHex: String
    @State private var isPickerPresented = false

    var body: some View {
        HStack {
            Text(.app("editor.task.symbolColor"))
            Spacer()
            pickerButton
        }
        #if os(macOS)
        .popover(isPresented: $isPickerPresented) {
            picker.frame(width: 460, height: 520)
        }
        #else
        .sheet(isPresented: $isPickerPresented) {
            NavigationStack {
                picker
                    .navigationTitle(AppStrings.localized("editor.symbol.title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(AppStrings.done) {
                                isPickerPresented = false
                            }
                        }
                    }
            }
            .presentationDetents([.large])
        }
        #endif
    }

    private var pickerButton: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(Color(hex: colorHex) ?? .blue)
                Text(.app("common.choose"))
            }
        }
    }

    private var picker: some View {
        SymbolAndColorPicker(
            symbols: SymbolCatalog.symbolNames,
            searchKeywords: SymbolCatalog.searchKeywords,
            colors: colors,
            symbolName: $symbolName,
            colorHex: $colorHex
        )
    }
}

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
                item.isCompleted.toggle()
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
