import Foundation

struct InboxStore {
    private(set) var items: [InboxItem] = []
    private(set) var suggestions: [InboxSuggestion] = []

    mutating func refresh(items: [InboxItem], suggestions: [InboxSuggestion]) {
        self.items = sortedItems(InboxSuggestionIdentityService().visibleLogicalItems(from: items))
        self.suggestions = sortedSuggestions(suggestions.deduplicatedByID())
    }

    mutating func refreshSuggestionScoped(
        inboxItemIDs: Set<UUID>,
        suggestions fetchedSuggestions: [InboxSuggestion]
    ) {
        guard inboxItemIDs.isEmpty == false else { return }
        suggestions = sortedSuggestions(
            (suggestions.filter { inboxItemIDs.contains($0.inboxItemID) == false } + fetchedSuggestions).deduplicatedByID()
        )
    }

    private func sortedItems(_ items: [InboxItem]) -> [InboxItem] {
        items.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func sortedSuggestions(_ suggestions: [InboxSuggestion]) -> [InboxSuggestion] {
        suggestions.sorted { lhs, rhs in
            if lhs.inboxItemID != rhs.inboxItemID {
                return lhs.inboxItemID.uuidString < rhs.inboxItemID.uuidString
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}
