import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreInboxStoreTests {
    @Test @MainActor
    func itemScopedSuggestionRefreshReplacesOnlyAffectedInboxSuggestion() {
        let affectedItemID = UUID()
        let unchangedItemID = UUID()
        let taskID = UUID()

        let affectedItem = InboxItem(title: "Affected", deviceID: "test")
        affectedItem.id = affectedItemID
        let unchangedItem = InboxItem(title: "Keep", sortOrder: 20, deviceID: "test")
        unchangedItem.id = unchangedItemID

        let oldAffectedSuggestion = InboxSuggestion(
            inboxItemID: affectedItemID,
            taskID: taskID,
            reason: "Old",
            iconName: "tray",
            colorHex: "8E8E93",
            titleSnapshot: "Affected",
            deviceID: "test"
        )
        let unchangedSuggestion = InboxSuggestion(
            inboxItemID: unchangedItemID,
            taskID: taskID,
            reason: "Keep",
            iconName: "book",
            colorHex: "1677FF",
            titleSnapshot: "Keep",
            deviceID: "test"
        )

        var store = InboxStore()
        store.refresh(
            items: [affectedItem, unchangedItem],
            suggestions: [oldAffectedSuggestion, unchangedSuggestion]
        )

        let updatedAffectedSuggestion = InboxSuggestion(
            inboxItemID: affectedItemID,
            taskID: taskID,
            reason: "Updated",
            iconName: "checkmark.circle",
            colorHex: "34C759",
            titleSnapshot: "Affected",
            deviceID: "test"
        )

        store.refreshSuggestionScoped(
            inboxItemIDs: [affectedItemID],
            suggestions: [updatedAffectedSuggestion]
        )

        #expect(store.items.map(\.id) == [affectedItemID, unchangedItemID])
        #expect(store.suggestions.first { $0.inboxItemID == affectedItemID }?.reason == "Updated")
        #expect(store.suggestions.first { $0.inboxItemID == unchangedItemID }?.reason == "Keep")
        #expect(store.suggestions.contains { $0.id == oldAffectedSuggestion.id } == false)
    }
}
