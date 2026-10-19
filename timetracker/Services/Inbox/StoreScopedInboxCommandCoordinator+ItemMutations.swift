import Foundation
import SwiftData

extension StoreScopedInboxCommandCoordinator {
    @discardableResult
    func add(
        title: String,
        notes: String? = nil,
        existingItems: [InboxItem],
        context: ModelContext,
        deviceID: String
    ) throws -> InboxItem? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let preparedText = try InboxPersistencePolicy.prepareItem(
            title: title,
            notes: notes,
            suggestionReason: nil
        )

        let nextSortOrder = SortOrderPolicy.after(existingItems.filter { !$0.isCompleted }.map(\.sortOrder).max())
        let item = InboxItem(
            title: preparedText.title,
            isCompleted: false,
            sortOrder: nextSortOrder,
            deviceID: deviceID
        )
        preparedText.apply(to: item)
        context.insert(item)
        return item
    }

    func toggle(
        _ item: InboxItem,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String
    ) throws {
        let logicalMutation = try preparedLogicalMutation(for: item, context: context)
        let winner = logicalMutation.winner.item
        guard winner.deletedAt == nil else { return }
        winner.materializeSuggestionIdentity()
        logicalMutation.materializeDismissal()
        logicalMutation.winner.text.apply(to: winner)
        winner.isCompleted.toggle()
        winner.completedAt = winner.isCompleted ? now : nil
        winner.markMutated(at: now, deviceID: deviceID)
        tombstoneSuperseded(
            logicalMutation.activeSiblings,
            winnerUpdatedAt: now,
            deviceID: deviceID
        )
    }

    func updateTitle(
        _ item: InboxItem,
        title: String,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String
    ) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            try softDelete(item, context: context, now: now, deviceID: deviceID)
            return
        }
        let logicalMutation = try preparedLogicalMutation(for: item, context: context)
        let winner = logicalMutation.winner.item
        guard winner.deletedAt == nil else { return }
        let preparedText = try InboxPersistencePolicy.prepareItem(
            title: title,
            notes: winner.notes,
            suggestionReason: nil
        )
        guard winner.title != preparedText.title else { return }
        let preparedSuggestions = try preparedSuggestionMutations(for: winner, context: context)

        winner.materializeSuggestionIdentity()
        preparedText.apply(to: winner)
        winner.suggestedTaskID = nil
        winner.suggestionGeneratedAt = nil
        winner.suggestionRevisionID = UUID()
        winner.dismissedSuggestionRevisionID = nil
        winner.markMutated(at: now, deviceID: deviceID)
        tombstone(preparedSuggestions, now: now, deviceID: deviceID)
        tombstoneSuperseded(
            logicalMutation.activeSiblings,
            winnerUpdatedAt: now,
            deviceID: deviceID
        )
    }

    func softDelete(
        _ item: InboxItem,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String
    ) throws {
        let logicalMutation = try preparedLogicalMutation(for: item, context: context)
        let winner = logicalMutation.winner.item
        guard winner.deletedAt == nil else { return }
        let preparedSuggestions = try preparedSuggestionMutations(for: winner, context: context)

        winner.materializeSuggestionIdentity()
        logicalMutation.materializeDismissal()
        logicalMutation.winner.text.apply(to: winner)
        winner.deletedAt = now
        winner.markMutated(at: now, deviceID: deviceID)
        tombstone(preparedSuggestions, now: now, deviceID: deviceID)
        tombstone(logicalMutation.activeSiblings, now: now, deviceID: deviceID)
    }

    static func reorderedOpenItemIDs(
        items: [InboxItem],
        sourceOffsets: IndexSet,
        destination: Int
    ) -> [UUID] {
        let ids = items.map(\.id)
        guard !sourceOffsets.isEmpty else { return ids }

        let moving = sourceOffsets.sorted().compactMap { index in
            ids.indices.contains(index) ? ids[index] : nil
        }
        let sourceSet = Set(sourceOffsets)
        var remaining = ids.enumerated()
            .filter { !sourceSet.contains($0.offset) }
            .map(\.element)
        let adjustedDestination = destination - sourceOffsets.filter { $0 < destination }.count
        let clampedDestination = min(max(0, adjustedDestination), remaining.count)
        remaining.insert(contentsOf: moving, at: clampedDestination)
        return remaining
    }

    func reorderOpenItems(
        orderedItemIDs: [UUID],
        context: ModelContext,
        now: Date = Date(),
        deviceID: String
    ) throws {
        guard !orderedItemIDs.isEmpty else { return }
        let items = try InboxSuggestionIdentityService.visibleLogicalItems(
            from: context.fetch(FetchDescriptor<InboxItem>())
        )
        .filter { $0.isCompleted == false }
        let itemByID = items.latestByID()
        guard orderedItemIDs.count == items.count,
              Set(orderedItemIDs) == Set(itemByID.keys) else { return }
        let orderedItems = orderedItemIDs.compactMap { itemByID[$0] }
        guard orderedItems.count == items.count else { return }

        let logicalMutations = try orderedItems.map {
            try preparedLogicalMutation(for: $0, context: context)
        }
        guard logicalMutations.map({ $0.winner.item.id }) == orderedItemIDs else { return }

        for (index, logicalMutation) in logicalMutations.enumerated() {
            let item = logicalMutation.winner.item
            item.materializeSuggestionIdentity()
            logicalMutation.materializeDismissal()
            logicalMutation.winner.text.apply(to: item)
            item.sortOrder = SortOrderPolicy.position(index)
            item.markMutated(at: now, deviceID: deviceID)
            tombstoneSuperseded(
                logicalMutation.activeSiblings,
                winnerUpdatedAt: now,
                deviceID: deviceID
            )
        }
    }
}
