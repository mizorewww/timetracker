import Foundation

extension TaskEditorSession {
    var orderedChecklistIndices: [Int] {
        ChecklistOrderingService().completionGrouped(
            Array(draft.checklistItems.indices),
            isCompleted: { draft.checklistItems[$0].isCompleted }
        )
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
