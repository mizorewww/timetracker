import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func addInboxItem(title: String) -> Bool {
        performStoreScopedInboxMutation { coordinator in
            try coordinator.add(title: title)
        }?.didMutate == true
    }

    func toggleInboxItem(_ item: InboxItem) {
        _ = performStoreScopedInboxMutation { coordinator in
            try coordinator.toggle(baseline: InboxItemMutationBaseline(item: item))
        }
    }

    func updateInboxItemTitle(_ item: InboxItem, title: String) {
        let oldTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome = performStoreScopedInboxMutation { coordinator in
            try coordinator.updateTitle(
                baseline: InboxItemMutationBaseline(item: item),
                title: title
            )
        }
        if outcome?.didMutate == true,
           !newTitle.isEmpty,
           newTitle != oldTitle,
           let updatedItem = inboxItems.first(where: { $0.id == item.id })
        {
            inboxSuggestionFailureByItemID[item.id] = nil
            suggestInboxItem(updatedItem, showsErrors: false)
        }
    }

    func deleteInboxItem(_ item: InboxItem) {
        let outcome = performStoreScopedInboxMutation { coordinator in
            try coordinator.delete(baseline: InboxItemMutationBaseline(item: item))
        }
        if outcome?.didMutate == true {
            inboxSuggestionFailureByItemID[item.id] = nil
        }
    }

    func discardInboxSuggestion(_ item: InboxItem) {
        let outcome = performStoreScopedInboxMutation { coordinator in
            try coordinator.discardSuggestion(baseline: InboxItemMutationBaseline(item: item))
        }
        if outcome?.didMutate == true {
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
        return performStoreScopedInboxMutation { coordinator in
            try coordinator.reorder(
                baseline: InboxOrderMutationBaseline(items: currentItems),
                orderedItemIDs: orderedIDs
            )
        } != nil
    }

    func performStoreScopedInboxMutation(
        _ action: (StoreScopedInboxCommandCoordinator) throws -> InboxMutationOutcome
    ) -> InboxMutationOutcome? {
        performStoreScopedInboxMutation(
            refreshScopes: [.inbox],
            eventsForOutcome: { $0.events },
            action
        )
    }

    func performStoreScopedInboxMutation<Outcome>(
        refreshScopes: Set<StoreRefreshScope>,
        eventsForOutcome: @escaping (Outcome) -> Set<StoreDomainEvent>,
        _ action: (StoreScopedInboxCommandCoordinator) throws -> Outcome
    ) -> Outcome? {
        performStoreCommand(
            eventsForOutcome: eventsForOutcome,
            onError: { error in
                if error is StoreScopedInboxMutationError {
                    do {
                        try self.refresh(plan: StoreRefreshPlan(scopes: refreshScopes))
                    } catch {
                        self.errorMessage = self.savedRefreshFailedMessage(error)
                        return
                    }
                }
                self.errorMessage = error.localizedDescription
            },
            command: { container in
                try action(
                    StoreScopedInboxCommandCoordinator(
                        container: container,
                        writeAuthorization: writeAuthorization
                    )
                )
            }
        )
    }

    func refreshStoreScopedInboxReadModels(scopes: Set<StoreRefreshScope>) {
        do {
            try refresh(plan: StoreRefreshPlan(scopes: scopes))
        } catch {
            errorMessage = savedRefreshFailedMessage(error)
        }
    }
}
