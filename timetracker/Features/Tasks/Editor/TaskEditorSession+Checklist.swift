import Foundation

extension TaskEditorSession {
    var orderedChecklistIndices: [Int] {
        ChecklistOrderingService().completionGrouped(
            Array(draft.checklistItems.indices),
            isCompleted: { draft.checklistItems[$0].isCompleted }
        )
    }

    func toggleChecklistItem(id: UUID) {
        guard let sourceIndex = draft.checklistItems.firstIndex(where: {
            $0.id == id
        }) else {
            return
        }

        var item = draft.checklistItems.remove(at: sourceIndex)
        item.isCompleted.toggle()
        if item.isCompleted {
            preCompletionChecklistIndices[id] = sourceIndex
            draft.checklistItems.append(item)
        } else {
            // Restore the original position when it is still inside the
            // incomplete group; fall back to the group end otherwise.
            let incompleteEnd = draft.checklistItems.firstIndex(where: {
                $0.isCompleted
            }) ?? draft.checklistItems.endIndex
            let restoredIndex = preCompletionChecklistIndices.removeValue(
                forKey: id
            )
            let insertionIndex = min(restoredIndex ?? incompleteEnd, incompleteEnd)
            draft.checklistItems.insert(item, at: insertionIndex)
        }
    }

    func moveChecklistItems(
        fromOffsets sourceOffsets: IndexSet,
        toOffset destination: Int
    ) {
        let orderedDrafts = orderedChecklistIndices.map {
            draft.checklistItems[$0]
        }
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

        let draftByID = draft.checklistItems.reduce(
            into: [UUID: ChecklistEditorDraft]()
        ) { result, item in
            result[item.id] = item
        }
        draft.checklistItems = reorderedIDs.compactMap { draftByID[$0] }
    }

    func addChecklistItem(afterVisualIndex visualIndex: Int? = nil) -> UUID {
        let newItem = ChecklistEditorDraft()
        var orderedDrafts = orderedChecklistIndices.map {
            draft.checklistItems[$0]
        }
        if let visualIndex,
           orderedDrafts.indices.contains(visualIndex),
           orderedDrafts[visualIndex].isCompleted == false {
            orderedDrafts.insert(newItem, at: visualIndex + 1)
        } else {
            let insertionIndex = orderedDrafts.firstIndex {
                $0.isCompleted
            } ?? orderedDrafts.count
            orderedDrafts.insert(newItem, at: insertionIndex)
        }
        draft.checklistItems = orderedDrafts
        return newItem.id
    }
}
