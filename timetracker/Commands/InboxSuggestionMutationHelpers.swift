import Foundation
import SwiftData

extension InboxCommandHandler {
    func update(
        _ suggestion: InboxSuggestion,
        item: InboxItem,
        destination: InboxManualRouteDestination,
        text: PreparedInboxSuggestionText,
        now: Date,
        deviceID: String
    ) {
        text.apply(to: suggestion)
        suggestion.inboxItemID = item.id
        suggestion.inboxItemContextID = item.effectiveSuggestionContextID
        suggestion.inboxItemRevisionID = item.effectiveSuggestionRevisionID
        suggestion.taskID = destination.persistenceTargetID
        suggestion.destinationKindRaw = destination.suggestionDestinationKind.rawValue
        suggestion.generatedAt = now
        suggestion.updatedAt = now
        suggestion.deviceID = deviceID
        suggestion.clientMutationID = UUID()
    }

    func preparedSuggestionMutations(
        for item: InboxItem,
        context: ModelContext
    ) throws -> [PreparedInboxSuggestionMutation] {
        try suggestions(for: item, context: context)
            .deduplicatedByID()
            .map(prepareSuggestionMutation)
    }

    func preparedSuggestionMutations(
        for inboxItemID: UUID,
        context: ModelContext
    ) throws -> [PreparedInboxSuggestionMutation] {
        try context.fetch(
            FetchDescriptor<InboxSuggestion>(
                predicate: #Predicate { $0.inboxItemID == inboxItemID }
            )
        )
        .visibleDeduplicatedByID()
        .map(prepareSuggestionMutation)
    }

    func suggestions(
        for item: InboxItem,
        context: ModelContext
    ) throws -> [InboxSuggestion] {
        let itemID = item.id
        let contextID = item.effectiveSuggestionContextID
        let descriptor = FetchDescriptor<InboxSuggestion>(
            predicate: #Predicate {
                $0.inboxItemID == itemID ||
                    $0.inboxItemID == contextID ||
                    $0.inboxItemContextID == contextID
            }
        )
        return try context.fetch(descriptor).filter {
            $0.inboxItemID == itemID ||
                $0.inboxItemID == contextID ||
                $0.inboxItemContextID == contextID
        }
    }

    func prepareSuggestionMutation(
        _ suggestion: InboxSuggestion
    ) throws -> PreparedInboxSuggestionMutation {
        PreparedInboxSuggestionMutation(
            suggestion: suggestion,
            text: try InboxPersistencePolicy.prepareSuggestion(
                reason: suggestion.reason,
                iconName: suggestion.iconName,
                colorHex: suggestion.colorHex,
                modelID: suggestion.modelID,
                titleSnapshot: suggestion.titleSnapshot
            )
        )
    }

    func tombstone(
        _ preparedSuggestions: [PreparedInboxSuggestionMutation],
        now: Date,
        deviceID: String
    ) {
        for preparedSuggestion in preparedSuggestions {
            preparedSuggestion.text.apply(to: preparedSuggestion.suggestion)
            softDelete(preparedSuggestion.suggestion, now: now, deviceID: deviceID)
        }
    }

    func softDelete(_ suggestion: InboxSuggestion, now: Date, deviceID: String) {
        suggestion.deletedAt = now
        suggestion.updatedAt = now
        suggestion.deviceID = deviceID
        suggestion.clientMutationID = UUID()
    }
}
