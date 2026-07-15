import Foundation
import SwiftData

@MainActor
enum SeedData {
    static let automaticDemoSeedingDisabledKey = "TimeTrackerAutomaticDemoSeedingDisabled"

    enum SeedDataError: LocalizedError {
        case demoDataCreationUnavailable

        var errorDescription: String? {
            switch self {
            case .demoDataCreationUnavailable:
                "Demo data can only be created in Debug builds."
            }
        }
    }

    static var isAutomaticDemoSeedingDisabled: Bool {
        UserDefaults.standard.bool(forKey: automaticDemoSeedingDisabledKey)
    }

    static func setAutomaticDemoSeedingDisabled(_ disabled: Bool) {
        UserDefaults.standard.set(disabled, forKey: automaticDemoSeedingDisabledKey)
    }

    static func ensureSeeded(context: ModelContext) throws {
        guard AppDemoDataConfiguration.allowsDemoDataCreation else { return }

        switch AppDemoDataConfiguration.currentMode {
        case .off:
            return
        case .replaceOnLaunch:
            try replaceWithDemoData(context: context)
            return
        case .seedIfEmpty:
            break
        }

        guard !isAutomaticDemoSeedingDisabled else { return }
        guard AppCloudSync.allowsAutomaticDemoSeeding else { return }
        let taskCount = try context.fetch(FetchDescriptor<TaskNode>()).count
        guard taskCount == 0 else { return }
        try context.performAtomicMutation {
            try buildDemoData(context: context)
        }
    }

    static func replaceWithDemoData(context: ModelContext) throws {
        guard AppDemoDataConfiguration.allowsDemoDataCreation else {
            throw SeedDataError.demoDataCreationUnavailable
        }

        try context.performAtomicMutation {
            try clearAllChanges(context: context, includesPreferences: false)
            try buildDemoData(context: context)
        }
        setAutomaticDemoSeedingDisabled(false)
    }

    static func clearAll(context: ModelContext) throws {
        try context.performAtomicMutation {
            try clearAllChanges(context: context, includesPreferences: true)
        }
        setAutomaticDemoSeedingDisabled(true)
    }
}
