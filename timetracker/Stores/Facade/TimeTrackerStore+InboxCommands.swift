import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func addInboxItem(title: String) -> Bool {
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

    @discardableResult
    func reorderInboxItems(sourceOffsets: IndexSet, destination: Int) -> Bool {
        let currentItems = openInboxItems
        let orderedIDs = inboxCommandHandler.reorderedOpenItemIDs(
            items: currentItems,
            sourceOffsets: sourceOffsets,
            destination: destination
        )
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try StoreScopedInboxCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).reorder(
                baseline: InboxOrderMutationBaseline(items: currentItems),
                orderedItemIDs: orderedIDs
            )
            finishStoreScopedMutation(events: outcome.events)
            return true
        } catch {
            if error is StoreScopedInboxMutationError {
                do {
                    try refresh(plan: StoreRefreshPlan(scopes: [.inbox]))
                } catch {
                    errorMessage = String(
                        format: AppStrings.localized("error.savedRefreshFailed"),
                        error.localizedDescription
                    )
                    return false
                }
            }
            errorMessage = error.localizedDescription
            return false
        }
    }
}
