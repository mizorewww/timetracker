import Foundation
import SwiftData

@MainActor
struct DatabaseMaintenanceService {
    nonisolated static let defaultTombstoneRetention: TimeInterval = 90 * 24 * 60 * 60
    nonisolated static let defaultFetchBatchSize = 512

    @discardableResult
    func optimizeDatabase(
        context: ModelContext,
        now: Date = Date(),
        tombstoneRetention: TimeInterval = Self.defaultTombstoneRetention,
        allowsPermanentTombstonePurge override: Bool? = nil,
        fetchBatchSize: Int = Self.defaultFetchBatchSize
    ) throws -> Int {
        // CloudKit has no per-device deletion acknowledgement. Purging a tombstone
        // while an old device is offline can let that device resurrect its visible
        // copy later, so physical deletion is deliberately local-only.
        let allowsPermanentTombstonePurge = override ?? AppCloudSync.allowsPermanentTombstonePurge
        guard allowsPermanentTombstonePurge else { return 0 }
        let cutoff = now.addingTimeInterval(-max(0, tombstoneRetention))
        var removedCount = 0

        // Resolve canonical graph roots one table at a time. The previous
        // implementation retained every row from all twelve tables until the
        // final save, so a large ledger amplified the maintenance memory peak.
        let taskPurge = try purgeCanonicalModels(
            context: context,
            descriptor: FetchDescriptor<TaskNode>(),
            cutoff: cutoff
        )
        let expiredTaskIDs = taskPurge.ids
        removedCount += taskPurge.count

        let recurrenceRulePurge = try purgeCanonicalModels(
            context: context,
            descriptor: FetchDescriptor<TaskRecurrenceRule>(),
            cutoff: cutoff,
            additionallyExpired: {
                expiredTaskIDs.contains($0.templateTaskID)
            }
        )
        let expiredRuleIDs = recurrenceRulePurge.ids
        removedCount += recurrenceRulePurge.count

        let recurrenceOccurrencePurge = try purgeCanonicalModels(
            context: context,
            descriptor: FetchDescriptor<TaskRecurrenceOccurrence>(),
            cutoff: cutoff,
            additionallyExpired: {
                expiredRuleIDs.contains($0.ruleID) ||
                    expiredTaskIDs.contains($0.templateTaskID) ||
                    expiredTaskIDs.contains($0.generatedTaskID)
            }
        )
        removedCount += recurrenceOccurrencePurge.count

        let quantityGoalPurge = try purgeCanonicalModels(
            context: context,
            descriptor: FetchDescriptor<TaskQuantityGoal>(),
            cutoff: cutoff,
            additionallyExpired: {
                expiredTaskIDs.contains($0.taskID)
            }
        )
        let expiredQuantityGoalIDs = quantityGoalPurge.ids
        removedCount += quantityGoalPurge.count

        let quantityEntryPurge = try purgeCanonicalModels(
            context: context,
            descriptor: FetchDescriptor<TaskQuantityEntry>(),
            cutoff: cutoff,
            additionallyExpired: {
                expiredTaskIDs.contains($0.taskID) ||
                    expiredQuantityGoalIDs.contains($0.quantityGoalID)
            }
        )
        removedCount += quantityEntryPurge.count

        let categoryPurge = try purgeCanonicalModels(
            context: context,
            descriptor: FetchDescriptor<TaskCategory>(),
            cutoff: cutoff
        )
        let expiredCategoryIDs = categoryPurge.ids
        removedCount += categoryPurge.count

        let sessionPurge = try purgeCanonicalModels(
            context: context,
            descriptor: FetchDescriptor<TimeSession>(),
            cutoff: cutoff,
            additionallyExpired: { expiredTaskIDs.contains($0.taskID) }
        )
        let expiredSessionIDs = sessionPurge.ids
        removedCount += sessionPurge.count

        let checklistPurge = try purgeCanonicalModels(
            context: context,
            descriptor: FetchDescriptor<ChecklistItem>(),
            cutoff: cutoff,
            additionallyExpired: { expiredTaskIDs.contains($0.taskID) }
        )
        let expiredChecklistItemIDs = checklistPurge.ids
        removedCount += checklistPurge.count

        let inboxPurge = try purgeCanonicalModels(
            context: context,
            descriptor: FetchDescriptor<InboxItem>(),
            cutoff: cutoff
        )
        let expiredInboxItemIDs = inboxPurge.ids
        removedCount += inboxPurge.count

        // Relationship and leaf tables do not participate in root-ID winner
        // discovery. Enumerate them in bounded fetch batches and keep the whole
        // graph mutation in the caller's single atomic save.
        removedCount += try deleteMatching(
            context: context,
            descriptor: FetchDescriptor<TaskCategoryAssignment>(),
            batchSize: fetchBatchSize
        ) {
            isExpired($0.deletedAt, cutoff: cutoff) ||
                expiredTaskIDs.contains($0.taskID) ||
                expiredCategoryIDs.contains($0.categoryID)
        }
        removedCount += try deleteMatching(
            context: context,
            descriptor: FetchDescriptor<TimeSegment>(),
            batchSize: fetchBatchSize
        ) {
            isExpired($0.deletedAt, cutoff: cutoff) ||
                expiredTaskIDs.contains($0.taskID) ||
                expiredSessionIDs.contains($0.sessionID)
        }
        removedCount += try deleteMatching(
            context: context,
            descriptor: FetchDescriptor<PomodoroRun>(),
            batchSize: fetchBatchSize
        ) {
            isExpired($0.deletedAt, cutoff: cutoff) || expiredTaskIDs.contains($0.taskID)
        }
        removedCount += try deleteMatching(
            context: context,
            descriptor: FetchDescriptor<CountdownEvent>(),
            batchSize: fetchBatchSize
        ) {
            isExpired($0.deletedAt, cutoff: cutoff)
        }
        removedCount += try deleteMatching(
            context: context,
            descriptor: FetchDescriptor<SyncedPreference>(),
            batchSize: fetchBatchSize
        ) {
            isExpired($0.deletedAt, cutoff: cutoff)
        }
        removedCount += try deleteMatching(
            context: context,
            descriptor: FetchDescriptor<ChecklistItemVisual>(),
            batchSize: fetchBatchSize
        ) {
            isExpired($0.deletedAt, cutoff: cutoff) ||
                expiredChecklistItemIDs.contains($0.checklistItemID)
        }
        removedCount += try deleteMatching(
            context: context,
            descriptor: FetchDescriptor<InboxSuggestion>(),
            batchSize: fetchBatchSize
        ) {
            isExpired($0.deletedAt, cutoff: cutoff) ||
                expiredInboxItemIDs.contains($0.inboxItemID) ||
                expiredTaskIDs.contains($0.taskID)
        }
        removedCount += try deleteMatching(
            context: context,
            descriptor: FetchDescriptor<InboxCaptureReceipt>(),
            batchSize: fetchBatchSize
        ) {
            isExpired($0.deletedAt, cutoff: cutoff) ||
                expiredInboxItemIDs.contains($0.inboxItemID)
        }

        if removedCount > 0 {
            try context.saveAfterMutationStep()
        }
        return removedCount
    }

    private func purgeCanonicalModels<Model: PersistentModel & PersistentUUIDModel>(
        context: ModelContext,
        descriptor: FetchDescriptor<Model>,
        cutoff: Date,
        additionallyExpired: (Model) -> Bool = { _ in false }
    ) throws -> (ids: Set<UUID>, count: Int) {
        let models = try context.fetch(descriptor)
        let expiredIDs = expiredCanonicalIDs(in: models, cutoff: cutoff)
            .union(models.lazy.filter(additionallyExpired).map(\.id))
        var count = 0
        for model in models where expiredIDs.contains(model.id) {
            context.delete(model)
            count += 1
        }
        return (expiredIDs, count)
    }

    private func deleteMatching<Model: PersistentModel>(
        context: ModelContext,
        descriptor: FetchDescriptor<Model>,
        batchSize: Int,
        where shouldDelete: (Model) -> Bool
    ) throws -> Int {
        var count = 0
        try context.enumerate(
            descriptor,
            batchSize: max(1, batchSize),
            allowEscapingMutations: true
        ) { model in
            guard shouldDelete(model) else { return }
            context.delete(model)
            count += 1
        }
        return count
    }

    private func expiredCanonicalIDs<Model: PersistentUUIDModel>(
        in models: [Model],
        cutoff: Date
    ) -> Set<UUID> {
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
