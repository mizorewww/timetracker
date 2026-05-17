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
        guard try !hasUserVisibleContent(context: context) else { return }
        try buildDemoData(context: context)
    }

    private static func hasUserVisibleContent(context: ModelContext) throws -> Bool {
        try containsAny(TaskNode.self, context: context) ||
            containsAny(TaskCategory.self, context: context) ||
            containsAny(TaskCategoryAssignment.self, context: context) ||
            containsAny(ChecklistItem.self, context: context) ||
            containsAny(ChecklistItemVisual.self, context: context) ||
            containsAny(InboxItem.self, context: context) ||
            containsAny(InboxSuggestion.self, context: context) ||
            containsAny(CountdownEvent.self, context: context) ||
            containsAny(TimeSession.self, context: context) ||
            containsAny(TimeSegment.self, context: context) ||
            containsAny(PomodoroRun.self, context: context)
    }

    private static func containsAny<Model: PersistentModel>(
        _ model: Model.Type,
        context: ModelContext
    ) throws -> Bool {
        var descriptor = FetchDescriptor<Model>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    static func replaceWithDemoData(context: ModelContext) throws {
        guard AppDemoDataConfiguration.allowsDemoDataCreation else {
            throw SeedDataError.demoDataCreationUnavailable
        }

        try clearAll(context: context, disablesAutomaticDemoSeeding: false, includesPreferences: false)
        try buildDemoData(context: context)
        setAutomaticDemoSeedingDisabled(false)
    }

    static func clearAll(context: ModelContext) throws {
        try clearAll(context: context, disablesAutomaticDemoSeeding: true, includesPreferences: true)
    }
}
