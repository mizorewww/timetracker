import Foundation

nonisolated struct InboxSuggestionIdentity: Hashable, Sendable {
    let contextID: UUID
    let revisionID: UUID
}

extension InboxItem {
    var effectiveSuggestionContextID: UUID {
        suggestionContextID ?? id
    }

    var effectiveSuggestionRevisionID: UUID {
        suggestionRevisionID ?? id
    }

    var suggestionIdentity: InboxSuggestionIdentity {
        InboxSuggestionIdentity(
            contextID: effectiveSuggestionContextID,
            revisionID: effectiveSuggestionRevisionID
        )
    }

    var isCurrentSuggestionRevisionDismissed: Bool {
        dismissedSuggestionRevisionID == effectiveSuggestionRevisionID
    }

    func materializeSuggestionIdentity() {
        if suggestionContextID == nil {
            suggestionContextID = id
        }
        if suggestionRevisionID == nil {
            suggestionRevisionID = id
        }
    }
}

extension InboxSuggestion {
    var explicitInboxItemIdentity: InboxSuggestionIdentity? {
        guard let inboxItemContextID, let inboxItemRevisionID else { return nil }
        return InboxSuggestionIdentity(
            contextID: inboxItemContextID,
            revisionID: inboxItemRevisionID
        )
    }

    func belongs(to item: InboxItem) -> Bool {
        if let explicitInboxItemIdentity {
            return explicitInboxItemIdentity == item.suggestionIdentity
        }
        return inboxItemID == item.id || inboxItemID == item.effectiveSuggestionContextID
    }
}

struct InboxSuggestionIdentityService {
    func visibleLogicalItems<S: Sequence>(from items: S) -> [InboxItem]
    where S.Element == InboxItem {
        logicalWinners(from: items).filter { $0.deletedAt == nil }
    }

    func logicalWinners<S: Sequence>(from items: S) -> [InboxItem]
    where S.Element == InboxItem {
        var winners: [UUID: InboxItem] = [:]
        for item in items.deduplicatedByID() {
            let contextID = item.effectiveSuggestionContextID
            if let existing = winners[contextID] {
                if isPreferred(item, over: existing) {
                    winners[contextID] = item
                }
            } else {
                winners[contextID] = item
            }
        }
        return Array(winners.values)
    }

    func index(
        items: [InboxItem],
        suggestions: [InboxSuggestion]
    ) -> [UUID: InboxSuggestion] {
        var byIdentity: [InboxSuggestionIdentity: InboxSuggestion] = [:]
        var legacyByPhysicalItemID: [UUID: InboxSuggestion] = [:]

        // Resolve same-ID CloudKit duplicates before hiding tombstones.
        for suggestion in suggestions.deduplicatedByID() where suggestion.deletedAt == nil {
            if let identity = suggestion.explicitInboxItemIdentity {
                keepNewest(suggestion, in: &byIdentity, key: identity)
            } else {
                keepNewest(suggestion, in: &legacyByPhysicalItemID, key: suggestion.inboxItemID)
            }
        }

        return items.reduce(into: [:]) { result, item in
            if let suggestion = byIdentity[item.suggestionIdentity] ??
                legacyByPhysicalItemID[item.id] ??
                legacyByPhysicalItemID[item.effectiveSuggestionContextID] {
                result[item.id] = suggestion
            }
        }
    }

    private func isPreferred(_ candidate: InboxItem, over existing: InboxItem) -> Bool {
        // Deletion and an explicit restore use last-write-wins. A tombstone wins a tie,
        // preventing an older active physical copy from resurfacing after sync.
        if (candidate.deletedAt == nil) != (existing.deletedAt == nil) {
            if candidate.updatedAt != existing.updatedAt {
                return candidate.updatedAt > existing.updatedAt
            }
            return candidate.deletedAt != nil
        }
        // Dismissal is monotonic within a title revision. Editing rotates the revision.
        if candidate.effectiveSuggestionRevisionID == existing.effectiveSuggestionRevisionID,
           candidate.isCurrentSuggestionRevisionDismissed != existing.isCurrentSuggestionRevisionDismissed {
            return candidate.isCurrentSuggestionRevisionDismissed
        }
        if candidate.updatedAt != existing.updatedAt {
            return candidate.updatedAt > existing.updatedAt
        }
        if candidate.createdAt != existing.createdAt {
            return candidate.createdAt > existing.createdAt
        }
        if candidate.deviceID != existing.deviceID {
            return candidate.deviceID > existing.deviceID
        }
        if candidate.clientMutationID != existing.clientMutationID {
            return candidate.clientMutationID.uuidString > existing.clientMutationID.uuidString
        }
        return candidate.id.uuidString > existing.id.uuidString
    }

    private func keepNewest<Key: Hashable>(
        _ suggestion: InboxSuggestion,
        in index: inout [Key: InboxSuggestion],
        key: Key
    ) {
        guard let existing = index[key] else {
            index[key] = suggestion
            return
        }
        if suggestion.updatedAt > existing.updatedAt ||
            (suggestion.updatedAt == existing.updatedAt && suggestion.id.uuidString > existing.id.uuidString) {
            index[key] = suggestion
        }
    }
}
