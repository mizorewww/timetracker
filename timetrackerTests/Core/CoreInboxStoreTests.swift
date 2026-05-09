import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreInboxStoreTests {
    @Test @MainActor
    func inboxSuggestionStateHidesStaleSuggestionsAndAllowsRegeneration() {
        let service = InboxSuggestionStateService()
        let item = InboxItem(title: "Plan chemistry review", deviceID: "test")
        let taskID = UUID()

        #expect(service.state(for: item, suggestion: nil, isInFlight: false) == .eligible)
        #expect(service.shouldAutoSuggest(item: item, suggestion: nil, isInFlight: false))
        #expect(service.displaySuggestion(for: item, suggestion: nil) == nil)

        #expect(service.state(for: item, suggestion: nil, isInFlight: true) == .pending)
        #expect(service.shouldAutoSuggest(item: item, suggestion: nil, isInFlight: true) == false)

        let readySuggestion = InboxSuggestion(
            inboxItemID: item.id,
            taskID: taskID,
            reason: "Matches study task",
            iconName: "book",
            colorHex: "1677FF",
            titleSnapshot: item.title,
            deviceID: "test"
        )
        #expect(service.state(for: item, suggestion: readySuggestion, isInFlight: false) == .ready)
        #expect(service.displaySuggestion(for: item, suggestion: readySuggestion)?.id == readySuggestion.id)

        item.suggestionGeneratedAt = Date(timeIntervalSince1970: 1_000)
        #expect(service.state(for: item, suggestion: nil, isInFlight: false) == .dismissed)
        #expect(service.shouldAutoSuggest(item: item, suggestion: nil, isInFlight: false) == false)

        item.title = "Plan physics review"
        #expect(service.state(for: item, suggestion: readySuggestion, isInFlight: false) == .stale)
        #expect(service.displaySuggestion(for: item, suggestion: readySuggestion) == nil)
        #expect(service.shouldAutoSuggest(item: item, suggestion: readySuggestion, isInFlight: false))
    }

    @Test @MainActor
    func storeDoesNotExposeStaleInboxSuggestionsToUI() {
        let item = InboxItem(title: "New title", deviceID: "test")
        let task = TaskNode(title: "Study", parentID: nil, deviceID: "test")
        let staleSuggestion = InboxSuggestion(
            inboxItemID: item.id,
            taskID: task.id,
            reason: "Old title match",
            iconName: "book",
            colorHex: "1677FF",
            titleSnapshot: "Old title",
            deviceID: "test"
        )

        let store = TimeTrackerStore()
        store.tasks = [task]
        store.inboxItems = [item]
        store.inboxSuggestions = [staleSuggestion]

        #expect(store.inboxSuggestion(for: item) == nil)
    }

    @Test @MainActor
    func storeExposesItemScopedInboxSuggestionFailuresOnlyWhenActionable() {
        let item = InboxItem(title: "Read HIG", deviceID: "test")
        let task = TaskNode(title: "Study", parentID: nil, deviceID: "test")
        let suggestion = InboxSuggestion(
            inboxItemID: item.id,
            taskID: task.id,
            reason: "Study item",
            iconName: "book",
            colorHex: "1677FF",
            titleSnapshot: item.title,
            deviceID: "test"
        )
        let store = TimeTrackerStore()
        store.tasks = [task]
        store.inboxItems = [item]
        store.inboxSuggestionFailureByItemID[item.id] = "Could not suggest"

        #expect(store.inboxSuggestionFailureMessage(for: item) == "Could not suggest")

        store.inboxSuggestionInFlightIDs.insert(item.id)
        #expect(store.inboxSuggestionFailureMessage(for: item) == nil)

        store.inboxSuggestionInFlightIDs.remove(item.id)
        store.inboxSuggestions = [suggestion]
        #expect(store.inboxSuggestionFailureMessage(for: item) == nil)
    }

    @Test @MainActor
    func storeCanClearItemScopedInboxSuggestionFailure() {
        let item = InboxItem(title: "Read HIG", deviceID: "test")
        let store = TimeTrackerStore()
        store.inboxSuggestionFailureByItemID[item.id] = "Could not suggest"

        store.clearInboxSuggestionFailure(item)

        #expect(store.inboxSuggestionFailureByItemID[item.id] == nil)
    }

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
