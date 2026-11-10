#if DEBUG
import Foundation

enum AutomaticDemoDataMode: String {
    case off
    case seedIfEmpty
    case replaceOnLaunch
}

/// Debug-only demo data, selected by one launch argument:
/// `-TimeTrackerAutomaticDemoDataModeOverride <mode>`.
enum AppDemoDataConfiguration {
    static let overrideKey = "TimeTrackerAutomaticDemoDataModeOverride"

    static let currentMode: AutomaticDemoDataMode =
        commandLineMode(arguments: CommandLine.arguments) ?? .off

    /// Demo writes are confined to the isolated demo store: with the mode
    /// `off`, a Debug build opens the production CloudKit store, and seeding
    /// there would tombstone the user's real data and sync it to iCloud.
    static var allowsDemoDataMutation: Bool {
        usesLocalDemoStore
    }

    static func commandLineMode(
        arguments: [String]
    ) -> AutomaticDemoDataMode? {
        let key = "-\(overrideKey)"
        for index in arguments.indices.reversed() {
            let argument = arguments[index]
            if argument == key,
               arguments.indices.contains(index + 1)
            {
                return AutomaticDemoDataMode(
                    rawValue: arguments[index + 1]
                )
            }
            let prefix = "\(key)="
            if argument.hasPrefix(prefix) {
                return AutomaticDemoDataMode(
                    rawValue: String(argument.dropFirst(prefix.count))
                )
            }
        }
        return nil
    }

    /// Days of heavy-user history the demo data adds, from
    /// `-TimeTrackerDemoHistoryDays <days>`; none when absent.
    static var largeHistoryDays: Int? {
        let days = UserDefaults.standard.integer(forKey: "TimeTrackerDemoHistoryDays")
        return days > 0 ? days : nil
    }

    static var usesLocalDemoStore: Bool {
        currentMode != .off
    }

    static var persistentStoreURL: URL {
        AppCloudSync.persistentStoreURL
            .deletingLastPathComponent()
            .appendingPathComponent("TimeTracker-Demo.store")
    }
}
#endif
