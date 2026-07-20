import Foundation
import SwiftData

extension SyncDataSnapshot {
    func restoreInboxItems(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = try context.fetch(FetchDescriptor<InboxItem>())
            .latestByIDMarkingDuplicatesDeleted(now: now, deviceID: deviceID)
        let snapshotIDs = Set(inboxItems.map(\.id))
        let logicalWinnerIDs = logicalInboxItemWinnerIDs()
        let itemIdentityByID = inboxItems.reduce(into: [UUID: InboxSuggestionIdentity]()) { result, item in
            result[item.id] = InboxSuggestionIdentity(
                contextID: item.suggestionContextID ?? item.id,
                revisionID: item.suggestionRevisionID ?? item.id
            )
        }
        let activeSuggestionItemIDs = Set(
            inboxSuggestions.lazy.filter { $0.deletedAt == nil }.map(\.inboxItemID)
        )
        let activeSuggestionIdentities = Set(
            inboxSuggestions.lazy.filter { $0.deletedAt == nil }.map { suggestion in
                let itemIdentity = itemIdentityByID[suggestion.inboxItemID]
                return InboxSuggestionIdentity(
                    contextID: suggestion.inboxItemContextID ?? itemIdentity?.contextID ?? suggestion.inboxItemID,
                    revisionID: suggestion.inboxItemRevisionID ?? itemIdentity?.revisionID ?? suggestion.inboxItemID
                )
            }
        )
        let dismissedIdentities = Set(inboxItems.compactMap { record -> InboxSuggestionIdentity? in
            let identity = record.effectiveSuggestionIdentity
            let hasActiveSuggestion = activeSuggestionItemIDs.contains(record.id) ||
                activeSuggestionIdentities.contains(identity)
            let dismissedRevisionID = record.dismissedSuggestionRevisionID ?? (
                record.suggestionGeneratedAt != nil && hasActiveSuggestion == false
                    ? identity.revisionID
                    : nil
            )
            return dismissedRevisionID == identity.revisionID ? identity : nil
        })
        // Keep rows absent from the snapshot older than restored rows. This matters
        // when two physical UUIDs represent the same logical Inbox item.
        let supersededAt = now.addingTimeInterval(-1)
        for item in existing.values where !snapshotIDs.contains(item.id) {
            item.deletedAt = supersededAt
            item.updatedAt = supersededAt
            item.deviceID = deviceID
            item.clientMutationID = UUID()
        }
        for record in inboxItems {
            let contextID = record.suggestionContextID ?? record.id
            let revisionID = record.suggestionRevisionID ?? record.id
            let identity = InboxSuggestionIdentity(contextID: contextID, revisionID: revisionID)
            let hasActiveSuggestion = activeSuggestionItemIDs.contains(record.id) ||
                activeSuggestionIdentities.contains(identity)
            let recordDismissedRevisionID = record.dismissedSuggestionRevisionID ?? (
                record.suggestionGeneratedAt != nil && hasActiveSuggestion == false
                    ? revisionID
                    : nil
            )
            let dismissedRevisionID = dismissedIdentities.contains(identity)
                ? revisionID
                : recordDismissedRevisionID
            let model = existing[record.id] ?? InboxItem(
                title: record.title,
                isCompleted: record.isCompleted,
                sortOrder: record.sortOrder,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.suggestionContextID = contextID
            model.suggestionRevisionID = revisionID
            model.dismissedSuggestionRevisionID = dismissedRevisionID
            model.title = record.title
            model.notes = record.notes
            model.isCompleted = record.isCompleted
            model.sortOrder = record.sortOrder
            model.completedAt = record.completedAt
            model.suggestedTaskID = record.suggestedTaskID
            model.suggestionReason = record.suggestionReason
            model.suggestionGeneratedAt = record.suggestionGeneratedAt
            model.createdAt = record.createdAt
            // Restore the snapshot as the local winner without flattening every
            // physical sibling to the same timestamp. Only the source snapshot's
            // logical winner is advanced; older revisions retain their ordering.
            model.updatedAt = logicalWinnerIDs.contains(record.id)
                ? max(record.updatedAt, now)
                : record.updatedAt
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            // Snapshot records do not carry mutation metadata. Reusing the opaque
            // record UUID makes exact timestamp/creation ties deterministic.
            model.clientMutationID = record.id
        }
    }

    private func logicalInboxItemWinnerIDs() -> Set<UUID> {
        var winnersByContextID: [UUID: InboxItemRecord] = [:]
        winnersByContextID.reserveCapacity(inboxItems.count)
        for record in inboxItems {
            let contextID = record.effectiveSuggestionIdentity.contextID
            if let current = winnersByContextID[contextID] {
                if record.isPreferredLogicalWinner(over: current) {
                    winnersByContextID[contextID] = record
                }
            } else {
                winnersByContextID[contextID] = record
            }
        }
        return Set(winnersByContextID.values.map(\.id))
    }

    func restoreInboxSuggestions(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = try context.fetch(FetchDescriptor<InboxSuggestion>())
            .latestByIDMarkingDuplicatesDeleted(now: now, deviceID: deviceID)
        let snapshotIDs = Set(inboxSuggestions.map(\.id))
        let itemIdentityByID = inboxItems.reduce(into: [UUID: InboxSuggestionIdentity]()) { result, item in
            result[item.id] = InboxSuggestionIdentity(
                contextID: item.suggestionContextID ?? item.id,
                revisionID: item.suggestionRevisionID ?? item.id
            )
        }
        let canonicalSuggestionIDs = canonicalInboxSuggestionIDs(
            itemIdentityByID: itemIdentityByID
        )
        for suggestion in existing.values where !snapshotIDs.contains(suggestion.id) {
            suggestion.deletedAt = now
            suggestion.updatedAt = now
            suggestion.deviceID = deviceID
            suggestion.clientMutationID = UUID()
        }
        for record in inboxSuggestions {
            let itemIdentity = itemIdentityByID[record.inboxItemID]
            let contextID = record.inboxItemContextID ?? itemIdentity?.contextID ?? record.inboxItemID
            let revisionID = record.inboxItemRevisionID ?? itemIdentity?.revisionID ?? record.inboxItemID
            let model = existing[record.id] ?? InboxSuggestion(
                inboxItemID: record.inboxItemID,
                inboxItemContextID: contextID,
                inboxItemRevisionID: revisionID,
                taskID: record.taskID,
                reason: record.reason,
                iconName: record.iconName,
                colorHex: record.colorHex,
                modelID: record.modelID,
                titleSnapshot: record.titleSnapshot,
                generatedAt: record.generatedAt,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.inboxItemID = record.inboxItemID
            model.inboxItemContextID = contextID
            model.inboxItemRevisionID = revisionID
            model.taskID = record.taskID
            model.destinationKindRaw = record.destinationKindRaw
            model.reason = record.reason
            model.iconName = record.iconName
            model.colorHex = record.colorHex
            model.modelID = record.modelID
            model.titleSnapshot = record.titleSnapshot
            model.generatedAt = record.generatedAt
            model.createdAt = record.createdAt
            // Advance only the source snapshot's active canonical winner. Lifting
            // every sibling erases source ordering and lets the UUID tie-breaker
            // select a formerly stale suggestion after restore.
            model.updatedAt = canonicalSuggestionIDs.contains(record.id)
                ? max(record.updatedAt, now)
                : record.updatedAt
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = record.id
        }
    }

    private func canonicalInboxSuggestionIDs(
        itemIdentityByID: [UUID: InboxSuggestionIdentity]
    ) -> Set<UUID> {
        var winnersByIdentity: [InboxSuggestionIdentity: InboxSuggestionRecord] = [:]
        winnersByIdentity.reserveCapacity(inboxSuggestions.count)
        for record in inboxSuggestions where record.deletedAt == nil {
            let itemIdentity = itemIdentityByID[record.inboxItemID]
            let identity = InboxSuggestionIdentity(
                contextID: record.inboxItemContextID ?? itemIdentity?.contextID ?? record.inboxItemID,
                revisionID: record.inboxItemRevisionID ?? itemIdentity?.revisionID ?? record.inboxItemID
            )
            guard let current = winnersByIdentity[identity] else {
                winnersByIdentity[identity] = record
                continue
            }
            if record.updatedAt > current.updatedAt ||
                (record.updatedAt == current.updatedAt && record.id.uuidString > current.id.uuidString) {
                winnersByIdentity[identity] = record
            }
        }
        return Set(winnersByIdentity.values.map(\.id))
    }
}
