import Foundation
import SwiftData

enum InboxCommandIdentityError: LocalizedError {
    case staleSuggestion

    var errorDescription: String? {
        "The inbox suggestion changed before this action completed."
    }
}

struct PreparedInboxItemMutation {
    let item: InboxItem
    let text: PreparedInboxItemText
}

struct PreparedInboxLogicalMutation {
    let winner: PreparedInboxItemMutation
    let activeSiblings: [PreparedInboxItemMutation]
}

extension InboxCommandHandler {
    func preparedLogicalMutation(
        for item: InboxItem,
        context: ModelContext
    ) throws -> PreparedInboxLogicalMutation {
        let itemID = item.id
        let contextID = item.effectiveSuggestionContextID
        let descriptor = FetchDescriptor<InboxItem>(
            predicate: #Predicate {
                $0.id == itemID || $0.id == contextID || $0.suggestionContextID == contextID
            }
        )
        var candidates = try context.fetch(descriptor).filter {
            $0.effectiveSuggestionContextID == contextID
        }
        if candidates.contains(where: { $0 === item }) == false {
            candidates.append(item)
        }
        let winner = InboxSuggestionIdentityService()
            .logicalWinners(from: candidates)
            .first { $0.effectiveSuggestionContextID == contextID } ?? item
        let preparedWinner = PreparedInboxItemMutation(
            item: winner,
            text: try InboxPersistencePolicy.prepareItem(
                title: winner.title,
                notes: winner.notes,
                suggestionReason: winner.suggestionReason
            )
        )
        let activeSiblings = try candidates
            .filter {
                $0 !== winner &&
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
        return PreparedInboxLogicalMutation(
            winner: preparedWinner,
            activeSiblings: activeSiblings
        )
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
