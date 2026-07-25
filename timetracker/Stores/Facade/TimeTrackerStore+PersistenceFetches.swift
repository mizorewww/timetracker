import Foundation
import SwiftData

extension TimeTrackerStore {
    func fetchSyncedPreferences() throws -> [SyncedPreference] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<SyncedPreference>(
            sortBy: [
                SortDescriptor(\.key),
                SortDescriptor(\.updatedAt, order: .reverse),
            ]
        )
        let all = try modelContext.fetch(descriptor)
        return SyncedPreferenceService.latestByKey(all.deduplicatedByID())
            .values
            .filter { $0.deletedAt == nil && SyncedPreferenceService.shouldSyncKey($0.key) }
            .sorted { $0.key < $1.key }
    }

    func fetchChecklistItems() throws -> [ChecklistItem] {
        guard let modelContext else { return [] }
        return try modelContext.fetch(FetchDescriptor<ChecklistItem>())
            .visibleDeduplicatedByID()
            .sorted(by: checklistItemOrder)
    }

    func fetchChecklistItems(taskIDs: Set<UUID>) throws -> [ChecklistItem] {
        guard let modelContext, taskIDs.isEmpty == false else { return [] }
        let requestedTaskIDs = Array(taskIDs)
        let descriptor = FetchDescriptor<ChecklistItem>(
            predicate: #Predicate { requestedTaskIDs.contains($0.taskID) }
        )
        return try modelContext.fetch(descriptor)
            .visibleDeduplicatedByID()
            .filter { taskIDs.contains($0.taskID) }
            .sorted(by: checklistItemOrder)
    }

    func fetchChecklistItemVisuals() throws -> [ChecklistItemVisual] {
        guard let modelContext else { return [] }
        let all = try modelContext.fetch(FetchDescriptor<ChecklistItemVisual>())
            .deduplicatedByID()
        return all.logicalWinnersByChecklistItemID().values
            .filter { $0.deletedAt == nil }
            .sorted(by: checklistVisualOrder)
    }

    func fetchChecklistItemVisuals(checklistItemIDs: Set<UUID>) throws -> [ChecklistItemVisual] {
        guard let modelContext, checklistItemIDs.isEmpty == false else { return [] }
        let requestedItemIDs = Array(checklistItemIDs)
        let descriptor = FetchDescriptor<ChecklistItemVisual>(
            predicate: #Predicate { requestedItemIDs.contains($0.checklistItemID) }
        )
        let all = try modelContext.fetch(descriptor)
            .deduplicatedByID()
            .filter { checklistItemIDs.contains($0.checklistItemID) }
        return all.logicalWinnersByChecklistItemID().values
            .filter { $0.deletedAt == nil }
            .sorted(by: checklistVisualOrder)
    }

    func fetchInboxItems() throws -> [InboxItem] {
        try fetchInboxItemReadModels().map(\.item)
    }

    func fetchInboxItemReadModels() throws -> [InboxItemReadModel] {
        guard let modelContext else { return [] }
        return try InboxSuggestionIdentityService().visibleLogicalReadModels(
            from: modelContext.fetch(FetchDescriptor<InboxItem>())
        )
    }

    func fetchInboxSuggestions() throws -> [InboxSuggestion] {
        guard let modelContext else { return [] }
        return try modelContext.fetch(FetchDescriptor<InboxSuggestion>())
            .visibleDeduplicatedByID()
            .sorted { lhs, rhs in lhs.createdAt < rhs.createdAt }
    }

    func fetchInboxSuggestions(inboxItemIDs: Set<UUID>) throws -> [InboxSuggestion] {
        guard let modelContext, inboxItemIDs.isEmpty == false else { return [] }
        let requestedItemIDs = Array(inboxItemIDs)
        let descriptor = FetchDescriptor<InboxSuggestion>(
            predicate: #Predicate { requestedItemIDs.contains($0.inboxItemID) }
        )
        return try modelContext.fetch(descriptor)
            .visibleDeduplicatedByID()
            .filter { inboxItemIDs.contains($0.inboxItemID) }
            .sorted { lhs, rhs in lhs.createdAt < rhs.createdAt }
    }

    func fetchCountdownEvents() throws -> [CountdownEvent] {
        guard let modelContext else { return [] }
        return try modelContext.fetch(FetchDescriptor<CountdownEvent>())
            .visibleDeduplicatedByID()
            .sorted { lhs, rhs in
                if lhs.date != rhs.date {
                    return lhs.date < rhs.date
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func checklistItemOrder(_ lhs: ChecklistItem, _ rhs: ChecklistItem) -> Bool {
        if lhs.taskID != rhs.taskID {
            return lhs.taskID.uuidString < rhs.taskID.uuidString
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func checklistVisualOrder(
        _ lhs: ChecklistItemVisual,
        _ rhs: ChecklistItemVisual
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
