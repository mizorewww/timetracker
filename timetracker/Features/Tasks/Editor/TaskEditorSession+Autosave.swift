import Foundation

extension TaskEditorSession {
    @discardableResult
    func acceptAutosavedDraft(
        _ savedDraft: TaskEditorDraft,
        for taskID: UUID
    ) -> Bool {
        guard savedDraft.taskID == taskID,
              let task = store.task(for: taskID) else { return false }
        let visibleDraft = draft
        let persistedDraft = store.editorDraft(for: task)
        guard let persistedChecklistIDs = Self.persistedChecklistIDs(
            in: persistedDraft,
            matching: savedDraft
        ) else { return false }
        rebaseAfterAutosave(
            visibleDraft: Self.rebasedAutosavedDraft(
                persistedDraft,
                preserving: visibleDraft,
                persistedChecklistIDs: persistedChecklistIDs
            ),
            savedBaseline: Self.rebasedAutosavedDraft(
                persistedDraft,
                preserving: savedDraft,
                persistedChecklistIDs: persistedChecklistIDs
            )
        )
        return true
    }

    private func rebaseAfterAutosave(
        visibleDraft: TaskEditorDraft,
        savedBaseline: TaskEditorDraft
    ) {
        draft.baseline = visibleDraft.baseline
        draft.taskID = visibleDraft.taskID
        let persistedChecklistIDs = visibleDraft.checklistItems.reduce(
            into: [UUID: UUID]()
        ) { result, item in
            guard let existingID = item.existingID else { return }
            result[item.id] = existingID
        }
        for index in draft.checklistItems.indices {
            let itemID = draft.checklistItems[index].id
            if let persistedID = persistedChecklistIDs[itemID] {
                draft.checklistItems[index].existingID = persistedID
            }
        }
        finishAutosaveRebase(
            visibleDraft: visibleDraft,
            savedBaseline: savedBaseline
        )
    }

    private static func rebasedAutosavedDraft(
        _ persistedDraft: TaskEditorDraft,
        preserving visibleDraft: TaskEditorDraft,
        persistedChecklistIDs: [UUID: UUID]
    ) -> TaskEditorDraft {
        var rebased = visibleDraft
        rebased.baseline = persistedDraft.baseline
        rebased.taskID = persistedDraft.taskID
        rebased.checklistItems = visibleDraft.checklistItems.map { visibleItem in
            ChecklistEditorDraft(
                id: visibleItem.id,
                existingID: persistedChecklistIDs[visibleItem.id] ??
                    visibleItem.existingID,
                title: visibleItem.title,
                isCompleted: visibleItem.isCompleted,
                iconName: visibleItem.iconName,
                colorHex: visibleItem.colorHex
            )
        }
        return rebased
    }

    private static func persistedChecklistIDs(
        in persistedDraft: TaskEditorDraft,
        matching savedDraft: TaskEditorDraft
    ) -> [UUID: UUID]? {
        guard persistedDraft.checklistItems.count ==
                savedDraft.checklistItems.count else {
            return nil
        }

        let persistedIDs = persistedDraft.checklistItems.compactMap(\.existingID)
        let persistedIDSet = Set(persistedIDs)
        guard persistedIDs.count == persistedDraft.checklistItems.count,
              persistedIDSet.count == persistedIDs.count else {
            return nil
        }

        var persistedIDByDraftID: [UUID: UUID] = [:]
        var claimedPersistedIDs: Set<UUID> = []
        for item in savedDraft.checklistItems {
            guard let existingID = item.existingID else { continue }
            guard persistedIDSet.contains(existingID),
                  claimedPersistedIDs.insert(existingID).inserted else {
                return nil
            }
            persistedIDByDraftID[item.id] = existingID
        }

        let newItems = savedDraft.checklistItems.filter {
            $0.existingID == nil
        }
        let unclaimedPersistedIDs = persistedIDs.filter {
            claimedPersistedIDs.contains($0) == false
        }
        guard newItems.count == unclaimedPersistedIDs.count else {
            return nil
        }
        for (item, persistedID) in zip(newItems, unclaimedPersistedIDs) {
            guard persistedIDByDraftID.updateValue(
                persistedID,
                forKey: item.id
            ) == nil else {
                return nil
            }
        }

        guard persistedIDByDraftID.count == savedDraft.checklistItems.count,
              Set(persistedIDByDraftID.values) == persistedIDSet else {
            return nil
        }
        return persistedIDByDraftID
    }
}
