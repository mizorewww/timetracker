import Foundation
import SwiftData

extension TimeTrackerStore {
    func fetchSyncedPreferences() throws -> [SyncedPreference] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<SyncedPreference>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.key),
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        let all = try modelContext.fetch(descriptor)
        return SyncedPreferenceService.latestByKey(all.deduplicatedByID())
            .values
            .sorted { $0.key < $1.key }
    }

    func fetchChecklistItems() throws -> [ChecklistItem] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<ChecklistItem>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.taskID),
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        )
        return try modelContext.fetch(descriptor).deduplicatedByID()
    }

    func fetchChecklistItems(taskIDs: Set<UUID>) throws -> [ChecklistItem] {
        guard let modelContext, taskIDs.isEmpty == false else { return [] }
        let requestedTaskIDs = Array(taskIDs)
        let descriptor = FetchDescriptor<ChecklistItem>(
            predicate: #Predicate { requestedTaskIDs.contains($0.taskID) && $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.taskID),
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        )
        return try modelContext.fetch(descriptor).deduplicatedByID()
    }

    func fetchChecklistItemVisuals() throws -> [ChecklistItemVisual] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<ChecklistItemVisual>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.checklistItemID),
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        let all = try modelContext.fetch(descriptor).deduplicatedByID()
        return Dictionary(grouping: all, by: \.checklistItemID)
            .values
            .compactMap { visuals in
                visuals.sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }.first
            }
            .sorted { lhs, rhs in lhs.createdAt < rhs.createdAt }
    }

    func fetchChecklistItemVisuals(checklistItemIDs: Set<UUID>) throws -> [ChecklistItemVisual] {
        guard let modelContext, checklistItemIDs.isEmpty == false else { return [] }
        let requestedItemIDs = Array(checklistItemIDs)
        let descriptor = FetchDescriptor<ChecklistItemVisual>(
            predicate: #Predicate { requestedItemIDs.contains($0.checklistItemID) && $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.checklistItemID),
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        let all = try modelContext.fetch(descriptor).deduplicatedByID()
        return Dictionary(grouping: all, by: \.checklistItemID)
            .values
            .compactMap { visuals in
                visuals.sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }.first
            }
            .sorted { lhs, rhs in lhs.createdAt < rhs.createdAt }
    }

    func fetchInboxItems() throws -> [InboxItem] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<InboxItem>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        )
        return try modelContext.fetch(descriptor).deduplicatedByID()
    }

    func fetchInboxSuggestions() throws -> [InboxSuggestion] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<InboxSuggestion>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.inboxItemID),
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        let all = try modelContext.fetch(descriptor).deduplicatedByID()
        return Dictionary(grouping: all, by: \.inboxItemID)
            .values
            .compactMap { suggestions in
                suggestions.sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }.first
            }
            .sorted { lhs, rhs in lhs.createdAt < rhs.createdAt }
    }

    func fetchInboxSuggestions(inboxItemIDs: Set<UUID>) throws -> [InboxSuggestion] {
        guard let modelContext, inboxItemIDs.isEmpty == false else { return [] }
        let requestedItemIDs = Array(inboxItemIDs)
        let descriptor = FetchDescriptor<InboxSuggestion>(
            predicate: #Predicate { requestedItemIDs.contains($0.inboxItemID) && $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.inboxItemID),
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        let all = try modelContext.fetch(descriptor).deduplicatedByID()
        return Dictionary(grouping: all, by: \.inboxItemID)
            .values
            .compactMap { suggestions in
                suggestions.sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }.first
            }
            .sorted { lhs, rhs in lhs.createdAt < rhs.createdAt }
    }

    func fetchCountdownEvents() throws -> [CountdownEvent] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<CountdownEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.date),
                SortDescriptor(\.createdAt)
            ]
        )
        return try modelContext.fetch(descriptor).deduplicatedByID()
    }
}
