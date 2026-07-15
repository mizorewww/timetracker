import Foundation
import SwiftData

@MainActor
struct InboxCommandHandler {
    @discardableResult
    func add(
        title: String,
        notes: String? = nil,
        existingItems: [InboxItem],
        context: ModelContext,
        deviceID: String = DeviceIdentity.current
    ) throws -> InboxItem? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let preparedText = try InboxPersistencePolicy.prepareItem(
            title: title,
            notes: notes,
            suggestionReason: nil
        )

        let nextSortOrder = (existingItems.filter { !$0.isCompleted }.map(\.sortOrder).max() ?? 0) + 10
        return try context.performAtomicMutation {
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
    }

    func toggle(
        _ item: InboxItem,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        let preparedText = try InboxPersistencePolicy.prepareItem(
            title: item.title,
            notes: item.notes,
            suggestionReason: item.suggestionReason
        )
        try context.performAtomicMutation {
            preparedText.apply(to: item)
            item.isCompleted.toggle()
            item.completedAt = item.isCompleted ? now : nil
            item.updatedAt = now
            item.deviceID = deviceID
            item.clientMutationID = UUID()
        }
    }

    func updateTitle(
        _ item: InboxItem,
        title: String,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            try softDelete(item, context: context, now: now, deviceID: deviceID)
            return
        }
        let preparedText = try InboxPersistencePolicy.prepareItem(
            title: title,
            notes: item.notes,
            suggestionReason: nil
        )
        guard item.title != preparedText.title else { return }
        let preparedSuggestions = try preparedSuggestionMutations(
            for: item.id,
            context: context
        )

        try context.performAtomicMutation {
            preparedText.apply(to: item)
            item.suggestedTaskID = nil
            item.suggestionGeneratedAt = nil
            item.updatedAt = now
            item.deviceID = deviceID
            item.clientMutationID = UUID()
            tombstone(preparedSuggestions, now: now, deviceID: deviceID)
        }
    }

    func softDelete(
        _ item: InboxItem,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        let preparedText = try InboxPersistencePolicy.prepareItem(
            title: item.title,
            notes: item.notes,
            suggestionReason: item.suggestionReason
        )
        let preparedSuggestions = try preparedSuggestionMutations(
            for: item.id,
            context: context
        )

        try context.performAtomicMutation {
            preparedText.apply(to: item)
            item.deletedAt = now
            item.updatedAt = now
            item.deviceID = deviceID
            item.clientMutationID = UUID()
            tombstone(preparedSuggestions, now: now, deviceID: deviceID)
        }
    }

    func reorderedOpenItemIDs(
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
        deviceID: String = DeviceIdentity.current
    ) throws {
        guard !orderedItemIDs.isEmpty else { return }
        let items = try context.fetch(FetchDescriptor<InboxItem>())
            .visibleDeduplicatedByID()
            .filter { $0.isCompleted == false }
        let itemByID = items.latestByID()
        guard orderedItemIDs.count == items.count,
              Set(orderedItemIDs) == Set(itemByID.keys) else { return }
        let orderedItems = orderedItemIDs.compactMap { itemByID[$0] }
        guard orderedItems.count == items.count else { return }

        let preparedItems = try orderedItems.map { item in
            (
                item,
                try InboxPersistencePolicy.prepareItem(
                    title: item.title,
                    notes: item.notes,
                    suggestionReason: item.suggestionReason
                )
            )
        }

        try context.performAtomicMutation {
            for (index, preparedItem) in preparedItems.enumerated() {
                let item = preparedItem.0
                preparedItem.1.apply(to: item)
                item.sortOrder = Double(index + 1) * 10
                item.updatedAt = now
                item.deviceID = deviceID
                item.clientMutationID = UUID()
            }
        }
    }
}
