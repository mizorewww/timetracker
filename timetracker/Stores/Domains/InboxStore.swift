import Foundation

struct InboxStore {
    private(set) var itemReadModels: [InboxItemReadModel] = []
    private(set) var suggestions: [InboxSuggestion] = []

    var items: [InboxItem] {
        itemReadModels.map(\.item)
    }

    mutating func refresh(items: [InboxItem], suggestions: [InboxSuggestion]) {
        refresh(
            itemReadModels: InboxSuggestionIdentityService().visibleLogicalReadModels(from: items),
            suggestions: suggestions
        )
    }

    mutating func refresh(
        itemReadModels: [InboxItemReadModel],
        suggestions: [InboxSuggestion]
    ) {
        self.itemReadModels = sortedItemReadModels(itemReadModels)
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

    private func sortedItemReadModels(_ readModels: [InboxItemReadModel]) -> [InboxItemReadModel] {
        readModels.sorted { lhsReadModel, rhsReadModel in
            let lhs = lhsReadModel.item
            let rhs = rhsReadModel.item
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func sortedSuggestions(_ suggestions: [InboxSuggestion]) -> [InboxSuggestion] {
        suggestions.sorted { lhs, rhs in
            if lhs.inboxItemID != rhs.inboxItemID {
                return lhs.inboxItemID.uuidString < rhs.inboxItemID.uuidString
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }
}
