import SwiftUI

struct TaskEditorForm: View {
    @ObservedObject var store: TimeTrackerStore
    @Binding var draft: TaskEditorDraft
    let colors: [String]
    let focusedChecklistDraftID: FocusState<UUID?>.Binding
    let orderedChecklistIndices: [Int]
    let moveChecklistItems: (IndexSet, Int) -> Void
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
                moveChecklistItems: moveChecklistItems,
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
        Section {
            TextField(AppStrings.localized("editor.task.name"), text: $draft.title)
            TaskStatusPicker(selection: $draft.status)
            parentPicker
            if draft.parentID == nil {
                categoryPicker
            }
            SymbolColorPickerRow(
                colors: colors,
                symbolName: $draft.iconName,
                colorHex: $draft.colorHex
            )
        } header: {
            Text(AppStrings.localized("editor.task.info"))
        } footer: {
            inheritedCategoryHint
        }
    }

    private var categoryPicker: some View {
        Picker(AppStrings.localized("taskCategory.title"), selection: $draft.categoryID) {
            Text(.app("taskCategory.none")).tag(Optional<UUID>.none)
            ForEach(store.taskCategories, id: \.id) { category in
                Label(category.title, systemImage: category.iconName ?? "square.grid.2x2")
                    .tag(Optional(category.id))
            }
        }
    }

    @ViewBuilder
    private var inheritedCategoryHint: some View {
        if let category = inheritedCategory {
            Label {
                Text(String(format: AppStrings.localized("taskCategory.inherited"), category.title))
            } icon: {
                Image(systemName: category.iconName ?? "square.grid.2x2")
            }
            .font(.caption)
            .foregroundStyle(Color(hex: category.colorHex) ?? .secondary)
        }
    }

    private var inheritedCategory: TaskCategory? {
        guard let parentID = draft.parentID,
              let parent = store.task(for: parentID) else {
            return nil
        }
        return store.effectiveCategory(for: parent)
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
    let moveChecklistItems: (IndexSet, Int) -> Void
    let addChecklistItem: (Int?) -> Void
    @State private var isSorting = false

    var body: some View {
        Section {
            checklistRows
            addButton
        } header: {
            HStack {
                Text(.app("editor.checklist.title"))
                Spacer()
                Button(isSorting ? AppStrings.done : AppStrings.localized("common.sort")) {
                    withAnimation(.snappy(duration: 0.2)) {
                        isSorting.toggle()
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        } footer: {
            Text(.app("editor.checklist.footer"))
        }
        .checklistSortingMode(isSorting)
    }

    @ViewBuilder
    private var checklistRows: some View {
        if checklistItems.isEmpty {
            Text(.app("editor.checklist.empty"))
                .foregroundStyle(.secondary)
        }

        ForEach(rowPlacements) { placement in
            ChecklistEditorRow(
                item: $checklistItems[placement.sourceIndex],
                isSorting: isSorting,
                canMoveUp: canMove(visualIndex: placement.visualIndex, direction: -1),
                canMoveDown: canMove(visualIndex: placement.visualIndex, direction: 1),
                moveUp: { moveChecklistItem(visualIndex: placement.visualIndex, direction: -1) },
                moveDown: { moveChecklistItem(visualIndex: placement.visualIndex, direction: 1) },
                delete: { deleteChecklistItem(at: placement.sourceIndex) },
                focus: focusedChecklistDraftID,
                submit: { addChecklistItem(placement.visualIndex) }
            )
        }
        .onMove(perform: moveChecklistItems)
        .animation(.snappy(duration: 0.2), value: rowAnimationSignature)
    }

    private var addButton: some View {
        Button {
            addChecklistItem(nil)
        } label: {
            Label(AppStrings.localized("editor.checklist.add"), systemImage: "plus")
        }
    }

    private var rowPlacements: [ChecklistEditorRowPlacement] {
        orderedChecklistIndices.enumerated().compactMap { visualIndex, sourceIndex in
            guard checklistItems.indices.contains(sourceIndex) else { return nil }
            return ChecklistEditorRowPlacement(
                id: checklistItems[sourceIndex].id,
                visualIndex: visualIndex,
                sourceIndex: sourceIndex
            )
        }
    }

    private var rowAnimationSignature: [UUID] {
        rowPlacements.map(\.id)
    }

    private func moveChecklistItem(visualIndex: Int, direction: Int) {
        let destination = direction < 0 ? visualIndex - 1 : visualIndex + 2
        guard canMove(visualIndex: visualIndex, direction: direction) else { return }
        moveChecklistItems(IndexSet(integer: visualIndex), destination)
    }

    private func canMove(visualIndex: Int, direction: Int) -> Bool {
        let destination = direction < 0 ? visualIndex - 1 : visualIndex + 2
        let elements = rowPlacements.map { placement in
            ChecklistOrderingElement(
                id: placement.id,
                isCompleted: checklistItems[placement.sourceIndex].isCompleted
            )
        }
        return ChecklistOrderingService().canMove(
            elements: elements,
            sourceOffsets: IndexSet(integer: visualIndex),
            destination: destination
        )
    }

    private func deleteChecklistItem(at index: Int) {
        guard checklistItems.indices.contains(index) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            _ = checklistItems.remove(at: index)
        }
    }
}

private extension View {
    @ViewBuilder
    func checklistSortingMode(_ isSorting: Bool) -> some View {
        #if os(macOS)
        self
        #else
        environment(\.editMode, .constant(isSorting ? .active : .inactive))
        #endif
    }
}

private struct ChecklistEditorRowPlacement: Identifiable, Equatable {
    let id: UUID
    let visualIndex: Int
    let sourceIndex: Int
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
    let isSorting: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void
    let focus: FocusState<UUID?>.Binding
    let submit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ChecklistCompletionButton(isCompleted: item.isCompleted, colorHex: item.colorHex) {
                withAnimation(.snappy(duration: 0.2)) {
                    item.isCompleted.toggle()
                }
            }
            .padding(.top, 2)

            SymbolColorPickerButton(
                colors: TaskColorPalette.hexValues,
                symbolName: $item.iconName,
                colorHex: $item.colorHex,
                showsTitle: false
            )
            .buttonStyle(.plain)
            .frame(width: 34, height: 34)

            TextField(AppStrings.localized("editor.checklist.itemPlaceholder"), text: $item.title, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .focused(focus, equals: item.id)
                .submitLabel(.next)
                .onSubmit(submit)
                .labelsHidden()

            sortingControls
            Button(role: .destructive) {
                delete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 32)
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
                        .frame(width: 24, height: 28)
                }
                .disabled(!canMoveUp)
                .accessibilityLabel(AppStrings.localized("common.moveUp"))

                Button(action: moveDown) {
                    Image(systemName: "chevron.down")
                        .frame(width: 24, height: 28)
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
