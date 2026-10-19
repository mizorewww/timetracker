import Foundation
import SwiftData

@MainActor
enum SeedData {
    /// Tombstones every live user row; the caller's atomic mutation commits.
    /// CloudKit user-fact models retain a tombstone so offline devices receive
    /// the reset instead of resurrecting old rows. Rows already tombstoned stay
    /// as they are so the reset does not re-export the deletion history.
    static func clearAll(
        context: ModelContext,
        includesPreferences: Bool
    ) throws {
        let now = Date()
        let deviceID = DeviceIdentity.current
        for model in TimeTrackerModelRegistry.currentModels
            where includesPreferences || model != SyncedPreference.self
        {
            try tombstoneLiveRows(of: model, context: context, now: now, deviceID: deviceID)
        }
    }

    private static func tombstoneLiveRows<Model: PersistentModel>(
        of _: Model.Type,
        context: ModelContext,
        now: Date,
        deviceID: String
    ) throws {
        let rows = try context.fetch(FetchDescriptor<Model>())
            .compactMap { $0 as? any SoftDeletablePersistentUUIDModel }
            .filter { $0.deletedAt == nil }
        tombstone(rows, now: now, deviceID: deviceID)
    }

    static func tombstone(
        _ models: [any SoftDeletablePersistentUUIDModel],
        now: Date,
        deviceID: String
    ) {
        for model in models {
            let mutationDate = PersistentLWWMutationDate.strictlyDominating(
                preferred: now,
                observed: model.updatedAt
            )
            model.deletedAt = mutationDate
            model.updatedAt = mutationDate
            model.deviceID = deviceID
            (model as? ClientMutationTrackedModel)?.clientMutationID = UUID()
        }
    }
}

#if DEBUG
extension SeedData {
    static let automaticDemoSeedingDisabledKey = "TimeTrackerAutomaticDemoSeedingDisabled"

    enum SeedDataError: LocalizedError {
        case demoDataCreationUnavailable

        var errorDescription: String? {
            switch self {
            case .demoDataCreationUnavailable:
                "Demo data can only be created in the isolated demo store."
            }
        }
    }

    static var isAutomaticDemoSeedingDisabled: Bool {
        AppDefaults.shared.bool(forKey: automaticDemoSeedingDisabledKey)
    }

    static func setAutomaticDemoSeedingDisabled(_ disabled: Bool) {
        AppDefaults.shared.set(disabled, forKey: automaticDemoSeedingDisabledKey)
    }

    static func ensureSeeded(context: ModelContext) throws {
        guard AppDemoDataConfiguration.allowsDemoDataMutation else { return }

        switch AppDemoDataConfiguration.currentMode {
        case .off:
            return
        case .replaceOnLaunch:
            try replaceWithDemoData(context: context)
            return
        case .seedIfEmpty:
            break
        }

        guard !isAutomaticDemoSeedingDisabled, AppCloudSync.allowsAutomaticDemoSeeding else { return }
        let taskCount = try context.fetch(FetchDescriptor<TaskNode>()).count
        guard taskCount == 0 else { return }
        try context.performAtomicMutation {
            try buildDemoData(context: context)
        }
    }

    static func replaceWithDemoData(context: ModelContext) throws {
        // This call wipes every existing row before seeding, so it must never
        // run against the production store.
        guard AppDemoDataConfiguration.allowsDemoDataMutation else {
            throw SeedDataError.demoDataCreationUnavailable
        }

        try context.performAtomicMutation {
            try clearAll(context: context, includesPreferences: false)
            try buildDemoData(context: context)
        }
        setAutomaticDemoSeedingDisabled(false)
    }
}
#endif
