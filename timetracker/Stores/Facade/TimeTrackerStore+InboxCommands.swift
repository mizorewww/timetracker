import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func addInboxItem(title: String) throws -> Bool {
        try performStoreScopedInboxMutation { coordinator in
            try coordinator.add(title: title)
        }.didMutate
    }

    func toggleInboxItem(_ item: InboxItem) throws {
        try performStoreScopedInboxMutation { coordinator in
            try coordinator.toggle(itemID: item.id)
        }
    }

    func updateInboxItemTitle(_ item: InboxItem, title: String) throws {
        let oldTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome = try performStoreScopedInboxMutation { coordinator in
            try coordinator.updateTitle(
                itemID: item.id,
                title: title
            )
        }
        if outcome.didMutate,
           !newTitle.isEmpty,
           newTitle != oldTitle,
           let updatedItem = inboxItems.first(where: { $0.id == item.id })
        {
            inboxSuggestionFailureByItemID[item.id] = nil
            suggestInboxItem(updatedItem, showsErrors: false)
        }
    }

    func deleteInboxItem(_ item: InboxItem) throws {
        let outcome = try performStoreScopedInboxMutation { coordinator in
            try coordinator.delete(itemID: item.id)
        }
        if outcome.didMutate {
            inboxSuggestionFailureByItemID[item.id] = nil
        }
    }

    func discardInboxSuggestion(_ item: InboxItem) throws {
        let outcome = try performStoreScopedInboxMutation { coordinator in
            try coordinator.discardSuggestion(itemID: item.id)
        }
        if outcome.didMutate {
            inboxSuggestionFailureByItemID[item.id] = nil
        }
    }

    func reorderInboxItems(sourceOffsets: IndexSet, destination: Int) throws {
        let currentItems = openInboxItems
        let orderedIDs = StoreScopedInboxCommandCoordinator.reorderedOpenItemIDs(
            items: currentItems,
            sourceOffsets: sourceOffsets,
            destination: destination
        )
        try performStoreScopedInboxMutation { coordinator in
            try coordinator.reorder(orderedItemIDs: orderedIDs)
        }
    }

    @discardableResult
    func performStoreScopedInboxMutation(
        _ action: (StoreScopedInboxCommandCoordinator) throws -> InboxMutationOutcome
    ) throws -> InboxMutationOutcome {
        try performStoreScopedInboxMutation(
            refreshScopes: [.inbox],
            eventsForOutcome: { $0.events },
            action
        )
    }

    func performStoreScopedInboxMutation<Outcome>(
        refreshScopes: Set<StoreRefreshScope>,
        eventsForOutcome: @escaping (Outcome) -> Set<StoreDomainEvent>,
        _ action: (StoreScopedInboxCommandCoordinator) throws -> Outcome
    ) throws -> Outcome {
        try performStoreCommand(
            eventsForOutcome: eventsForOutcome,
            onError: { error in
                if error is StoreScopedInboxMutationError {
                    self.refreshLoggingFailure(
                        plan: StoreRefreshPlan(scopes: refreshScopes)
                    )
                }
            },
            command: { session in
                try action(
                    StoreScopedInboxCommandCoordinator(
                        session: session
                    )
                )
            }
        )
    }

    func refreshStoreScopedInboxReadModels(scopes: Set<StoreRefreshScope>) {
        refreshLoggingFailure(plan: StoreRefreshPlan(scopes: scopes))
    }
}
