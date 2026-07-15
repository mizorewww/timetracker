import Foundation

enum AutomaticDemoDataMode: String {
    case off
    case seedIfEmpty
    case replaceOnLaunch
}

enum AppDemoDataConfiguration {
    static let infoDictionaryKey = "TimeTrackerAutomaticDemoDataMode"
    static let overrideKey = "TimeTrackerAutomaticDemoDataModeOverride"

    static var allowsDemoDataCreation: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static var currentMode: AutomaticDemoDataMode {
        guard allowsDemoDataCreation else { return .off }

        if CommandLine.arguments.contains("--cloud-smoke-test"),
           CommandLine.arguments.contains("queueDownloadFromDemo"),
           UserDefaults.standard.string(forKey: overrideKey) == nil {
            return .seedIfEmpty
        }
        if let override = UserDefaults.standard.string(forKey: overrideKey),
           let mode = AutomaticDemoDataMode(rawValue: override) {
            return mode
        }
        if let configured = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String,
           let mode = AutomaticDemoDataMode(rawValue: configured) {
            return mode
        }
        return .off
    }

    static var usesLocalDemoStore: Bool {
        currentMode != .off
    }

    static var persistentStoreURL: URL {
        AppCloudSync.persistentStoreURL
            .deletingLastPathComponent()
            .appendingPathComponent("TimeTracker-Demo.store")
    }

    static func disableLocalDemoStoreForCloudSync() {
        UserDefaults.standard.set(AutomaticDemoDataMode.off.rawValue, forKey: overrideKey)
        SeedData.setAutomaticDemoSeedingDisabled(true)
    }
}
