import Foundation

enum AutomaticDemoDataMode: String {
    case off
    case seedIfEmpty
    case replaceOnLaunch
}

enum AppDemoDataConfiguration {
    static let infoDictionaryKey = "TimeTrackerAutomaticDemoDataMode"
    static let overrideKey = "TimeTrackerAutomaticDemoDataModeOverride"

    static var currentMode: AutomaticDemoDataMode {
        #if DEBUG
        if CommandLine.arguments.contains("--cloud-smoke-test"),
           CommandLine.arguments.contains("queueDownloadFromDemo"),
           UserDefaults.standard.string(forKey: overrideKey) == nil {
            return .seedIfEmpty
        }
        #endif
        if let override = UserDefaults.standard.string(forKey: overrideKey),
           let mode = AutomaticDemoDataMode(rawValue: override) {
            return mode
        }
        if let configured = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String,
           let mode = AutomaticDemoDataMode(rawValue: configured) {
            return mode
        }
        #if DEBUG
        return .seedIfEmpty
        #else
        return .off
        #endif
    }

    static var usesLocalDemoStore: Bool {
        currentMode != .off
    }

    static func disableLocalDemoStoreForCloudSync() {
        UserDefaults.standard.set(AutomaticDemoDataMode.off.rawValue, forKey: overrideKey)
        SeedData.setAutomaticDemoSeedingDisabled(true)
    }
}
