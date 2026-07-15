import Foundation
import SwiftData

struct PreparedInboxItemMutation {
    let item: InboxItem
    let text: PreparedInboxItemText
}

extension InboxCommandHandler {
    func preparedLogicalSiblingMutations(
        for item: InboxItem,
        context: ModelContext
    ) throws -> [PreparedInboxItemMutation] {
        let itemID = item.id
        let contextID = item.effectiveSuggestionContextID
        let descriptor = FetchDescriptor<InboxItem>(
            predicate: #Predicate {
                $0.id == itemID || $0.id == contextID || $0.suggestionContextID == contextID
            }
        )
        return try context.fetch(descriptor)
            .deduplicatedByID()
            .filter {
                $0.id != itemID &&
                    $0.deletedAt == nil &&
                    $0.effectiveSuggestionContextID == contextID
            }
            .map { sibling in
                PreparedInboxItemMutation(
                    item: sibling,
                    text: try InboxPersistencePolicy.prepareItem(
                        title: sibling.title,
                        notes: sibling.notes,
                        suggestionReason: sibling.suggestionReason
                    )
                )
            }
    }

    func tombstone(
        _ preparedItems: [PreparedInboxItemMutation],
        now: Date,
        deviceID: String
    ) {
        for preparedItem in preparedItems {
            preparedItem.text.apply(to: preparedItem.item)
            preparedItem.item.deletedAt = now
            preparedItem.item.updatedAt = now
            preparedItem.item.deviceID = deviceID
            preparedItem.item.clientMutationID = UUID()
        }
    }

    func tombstoneSuperseded(
        _ preparedItems: [PreparedInboxItemMutation],
        winnerUpdatedAt: Date,
        deviceID: String
    ) {
        tombstone(
            preparedItems,
            now: winnerUpdatedAt.addingTimeInterval(-1),
            deviceID: deviceID
        )
    }
}
