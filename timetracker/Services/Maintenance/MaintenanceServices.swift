import Foundation
import SwiftData

@MainActor
struct DatabaseMaintenanceService {
    nonisolated static let defaultTombstoneRetention: TimeInterval = 90 * 24 * 60 * 60

    @discardableResult
    func optimizeDatabase(
        context: ModelContext,
        now: Date = Date(),
        tombstoneRetention: TimeInterval = Self.defaultTombstoneRetention,
        allowsPermanentTombstonePurge override: Bool? = nil
    ) throws -> Int {
        // CloudKit has no per-device deletion acknowledgement. Purging a tombstone
        // while an old device is offline can let that device resurrect its visible
        // copy later, so physical deletion is deliberately local-only.
        let allowsPermanentTombstonePurge = override ?? AppCloudSync.allowsPermanentTombstonePurge
        guard allowsPermanentTombstonePurge else { return 0 }
        let cutoff = now.addingTimeInterval(-max(0, tombstoneRetention))
        let allTasks = try context.fetch(FetchDescriptor<TaskNode>())
        let allCategories = try context.fetch(FetchDescriptor<TaskCategory>())
        let allCategoryAssignments = try context.fetch(FetchDescriptor<TaskCategoryAssignment>())
        let allSegments = try context.fetch(FetchDescriptor<TimeSegment>())
        let allSessions = try context.fetch(FetchDescriptor<TimeSession>())
        let allRuns = try context.fetch(FetchDescriptor<PomodoroRun>())
        let allCountdownEvents = try context.fetch(FetchDescriptor<CountdownEvent>())
        let allPreferences = try context.fetch(FetchDescriptor<SyncedPreference>())
        let allChecklistItems = try context.fetch(FetchDescriptor<ChecklistItem>())
        let allChecklistVisuals = try context.fetch(FetchDescriptor<ChecklistItemVisual>())
        let allInboxItems = try context.fetch(FetchDescriptor<InboxItem>())
        let allInboxSuggestions = try context.fetch(FetchDescriptor<InboxSuggestion>())

        let expiredTaskIDs = expiredCanonicalIDs(in: allTasks, cutoff: cutoff)
        let expiredCategoryIDs = expiredCanonicalIDs(in: allCategories, cutoff: cutoff)
        let expiredSessionIDs = expiredCanonicalIDs(in: allSessions, cutoff: cutoff)
            .union(allSessions.filter { expiredTaskIDs.contains($0.taskID) }.map(\.id))
        let expiredChecklistItemIDs = expiredCanonicalIDs(in: allChecklistItems, cutoff: cutoff)
            .union(allChecklistItems.filter { expiredTaskIDs.contains($0.taskID) }.map(\.id))
        let expiredInboxItemIDs = expiredCanonicalIDs(in: allInboxItems, cutoff: cutoff)

        let tasksToDelete = allTasks.filter { expiredTaskIDs.contains($0.id) }
        let categoriesToDelete = allCategories.filter { expiredCategoryIDs.contains($0.id) }
        let assignmentsToDelete = allCategoryAssignments.filter {
            isExpired($0.deletedAt, cutoff: cutoff) ||
                expiredTaskIDs.contains($0.taskID) ||
                expiredCategoryIDs.contains($0.categoryID)
        }
        let sessionsToDelete = allSessions.filter { expiredSessionIDs.contains($0.id) }
        let segmentsToDelete = allSegments.filter {
            isExpired($0.deletedAt, cutoff: cutoff) ||
                expiredTaskIDs.contains($0.taskID) ||
                expiredSessionIDs.contains($0.sessionID)
        }
        let runsToDelete = allRuns.filter {
            isExpired($0.deletedAt, cutoff: cutoff) || expiredTaskIDs.contains($0.taskID)
        }
        let countdownsToDelete = allCountdownEvents.filter { isExpired($0.deletedAt, cutoff: cutoff) }
        let preferencesToDelete = allPreferences.filter { isExpired($0.deletedAt, cutoff: cutoff) }
        let checklistItemsToDelete = allChecklistItems.filter {
            expiredChecklistItemIDs.contains($0.id) || expiredTaskIDs.contains($0.taskID)
        }
        let checklistVisualsToDelete = allChecklistVisuals.filter {
            isExpired($0.deletedAt, cutoff: cutoff) || expiredChecklistItemIDs.contains($0.checklistItemID)
        }
        let inboxItemsToDelete = allInboxItems.filter { expiredInboxItemIDs.contains($0.id) }
        let inboxSuggestionsToDelete = allInboxSuggestions.filter {
            isExpired($0.deletedAt, cutoff: cutoff) ||
                expiredInboxItemIDs.contains($0.inboxItemID) ||
                expiredTaskIDs.contains($0.taskID)
        }

        tasksToDelete.forEach(context.delete)
        categoriesToDelete.forEach(context.delete)
        assignmentsToDelete.forEach(context.delete)
        segmentsToDelete.forEach(context.delete)
        sessionsToDelete.forEach(context.delete)
        runsToDelete.forEach(context.delete)
        countdownsToDelete.forEach(context.delete)
        preferencesToDelete.forEach(context.delete)
        checklistVisualsToDelete.forEach(context.delete)
        checklistItemsToDelete.forEach(context.delete)
        inboxSuggestionsToDelete.forEach(context.delete)
        inboxItemsToDelete.forEach(context.delete)

        let removedCount = tasksToDelete.count +
            categoriesToDelete.count +
            assignmentsToDelete.count +
            segmentsToDelete.count +
            sessionsToDelete.count +
            runsToDelete.count +
            countdownsToDelete.count +
            preferencesToDelete.count +
            checklistVisualsToDelete.count +
            checklistItemsToDelete.count +
            inboxSuggestionsToDelete.count +
            inboxItemsToDelete.count
        if removedCount > 0 {
            try context.saveAfterMutationStep()
        }
        return removedCount
    }

    private func expiredCanonicalIDs<Model>(
        in models: [Model],
        cutoff: Date
    ) -> Set<UUID> where Model: PersistentUUIDModel {
        Set(
            models
                .deduplicatedByID()
                .filter { isExpired($0.deletedAt, cutoff: cutoff) }
                .map(\.id)
        )
    }

    private func isExpired(_ deletedAt: Date?, cutoff: Date) -> Bool {
        guard let deletedAt else { return false }
        return deletedAt <= cutoff
    }
}
