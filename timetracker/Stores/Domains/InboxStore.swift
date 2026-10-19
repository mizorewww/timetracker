import Foundation

struct InboxStore {
    private(set) var itemReadModels: [InboxItemReadModel] = []
    private(set) var suggestions: [InboxSuggestion] = []
    private(set) var itemReadModelByItemID: [UUID: InboxItemReadModel] = [:]
    private(set) var suggestionByItemID: [UUID: InboxSuggestion] = [:]

    var items: [InboxItem] {
        itemReadModels.map(\.item)
    }

    mutating func refresh(
        itemReadModels: [InboxItemReadModel],
        suggestions: [InboxSuggestion]
    ) {
        self.itemReadModels = sortedItemReadModels(itemReadModels)
        self.suggestions = sortedSuggestions(suggestions.deduplicatedByID())
        itemReadModelByItemID = Dictionary(
            uniqueKeysWithValues: self.itemReadModels.map { ($0.item.id, $0) }
        )
        rebuildSuggestionIndex()
    }

    mutating func refreshSuggestionScoped(
        inboxItemIDs: Set<UUID>,
        suggestions fetchedSuggestions: [InboxSuggestion]
    ) {
        guard inboxItemIDs.isEmpty == false else { return }
        suggestions = sortedSuggestions(
            (suggestions.filter { inboxItemIDs.contains($0.inboxItemID) == false } + fetchedSuggestions).deduplicatedByID()
        )
        rebuildSuggestionIndex()
    }

    private mutating func rebuildSuggestionIndex() {
        suggestionByItemID = InboxSuggestionIdentityService.index(
            items: items,
            suggestions: suggestions
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
            return lhs.id < rhs.id
        }
    }

    private func sortedSuggestions(_ suggestions: [InboxSuggestion]) -> [InboxSuggestion] {
        suggestions.sorted { lhs, rhs in
            if lhs.inboxItemID != rhs.inboxItemID {
                return lhs.inboxItemID < rhs.inboxItemID
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id > rhs.id
        }
    }
}
