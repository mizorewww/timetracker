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

@MainActor
struct PreferenceCommandHandler {
    func set(key: AppPreferenceKey, valueJSON: String, context: ModelContext, now: Date = Date()) throws {
        let rawKey = key.rawValue
        let descriptor = FetchDescriptor<SyncedPreference>(
            predicate: #Predicate { $0.key == rawKey && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let existing = try context.fetch(descriptor)
        let target = existing.first ?? SyncedPreference(
            key: key.rawValue,
            valueJSON: valueJSON,
            deviceID: DeviceIdentity.current
        )
        if existing.isEmpty {
            context.insert(target)
        }
        target.valueJSON = valueJSON
        target.updatedAt = now
        target.deviceID = DeviceIdentity.current
        target.clientMutationID = UUID()
        for duplicate in existing.dropFirst() {
            duplicate.deletedAt = now
            duplicate.updatedAt = now
            duplicate.clientMutationID = UUID()
        }
        try context.save()
    }
}
