import Foundation

extension TimeTrackerStore {
    func addInboxItem(title: String) {
        perform(event: .inboxChanged(itemIDs: [])) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.add(
                title: title,
                existingItems: inboxItems,
                context: modelContext
            )
        }
    }

    func toggleInboxItem(_ item: InboxItem) {
        perform(event: .inboxChanged(itemIDs: [item.id])) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.toggle(item, context: modelContext)
        }
    }

    func updateInboxItemTitle(_ item: InboxItem, title: String) {
        let oldTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let didUpdate = perform(event: .inboxChanged(itemIDs: [item.id])) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.updateTitle(item, title: title, context: modelContext)
        }
        if didUpdate, !newTitle.isEmpty, newTitle != oldTitle {
            inboxSuggestionFailureByItemID[item.id] = nil
            suggestInboxItem(item, showsErrors: false)
        }
    }

    func deleteInboxItem(_ item: InboxItem) {
        let didDelete = perform(event: .inboxChanged(itemIDs: [item.id])) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.softDelete(item, context: modelContext)
        }
        if didDelete {
            inboxSuggestionFailureByItemID[item.id] = nil
        }
    }

    func discardInboxSuggestion(_ item: InboxItem) {
        let didDiscard = perform(event: .inboxChanged(itemIDs: [item.id])) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.discardSuggestion(item, context: modelContext)
        }
        if didDiscard {
            inboxSuggestionFailureByItemID[item.id] = nil
        }
    }

    func reorderInboxItems(sourceOffsets: IndexSet, destination: Int) {
        let orderedIDs = inboxCommandHandler.reorderedOpenItemIDs(
            items: openInboxItems,
            sourceOffsets: sourceOffsets,
            destination: destination
        )
        perform(event: .inboxChanged(itemIDs: Set(orderedIDs))) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.reorderOpenItems(
                orderedItemIDs: orderedIDs,
                context: modelContext
            )
        }
    }
}
