import Foundation

extension TimeTrackerStore {
    var openInboxItems: [InboxItem] {
        inboxItems
            .filter { !$0.isCompleted && $0.deletedAt == nil }
            .sorted(by: inboxSort)
    }

    var completedInboxItems: [InboxItem] {
        inboxItems
            .filter { $0.isCompleted && $0.deletedAt == nil }
            .sorted(by: inboxSort)
    }

    var inboxItemsForDisplay: [InboxItem] {
        openInboxItems + completedInboxItems
    }

    func inboxSuggestion(for item: InboxItem) -> InboxSuggestion? {
        inboxSuggestionStateService.displaySuggestion(
            for: inboxItemReadModel(for: item),
            suggestion: inboxSuggestionByItemID[item.id]
        )
    }

    func inboxItemReadModel(for item: InboxItem) -> InboxItemReadModel {
        if let readModel = inboxItemReadModelByItemID[item.id], readModel.item === item {
            return readModel
        }
        return InboxItemReadModel(
            item: item,
            dismissedSuggestionRevisionID: item.dismissedSuggestionRevisionID
        )
    }

    func inboxSuggestionFailureMessage(for item: InboxItem) -> String? {
        guard item.deletedAt == nil,
              item.isCompleted == false,
              inboxSuggestionInFlightIDs.contains(item.id) == false,
              inboxSuggestion(for: item) == nil
        else {
            return nil
        }
        return inboxSuggestionFailureByItemID[item.id]
    }

    func clearInboxSuggestionFailure(_ item: InboxItem) {
        inboxSuggestionFailureByItemID[item.id] = nil
    }

    func rebuildInboxSuggestionIndexes() {
        inboxSuggestionByItemID = InboxSuggestionIdentityService().index(
            items: inboxItems,
            suggestions: inboxSuggestions
        )
    }

    private func inboxSort(_ lhs: InboxItem, _ rhs: InboxItem) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
