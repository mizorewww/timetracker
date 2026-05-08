import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreChecklistStoreTests {
    @Test @MainActor
    func taskScopedRefreshReplacesOnlyAffectedChecklistItemsAndVisuals() {
        let affectedTaskID = UUID()
        let unchangedTaskID = UUID()

        let oldAffectedItem = ChecklistItem(
            taskID: affectedTaskID,
            title: "Old",
            sortOrder: 10,
            deviceID: "test"
        )
        let unchangedItem = ChecklistItem(
            taskID: unchangedTaskID,
            title: "Keep",
            sortOrder: 10,
            deviceID: "test"
        )
        let oldAffectedVisual = ChecklistItemVisual(
            checklistItemID: oldAffectedItem.id,
            iconName: "square",
            colorHex: "999999",
            deviceID: "test"
        )
        let unchangedVisual = ChecklistItemVisual(
            checklistItemID: unchangedItem.id,
            iconName: "book",
            colorHex: "1677FF",
            deviceID: "test"
        )

        var store = ChecklistStore()
        store.refresh(
            items: [oldAffectedItem, unchangedItem],
            visuals: [oldAffectedVisual, unchangedVisual]
        )

        let updatedAffectedItem = ChecklistItem(
            taskID: affectedTaskID,
            title: "Updated",
            sortOrder: 10,
            deviceID: "test"
        )
        updatedAffectedItem.id = oldAffectedItem.id
        let updatedAffectedVisual = ChecklistItemVisual(
            checklistItemID: updatedAffectedItem.id,
            iconName: "checkmark.circle",
            colorHex: "34C759",
            deviceID: "test"
        )

        store.refreshTaskScoped(
            taskIDs: [affectedTaskID],
            items: [updatedAffectedItem],
            visuals: [updatedAffectedVisual]
        )

        #expect(store.items.map(\.id).contains(oldAffectedItem.id))
        #expect(store.items.first { $0.id == oldAffectedItem.id }?.title == "Updated")
        #expect(store.items.first { $0.id == unchangedItem.id }?.title == "Keep")
        #expect(store.visuals.first { $0.checklistItemID == oldAffectedItem.id }?.iconName == "checkmark.circle")
        #expect(store.visuals.first { $0.checklistItemID == unchangedItem.id }?.iconName == "book")
    }
}
