import SwiftUI

struct TaskDetailEditorCard: View {
    @ObservedObject var store: TimeTrackerStore
    @Binding var draft: TaskEditorDraft
    let save: () -> Void
    let reset: () -> Void
    let focusedChecklistDraftID: FocusState<UUID?>.Binding
    @State private var isSortingChecklist = false

    private let colors = TaskColorPalette.hexValues

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            infoSection
            Divider()
            planSection
            Divider()
            checklistSection
            Divider()
            notesSection
        }
        .appCard()
        .accessibilityIdentifier("task.detail.editor")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(AppStrings.localized("task.detail.editor"), systemImage: "pencil")
                .font(.headline)
            Spacer(minLength: 8)
            Button(AppStrings.localized("common.reset"), action: reset)
                .buttonStyle(.bordered)
            Button(AppStrings.localized("common.save"), action: save)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
        }
    }

    private var infoSection: some View {
        TaskDetailEditorSection(title: AppStrings.localized("editor.task.info")) {
            TextField(AppStrings.localized("editor.task.name"), text: $draft.title, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)

            TaskDetailStatusSelector(selection: $draft.status)

            parentPicker
            if draft.parentID == nil {
                categoryPicker
            } else {
                inheritedCategoryHint
            }

            SymbolColorPickerRow(
                colors: colors,
                symbolName: $draft.iconName,
                colorHex: $draft.colorHex
            )
        }
    }

    private var planSection: some View {
        TaskDetailEditorSection(title: AppStrings.localized("editor.task.plan")) {
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

    private var checklistSection: some View {
        TaskDetailEditorSection(title: AppStrings.localized("editor.checklist.title")) {
            HStack {
                Text(.app("editor.checklist.footer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(isSortingChecklist ? AppStrings.done : AppStrings.localized("common.sort")) {
                    isSortingChecklist.toggle()
                }
                .font(.caption)
            }

            if draft.checklistItems.isEmpty {
                Text(.app("editor.checklist.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(rowPlacements) { placement in
                ChecklistEditorRow(
                    item: $draft.checklistItems[placement.sourceIndex],
                    isSorting: isSortingChecklist,
                    canMoveUp: canMove(visualIndex: placement.visualIndex, direction: -1),
                    canMoveDown: canMove(visualIndex: placement.visualIndex, direction: 1),
                    moveUp: { moveChecklistItem(visualIndex: placement.visualIndex, direction: -1) },
                    moveDown: { moveChecklistItem(visualIndex: placement.visualIndex, direction: 1) },
                    delete: { deleteChecklistItem(at: placement.sourceIndex) },
                    focus: focusedChecklistDraftID,
                    submit: { addChecklistItem(afterVisualIndex: placement.visualIndex) }
                )
                if placement.id != rowPlacements.last?.id {
                    Divider()
                }
            }

            Button {
                addChecklistItem()
            } label: {
                Label(AppStrings.localized("editor.checklist.add"), systemImage: "plus")
            }
        }
    }

    private var notesSection: some View {
        TaskDetailEditorSection(title: AppStrings.localized("editor.task.notes")) {
            TextEditor(text: $draft.notes)
                .frame(minHeight: 96)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18))
                }
        }
    }

    private var parentPicker: some View {
        Picker(AppStrings.localized("editor.task.parent"), selection: $draft.parentID) {
            Text(.app("editor.task.rootLevel")).tag(Optional<UUID>.none)
            ForEach(store.validParentTasks(for: draft.taskID), id: \.id) { task in
                Text(indentedTitle(task)).tag(Optional(task.id))
            }
        }
        .pickerStyle(.menu)
    }

    private var categoryPicker: some View {
        Picker(AppStrings.localized("taskCategory.title"), selection: $draft.categoryID) {
            Text(.app("taskCategory.none")).tag(Optional<UUID>.none)
            ForEach(store.taskCategories, id: \.id) { category in
                Label(category.title, systemImage: category.iconName ?? "square.grid.2x2")
                    .tag(Optional(category.id))
            }
        }
        .pickerStyle(.menu)
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

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var orderedChecklistIndices: [Int] {
        draft.checklistItems.indices.sorted { lhs, rhs in
            let left = draft.checklistItems[lhs]
            let right = draft.checklistItems[rhs]
            if left.isCompleted != right.isCompleted {
                return !left.isCompleted
            }
            return lhs < rhs
        }
    }

    private var rowPlacements: [TaskDetailChecklistEditorRowPlacement] {
        orderedChecklistIndices.enumerated().compactMap { visualIndex, sourceIndex in
            guard draft.checklistItems.indices.contains(sourceIndex) else { return nil }
            return TaskDetailChecklistEditorRowPlacement(
                id: draft.checklistItems[sourceIndex].id,
                visualIndex: visualIndex,
                sourceIndex: sourceIndex
            )
        }
    }

    private func indentedTitle(_ task: TaskNode) -> String {
        String(repeating: "  ", count: task.depth) + task.title
    }

    private func addChecklistItem(afterVisualIndex visualIndex: Int? = nil) {
        let newItem = ChecklistEditorDraft()
        var orderedDrafts = orderedChecklistIndices.map { draft.checklistItems[$0] }
        if let visualIndex,
           orderedDrafts.indices.contains(visualIndex),
           orderedDrafts[visualIndex].isCompleted == false {
            orderedDrafts.insert(newItem, at: visualIndex + 1)
        } else {
            let insertionIndex = orderedDrafts.firstIndex { $0.isCompleted } ?? orderedDrafts.count
            orderedDrafts.insert(newItem, at: insertionIndex)
        }
        draft.checklistItems = orderedDrafts
        focusedChecklistDraftID.wrappedValue = newItem.id
    }

    private func deleteChecklistItem(at index: Int) {
        guard draft.checklistItems.indices.contains(index) else { return }
        draft.checklistItems.remove(at: index)
    }

    private func moveChecklistItem(visualIndex: Int, direction: Int) {
        let destination = direction < 0 ? visualIndex - 1 : visualIndex + 2
        moveChecklistItems(fromOffsets: IndexSet(integer: visualIndex), toOffset: destination)
    }

    private func moveChecklistItems(fromOffsets sourceOffsets: IndexSet, toOffset destination: Int) {
        let orderedDrafts = orderedChecklistIndices.map { draft.checklistItems[$0] }
        let elements = orderedDrafts.map {
            ChecklistOrderingElement(id: $0.id, isCompleted: $0.isCompleted)
        }
        guard let reorderedIDs = ChecklistOrderingService().reorderedIDs(
            elements: elements,
            sourceOffsets: sourceOffsets,
            destination: destination
        ) else {
            return
        }
        let draftByID = Dictionary(uniqueKeysWithValues: draft.checklistItems.map { ($0.id, $0) })
        draft.checklistItems = reorderedIDs.compactMap { draftByID[$0] }
    }

    private func canMove(visualIndex: Int, direction: Int) -> Bool {
        let destination = direction < 0 ? visualIndex - 1 : visualIndex + 2
        let elements = rowPlacements.map { placement in
            ChecklistOrderingElement(
                id: placement.id,
                isCompleted: draft.checklistItems[placement.sourceIndex].isCompleted
            )
        }
        return ChecklistOrderingService().canMove(
            elements: elements,
            sourceOffsets: IndexSet(integer: visualIndex),
            destination: destination
        )
    }
}

private struct TaskDetailEditorSection<Content: View>: View {
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

private struct TaskDetailStatusSelector: View {
    @Binding var selection: TaskStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.app("editor.task.status"))
                .font(.caption)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    options
                }

                VStack(spacing: 8) {
                    options
                }
            }
        }
    }

    private var options: some View {
        ForEach(TaskStatus.editableCases, id: \.self) { status in
            Button {
                selection = status
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: status.symbolName)
                        .foregroundStyle(Color(hex: status.colorHex) ?? .secondary)
                    Text(status.displayName)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if selection == status {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                    }
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .frame(height: 38)
                .frame(maxWidth: .infinity)
                .background(optionBackground(for: status), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(status.displayName)
        }
    }

    private func optionBackground(for status: TaskStatus) -> Color {
        selection == status
            ? (Color(hex: status.colorHex) ?? .blue).opacity(0.16)
            : Color.secondary.opacity(0.08)
    }
}

private struct TaskDetailChecklistEditorRowPlacement: Identifiable {
    let id: UUID
    let visualIndex: Int
    let sourceIndex: Int
}
