import SwiftUI

struct TaskDetailChecklistEditorSection: View {
    @Binding var draft: TaskEditorDraft
    let focusedChecklistDraftID: FocusState<UUID?>.Binding
    @State private var isSortingChecklist = false

    var body: some View {
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

private struct TaskDetailChecklistEditorRowPlacement: Identifiable {
    let id: UUID
    let visualIndex: Int
    let sourceIndex: Int
}
