import Foundation
import SwiftData

@MainActor
enum SeedData {
    /// Resets every user row (a user-confirmed Settings action).
    static func clearAll(context: ModelContext) throws {
        try context.performAtomicMutation {
            try clearAllChanges(context: context, includesPreferences: true)
        }
        #if DEBUG
        setAutomaticDemoSeedingDisabled(true)
        #endif
    }

    static func clearAllChanges(
        context: ModelContext,
        includesPreferences: Bool
    ) throws {
        let now = Date()
        let deviceID = DeviceIdentity.current
        // CloudKit user-fact models retain a tombstone so offline devices receive
        // the reset instead of resurrecting old rows.
        for model in TimeTrackerModelRegistry.currentModels
            where includesPreferences || model != SyncedPreference.self
        {
            try tombstoneAll(model, context: context, now: now, deviceID: deviceID)
        }
        try context.saveAfterMutationStep()
    }

    private static func tombstoneAll<Model: PersistentModel>(
        _: Model.Type,
        context: ModelContext,
        now: Date,
        deviceID: String
    ) throws {
        let rows = try context.fetch(FetchDescriptor<Model>())
            .compactMap { $0 as? any SoftDeletablePersistentUUIDModel }
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
            try clearAllChanges(
                context: context,
                includesPreferences: false
            )
            try buildDemoData(context: context)
        }
        setAutomaticDemoSeedingDisabled(false)
    }
}
#endif
