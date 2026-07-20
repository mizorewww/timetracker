import Foundation

extension TaskEditorSession {
    func acceptAutosavedDraft(
        _ savedDraft: TaskEditorDraft,
        for taskID: UUID
    ) {
        guard savedDraft.taskID == taskID,
              let task = store.task(for: taskID) else { return }
        let persistedDraft = store.editorDraft(for: task)
        replace(
            with: Self.rebasedAutosavedDraft(
                persistedDraft,
                preserving: savedDraft
            )
        )
    }

    private static func rebasedAutosavedDraft(
        _ persistedDraft: TaskEditorDraft,
        preserving visibleDraft: TaskEditorDraft
    ) -> TaskEditorDraft {
        var rebased = persistedDraft
        rebased.title = visibleDraft.title
        rebased.parentID = visibleDraft.parentID
        rebased.categoryID = visibleDraft.categoryID
        rebased.colorHex = visibleDraft.colorHex
        rebased.iconName = visibleDraft.iconName
        rebased.notes = visibleDraft.notes
        rebased.estimatedMinutes = visibleDraft.estimatedMinutes
        rebased.hasDueDate = visibleDraft.hasDueDate
        rebased.dueAt = visibleDraft.dueAt

        guard persistedDraft.checklistItems.count ==
                visibleDraft.checklistItems.count else {
            return rebased
        }
        rebased.checklistItems = zip(
            persistedDraft.checklistItems,
            visibleDraft.checklistItems
        ).map { persistedItem, visibleItem in
            var item = persistedItem
            item.title = visibleItem.title
            item.isCompleted = visibleItem.isCompleted
            item.iconName = visibleItem.iconName
            item.colorHex = visibleItem.colorHex
            return item
        }
        return rebased
    }
}
