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
        try context.save()
        return item
    }

    func toggle(_ item: InboxItem, context: ModelContext, now: Date = Date()) throws {
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? now : nil
        item.updatedAt = now
        item.clientMutationID = UUID()
        try context.save()
    }

    func updateTitle(_ item: InboxItem, title: String, context: ModelContext, now: Date = Date()) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            try softDelete(item, context: context, now: now)
            return
        }
        guard item.title != trimmedTitle else { return }

        item.title = trimmedTitle
        item.suggestedTaskID = nil
        item.suggestionReason = nil
        item.suggestionGeneratedAt = nil
        item.updatedAt = now
        item.clientMutationID = UUID()
        try context.save()
    }

    func softDelete(_ item: InboxItem, context: ModelContext, now: Date = Date()) throws {
        item.deletedAt = now
        item.updatedAt = now
        item.clientMutationID = UUID()
        try context.save()
    }
}
