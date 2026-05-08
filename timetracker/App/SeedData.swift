import Foundation
import SwiftData

@MainActor
enum SeedData {
    static let automaticDemoSeedingDisabledKey = "TimeTrackerAutomaticDemoSeedingDisabled"

    static var isAutomaticDemoSeedingDisabled: Bool {
        UserDefaults.standard.bool(forKey: automaticDemoSeedingDisabledKey)
    }

    static func setAutomaticDemoSeedingDisabled(_ disabled: Bool) {
        UserDefaults.standard.set(disabled, forKey: automaticDemoSeedingDisabledKey)
    }

    static func ensureSeeded(context: ModelContext) throws {
        guard !isAutomaticDemoSeedingDisabled else { return }
        guard AppCloudSync.allowsAutomaticDemoSeeding else { return }
        let taskCount = try context.fetch(FetchDescriptor<TaskNode>()).count
        guard taskCount == 0 else { return }
        try buildDemoData(context: context)
    }

    static func replaceWithDemoData(context: ModelContext) throws {
        try clearAll(context: context, disablesAutomaticDemoSeeding: false)
        try buildDemoData(context: context)
        setAutomaticDemoSeedingDisabled(false)
    }

    static func clearAll(context: ModelContext) throws {
        try clearAll(context: context, disablesAutomaticDemoSeeding: true)
    }
}
