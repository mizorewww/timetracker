import Foundation
import SwiftData

@MainActor
struct InboxCommandHandler {
    @discardableResult
    func add(
        title: String,
        existingItems: [InboxItem],
        context: ModelContext,
        deviceID: String = DeviceIdentity.current
    ) throws -> InboxItem? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let nextSortOrder = (existingItems.filter { !$0.isCompleted }.map(\.sortOrder).max() ?? 0) + 10
        let item = InboxItem(
            title: trimmedTitle,
            isCompleted: false,
            sortOrder: nextSortOrder,
            deviceID: deviceID
        )
        context.insert(item)
        try context.saveAfterMutationStep()
        return item
    }

    func toggle(
        _ item: InboxItem,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? now : nil
        item.updatedAt = now
        item.deviceID = deviceID
        item.clientMutationID = UUID()
        try context.saveAfterMutationStep()
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
        guard item.title != trimmedTitle else { return }

        item.title = trimmedTitle
        item.suggestedTaskID = nil
        item.suggestionReason = nil
        item.suggestionGeneratedAt = nil
        item.updatedAt = now
        item.deviceID = deviceID
        item.clientMutationID = UUID()
        try clearSuggestions(for: item.id, context: context, now: now, deviceID: deviceID)
        try context.saveAfterMutationStep()
    }

    func softDelete(
        _ item: InboxItem,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        item.deletedAt = now
        item.updatedAt = now
        item.deviceID = deviceID
        item.clientMutationID = UUID()
        try clearSuggestions(for: item.id, context: context, now: now, deviceID: deviceID)
        try context.saveAfterMutationStep()
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

        for (index, item) in orderedItems.enumerated() {
            item.sortOrder = Double(index + 1) * 10
            item.updatedAt = now
            item.deviceID = deviceID
            item.clientMutationID = UUID()
        }
        try context.saveAfterMutationStep()
    }
}
