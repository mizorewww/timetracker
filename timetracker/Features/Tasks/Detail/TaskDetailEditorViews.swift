import SwiftUI

struct TaskDetailEditorCard: View {
    @ObservedObject var store: TimeTrackerStore
    @Binding var draft: TaskEditorDraft
    @Binding var isExpanded: Bool
    let save: () -> Void
    let reset: () -> Void
    let focusedChecklistDraftID: FocusState<UUID?>.Binding
    @State private var isSortingChecklist = false

    private let colors = TaskColorPalette.hexValues

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if isExpanded {
                Divider()
                infoSection
                Divider()
                planSection
                Divider()
                checklistSection
                Divider()
                notesSection
            } else {
                editorSummary
            }
        }
        .appCard()
        .accessibilityIdentifier("task.detail.editor")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(AppStrings.localized("task.detail.editor"), systemImage: "pencil")
                .font(.headline)
            Spacer(minLength: 8)
            if isExpanded {
                Button(AppStrings.localized("common.reset"), action: reset)
                    .buttonStyle(.bordered)
                Button(AppStrings.localized("common.save"), action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            } else {
                Button {
                    isExpanded = true
                } label: {
                    Label(AppStrings.localized("task.detail.editor.expand"), systemImage: "pencil")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var editorSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                summaryBadge(title: AppStrings.localized("editor.task.status"), value: draft.status.displayName, iconName: "circle")
                summaryBadge(title: AppStrings.localized("editor.task.estimate"), value: estimatedMinutesLabel, iconName: "timer")
                summaryBadge(title: AppStrings.localized("editor.checklist.title"), value: checklistSummary, iconName: "checklist")
            }

            VStack(alignment: .leading, spacing: 8) {
                summaryBadge(title: AppStrings.localized("editor.task.status"), value: draft.status.displayName, iconName: "circle")
                summaryBadge(title: AppStrings.localized("editor.task.estimate"), value: estimatedMinutesLabel, iconName: "timer")
                summaryBadge(title: AppStrings.localized("editor.checklist.title"), value: checklistSummary, iconName: "checklist")
            }
        }
    }

    private func summaryBadge(title: String, value: String, iconName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var infoSection: some View {
        TaskDetailEditorSection(title: AppStrings.localized("editor.task.info")) {
            TextField(AppStrings.localized("editor.task.name"), text: $draft.title, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)

            TaskDetailStatusControl(selection: $draft.status)

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

    private var checklistSummary: String {
        let completed = draft.checklistItems.filter(\.isCompleted).count
        let total = draft.checklistItems.count
        guard total > 0 else { return AppStrings.localized("checklist.noItems") }
        return "\(completed)/\(total)"
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
        let draftByID = draft.checklistItems.reduce(into: [UUID: ChecklistEditorDraft]()) { result, item in
            result[item.id] = item
        }
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

private struct TaskDetailStatusControl: View {
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

private struct TaskDetailChecklistEditorRowPlacement: Identifiable {
    let id: UUID
    let visualIndex: Int
    let sourceIndex: Int
}
