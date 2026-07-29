import SwiftUI

struct TaskChecklistEditorSection: View {
    @Binding var checklistItems: [ChecklistEditorDraft]
    let focusedChecklistDraftID: FocusState<UUID?>.Binding
    let orderedChecklistIndices: [Int]
    let toggleChecklistItem: (UUID) -> Void
    let deleteChecklistItem: (UUID) -> Void
    let moveChecklistItems: (IndexSet, Int) -> Void
    let addChecklistItem: (Int?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section {
            checklistRows
            addButton
        } header: {
            Text(.app("editor.checklist.title"))
        } footer: {
            Text(.app("editor.checklist.footer"))
        }
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.28),
            value: rowPlacements
        )
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
                delete: {
                    focusedChecklistDraftID.wrappedValue = nil
                    deleteChecklistItem(placement.id)
                },
                toggleCompletion: {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                        toggleChecklistItem(placement.id)
                    }
                },
                focus: focusedChecklistDraftID,
                submit: { addChecklistItem(placement.visualIndex) }
            )
        }
        .onMove(perform: moveChecklistItems)
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
}

private struct ChecklistEditorRowPlacement: Identifiable, Equatable {
    let id: UUID
    let visualIndex: Int
    let sourceIndex: Int
}
