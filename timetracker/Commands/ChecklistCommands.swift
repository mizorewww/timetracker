import Foundation
import SwiftData

@MainActor
struct ChecklistCommandHandler {
    private let orderingService = ChecklistOrderingService()

    @discardableResult
    func add(
        taskID: UUID,
        title: String,
        existingItems: [ChecklistItem],
        context: ModelContext,
        deviceID: String = DeviceIdentity.current
    ) throws -> ChecklistItem? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false else { return nil }

        let nextSortOrder = ((existingItems.map(\.sortOrder).max() ?? 0) + 10)
        let item = ChecklistItem(
            taskID: taskID,
            title: trimmedTitle,
            isCompleted: false,
            sortOrder: nextSortOrder,
            deviceID: deviceID
        )
        context.insert(item)
        try context.save()
        return item
    }

    func toggle(_ item: ChecklistItem, context: ModelContext, now: Date = Date()) throws {
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? now : nil
        item.updatedAt = now
        item.clientMutationID = UUID()
        try context.save()
    }

    func reorder(
        taskID: UUID,
        orderedItemIDs: [UUID],
        context: ModelContext,
        now: Date = Date()
    ) throws {
        let targetTaskID = taskID
        let items = try context.fetch(
            FetchDescriptor<ChecklistItem>(
                predicate: #Predicate { $0.taskID == targetTaskID && $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
            )
        )
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let orderedItems = orderedItemIDs.compactMap { itemByID[$0] }
        guard orderedItems.count == items.count else { return }

        for (index, item) in orderedItems.enumerated() {
            item.sortOrder = Double(index + 1) * 10
            item.updatedAt = now
            item.clientMutationID = UUID()
        }
        try context.save()
    }

    func reorderedIDs(
        items: [ChecklistItem],
        sourceOffsets: IndexSet,
        destination: Int
    ) -> [UUID]? {
        orderingService.reorderedIDs(
            elements: items.map {
                ChecklistOrderingElement(id: $0.id, isCompleted: $0.isCompleted)
            },
            sourceOffsets: sourceOffsets,
            destination: destination
        )
    }
}
