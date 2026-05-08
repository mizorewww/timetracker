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
        inboxSuggestionByItemID[item.id]
    }

    func rebuildInboxSuggestionIndexes() {
        inboxSuggestionByItemID = inboxSuggestions
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in lhs.updatedAt < rhs.updatedAt }
            .reduce(into: [:]) { result, suggestion in
                result[suggestion.inboxItemID] = suggestion
            }
    }

    private func inboxSort(_ lhs: InboxItem, _ rhs: InboxItem) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.createdAt < rhs.createdAt
    }
}
