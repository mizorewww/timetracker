import Foundation
import SwiftData

@MainActor
struct ChecklistCommandHandler {
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
}
