import Foundation
import SwiftData

@MainActor
struct PreferenceCommandHandler {
    func set(key: AppPreferenceKey, valueJSON: String, context: ModelContext, now: Date = Date()) throws {
        try set(values: [(key, valueJSON)], context: context, now: now)
    }

    func set(
        values: [(AppPreferenceKey, String)],
        context: ModelContext,
        now: Date = Date()
    ) throws {
        for (key, valueJSON) in values {
            try apply(key: key, valueJSON: valueJSON, context: context, now: now)
        }
        try context.saveAfterMutationStep()
    }

    private func apply(
        key: AppPreferenceKey,
        valueJSON: String,
        context: ModelContext,
        now: Date
    ) throws {
        let rawKey = key.rawValue
        let descriptor = FetchDescriptor<SyncedPreference>(
            predicate: #Predicate { $0.key == rawKey }
        )
        let existing = try context.fetch(descriptor).deduplicatedByID()
        let latest = SyncedPreferenceService.latestByKey(existing)[rawKey]
        let target: SyncedPreference
        if let latest, latest.deletedAt == nil {
            target = latest
        } else {
            target = SyncedPreference(
                key: key.rawValue,
                valueJSON: valueJSON,
                deviceID: DeviceIdentity.current
            )
            context.insert(target)
        }
        target.valueJSON = valueJSON
        target.updatedAt = now
        target.deviceID = DeviceIdentity.current
        target.clientMutationID = UUID()
        for duplicate in existing where duplicate !== target && duplicate.deletedAt == nil {
            duplicate.deletedAt = now
            duplicate.updatedAt = now
            duplicate.clientMutationID = UUID()
        }
    }
}
