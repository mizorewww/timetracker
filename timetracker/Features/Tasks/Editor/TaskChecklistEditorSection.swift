import SwiftUI

struct TaskChecklistEditorSection: View {
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
