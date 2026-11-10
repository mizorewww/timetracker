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
        let preparedValues = try values.map { key, valueJSON in
            try (
                key,
                PreferenceJSON.canonicalValueJSON(for: key, from: valueJSON)
            )
        }

        try context.performAtomicMutation {
            for (key, valueJSON) in preparedValues {
                try apply(key: key, valueJSON: valueJSON, context: context, now: now)
            }
        }
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
        target.markMutated(at: now, deviceID: DeviceIdentity.current)
        // A tombstone wins an exact timestamp tie for a logical key. Keep every
        // superseded physical sibling strictly older than the canonical write,
        // including tombstones that already existed before this mutation.
        let supersededAt = now.addingTimeInterval(-1)
        for duplicate in existing where duplicate !== target {
            duplicate.deletedAt = supersededAt
            duplicate.markMutated(at: supersededAt, deviceID: DeviceIdentity.current)
        }
    }
}

/// Serializes synced preference writes with every other store writer. Settings
/// scenes must not resolve logical preference rows from a stale ModelContext,
/// because timer admission and other commands read those rows under the shared
/// store lock.
@MainActor
struct StoreScopedPreferenceCommandCoordinator {
    let session: StoreMutationSession

    func set(key: AppPreferenceKey, valueJSON: String) throws {
        try set(values: [(key, valueJSON)])
    }

    func set(values: [(AppPreferenceKey, String)]) throws {
        try set(values: values, applyingLocalMutation: {})
    }

    /// Couples an infrequent, device-local setting mutation with the synced
    /// preference commit. The caller must keep this action synchronous and
    /// side-effect free outside the local device (for example, a Keychain
    /// write); network, UI, and projection work remain outside the lock.
    func set(
        values: [(AppPreferenceKey, String)],
        applyingLocalMutation: () throws -> Void
    ) throws {
        try withFreshMutationContext { context in
            try applyingLocalMutation()
            try PreferenceCommandHandler().set(values: values, context: context)
        }
    }

    private func withFreshMutationContext(
        _ operation: (ModelContext) throws -> Void
    ) throws {
        try session.withFreshMutationContext(operation)
    }
}
