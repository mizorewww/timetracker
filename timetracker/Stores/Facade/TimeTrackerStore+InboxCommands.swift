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

    func addInboxItem(title: String) {
        perform(event: .inboxChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.add(
                title: title,
                existingItems: inboxItems,
                context: modelContext
            )
        }
    }

    func toggleInboxItem(_ item: InboxItem) {
        perform(event: .inboxChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.toggle(item, context: modelContext)
        }
    }

    func updateInboxItemTitle(_ item: InboxItem, title: String) {
        perform(event: .inboxChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.updateTitle(item, title: title, context: modelContext)
        }
    }

    func deleteInboxItem(_ item: InboxItem) {
        perform(event: .inboxChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.softDelete(item, context: modelContext)
        }
    }

    private func inboxSort(_ lhs: InboxItem, _ rhs: InboxItem) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.createdAt < rhs.createdAt
    }
}
