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
        try tombstone(context.fetch(FetchDescriptor<CountdownEvent>()), now: now, deviceID: deviceID)
        if includesPreferences {
            try tombstone(context.fetch(FetchDescriptor<SyncedPreference>()), now: now, deviceID: deviceID)
        }
        try tombstone(context.fetch(FetchDescriptor<PomodoroRun>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TimeSegment>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TimeSession>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TaskRecurrenceOccurrence>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TaskQuantityEntry>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TaskQuantityGoal>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TaskRecurrenceRule>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<ChecklistItem>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<ChecklistItemVisual>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<InboxSuggestion>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<InboxItem>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<InboxCaptureReceipt>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TaskNode>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TaskCategory>()), now: now, deviceID: deviceID)
        try tombstone(context.fetch(FetchDescriptor<TaskCategoryAssignment>()), now: now, deviceID: deviceID)
        try context.saveAfterMutationStep()
    }

    static func tombstone<Model: SoftDeletablePersistentUUIDModel>(
        _ models: [Model],
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
