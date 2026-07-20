import Foundation
import SwiftData

extension SyncDataSnapshot {
    func restoreTaskRecurrenceRules(
        context: ModelContext,
        now: Date,
        deviceID: String
    ) throws {
        guard let records = taskRecurrenceRules else { return }
        var existing = try context.fetch(FetchDescriptor<TaskRecurrenceRule>())
            .latestByIDMarkingDuplicatesDeleted(
                now: now,
                deviceID: deviceID
            )
        let snapshotIDs = Set(records.map(\.id))
        for model in existing.values where !snapshotIDs.contains(model.id) {
            let mutationDate = PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: model.updatedAt
            )
            model.deletedAt = mutationDate
            model.updatedAt = mutationDate
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }

        for record in records {
            let existingModel = existing[record.id]
            let model = existingModel ?? TaskRecurrenceRule(
                templateTaskID: record.templateTaskID,
                startDayKey: record.startDayKey,
                timeZoneIdentifier: record.timeZoneIdentifier,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            let mutationDate = PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: [record.updatedAt] +
                    [existingModel?.updatedAt].compactMap { $0 }
            )
            model.id = record.id
            model.templateTaskID = record.templateTaskID
            model.cadenceRaw = record.cadenceRaw
            model.startDayKey = record.startDayKey
            model.timeZoneIdentifier = record.timeZoneIdentifier
            model.isEnabled = record.isEnabled
            model.createdAt = record.createdAt
            model.updatedAt = mutationDate
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    func restoreTaskRecurrenceOccurrences(
        context: ModelContext,
        now: Date,
        deviceID: String
    ) throws {
        guard let records = taskRecurrenceOccurrences else { return }
        var existing = try context
            .fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
            .latestByIDMarkingDuplicatesDeleted(
                now: now,
                deviceID: deviceID
            )
        let snapshotIDs = Set(records.map(\.id))
        for model in existing.values where !snapshotIDs.contains(model.id) {
            let mutationDate = PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: model.updatedAt
            )
            model.deletedAt = mutationDate
            model.updatedAt = mutationDate
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }

        for record in records {
            let existingModel = existing[record.id]
            let model = existingModel ?? TaskRecurrenceOccurrence(
                ruleID: record.ruleID,
                templateTaskID: record.templateTaskID,
                occurrenceDayKey: record.occurrenceDayKey,
                timeZoneIdentifier: record.timeZoneIdentifier,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            let mutationDate = PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: [record.updatedAt] +
                    [existingModel?.updatedAt].compactMap { $0 }
            )
            model.id = record.id
            model.ruleID = record.ruleID
            model.templateTaskID = record.templateTaskID
            model.occurrenceDayKey = record.occurrenceDayKey
            model.timeZoneIdentifier = record.timeZoneIdentifier
            model.generatedTaskID = record.generatedTaskID
            model.createdAt = record.createdAt
            model.updatedAt = mutationDate
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    func restoreTaskQuantityGoals(
        context: ModelContext,
        now: Date,
        deviceID: String
    ) throws {
        guard let records = taskQuantityGoals else { return }
        var existing = try context.fetch(FetchDescriptor<TaskQuantityGoal>())
            .latestByIDMarkingDuplicatesDeleted(
                now: now,
                deviceID: deviceID
            )
        let snapshotIDs = Set(records.map(\.id))
        for model in existing.values where !snapshotIDs.contains(model.id) {
            let mutationDate = PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: model.updatedAt
            )
            model.deletedAt = mutationDate
            model.updatedAt = mutationDate
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }

        for record in records {
            let existingModel = existing[record.id]
            let model = existingModel ?? TaskQuantityGoal(
                taskID: record.taskID,
                targetAmount: record.targetAmount,
                unitLabel: record.unitLabel,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            let mutationDate = PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: [record.updatedAt] +
                    [existingModel?.updatedAt].compactMap { $0 }
            )
            model.id = record.id
            model.taskID = record.taskID
            model.targetAmount = record.targetAmount
            model.unitLabel = record.unitLabel
            model.createdAt = record.createdAt
            model.updatedAt = mutationDate
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    func restoreTaskQuantityEntries(
        context: ModelContext,
        now: Date,
        deviceID: String
    ) throws {
        guard let records = taskQuantityEntries else { return }
        var existing = try context.fetch(FetchDescriptor<TaskQuantityEntry>())
            .latestByIDMarkingDuplicatesDeleted(
                now: now,
                deviceID: deviceID
            )
        let snapshotIDs = Set(records.map(\.id))
        for model in existing.values where !snapshotIDs.contains(model.id) {
            let mutationDate = PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: model.updatedAt
            )
            model.deletedAt = mutationDate
            model.updatedAt = mutationDate
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }

        for record in records {
            let existingModel = existing[record.id]
            let model = existingModel ?? TaskQuantityEntry(
                id: record.id,
                taskID: record.taskID,
                amount: record.amount,
                recordedAt: record.recordedAt,
                createdAt: record.createdAt,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            let mutationDate = PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: [record.updatedAt] +
                    [existingModel?.updatedAt].compactMap { $0 }
            )
            model.id = record.id
            model.taskID = record.taskID
            model.quantityGoalID = record.quantityGoalID
            model.amount = record.amount
            model.recordedAt = record.recordedAt
            model.createdAt = record.createdAt
            model.updatedAt = mutationDate
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }
}
