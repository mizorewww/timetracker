import Foundation
import SwiftData

enum AppPreferenceKey: String, CaseIterable {
    case preferredColorScheme = "PreferredColorScheme"
    case pomodoroDefaultMode = "PomodoroDefaultMode"
    case defaultFocusMinutes = "DefaultFocusMinutes"
    case defaultBreakMinutes = "DefaultBreakMinutes"
    case defaultPomodoroRounds = "DefaultPomodoroRounds"
    case allowParallelTimers = "AllowParallelTimers"
    case showGrossAndWallTogether = "ShowGrossAndWallTogether"
    case cloudSyncEnabled = "TimeTrackerCloudSyncEnabled"
    case quickStartTaskIDs = "QuickStartTaskIDs"
}

struct AppPreferences: Equatable {
    var preferredColorScheme = "system"
    var pomodoroDefaultMode = PomodoroPreset.classic.rawValue
    var defaultFocusMinutes = 25
    var defaultBreakMinutes = 5
    var defaultPomodoroRounds = 1
    var allowParallelTimers = true
    var showGrossAndWallTogether = true
    var cloudSyncEnabled = true
    var quickStartTaskIDs: [UUID] = []

    static let defaults = AppPreferences()

    init() {}

    init(syncedPreferences: [SyncedPreference]) {
        self = .defaults
        for preference in SyncedPreferenceService.latestByKey(syncedPreferences).values {
            apply(preference)
        }
    }

    mutating func apply(_ preference: SyncedPreference) {
        guard let key = AppPreferenceKey(rawValue: preference.key), preference.deletedAt == nil else { return }
        switch key {
        case .preferredColorScheme:
            preferredColorScheme = PreferenceJSON.decode(String.self, from: preference.valueJSON, default: preferredColorScheme)
        case .pomodoroDefaultMode:
            pomodoroDefaultMode = PreferenceJSON.decode(String.self, from: preference.valueJSON, default: pomodoroDefaultMode)
        case .defaultFocusMinutes:
            defaultFocusMinutes = PreferenceJSON.decode(Int.self, from: preference.valueJSON, default: defaultFocusMinutes).clamped(to: 1...480)
        case .defaultBreakMinutes:
            defaultBreakMinutes = PreferenceJSON.decode(Int.self, from: preference.valueJSON, default: defaultBreakMinutes).clamped(to: 1...480)
        case .defaultPomodoroRounds:
            defaultPomodoroRounds = PreferenceJSON.decode(Int.self, from: preference.valueJSON, default: defaultPomodoroRounds).clamped(to: 1...24)
        case .allowParallelTimers:
            allowParallelTimers = PreferenceJSON.decode(Bool.self, from: preference.valueJSON, default: allowParallelTimers)
        case .showGrossAndWallTogether:
            showGrossAndWallTogether = PreferenceJSON.decode(Bool.self, from: preference.valueJSON, default: showGrossAndWallTogether)
        case .cloudSyncEnabled:
            cloudSyncEnabled = PreferenceJSON.decode(Bool.self, from: preference.valueJSON, default: cloudSyncEnabled)
        case .quickStartTaskIDs:
            let strings = PreferenceJSON.decode([String].self, from: preference.valueJSON, default: [])
            quickStartTaskIDs = strings.compactMap(UUID.init(uuidString:))
        }
    }

    func valueJSON(for key: AppPreferenceKey) -> String {
        switch key {
        case .preferredColorScheme:
            return PreferenceJSON.encode(preferredColorScheme)
        case .pomodoroDefaultMode:
            return PreferenceJSON.encode(pomodoroDefaultMode)
        case .defaultFocusMinutes:
            return PreferenceJSON.encode(defaultFocusMinutes)
        case .defaultBreakMinutes:
            return PreferenceJSON.encode(defaultBreakMinutes)
        case .defaultPomodoroRounds:
            return PreferenceJSON.encode(defaultPomodoroRounds)
        case .allowParallelTimers:
            return PreferenceJSON.encode(allowParallelTimers)
        case .showGrossAndWallTogether:
            return PreferenceJSON.encode(showGrossAndWallTogether)
        case .cloudSyncEnabled:
            return PreferenceJSON.encode(cloudSyncEnabled)
        case .quickStartTaskIDs:
            return PreferenceJSON.encode(quickStartTaskIDs.map(\.uuidString))
        }
    }
}

enum PreferenceJSON {
    static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return string
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String, default defaultValue: T) -> T {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(type, from: data) else {
            return defaultValue
        }
        return value
    }
}

enum SyncedPreferenceService {
    static let migrationKey = "SyncedPreferencesMigratedToSwiftDataV1"

    static func latestByKey(_ preferences: [SyncedPreference]) -> [String: SyncedPreference] {
        preferences
            .filter { $0.deletedAt == nil }
            .reduce(into: [String: SyncedPreference]()) { result, preference in
                guard let existing = result[preference.key] else {
                    result[preference.key] = preference
                    return
                }
                if preference.updatedAt >= existing.updatedAt {
                    result[preference.key] = preference
                }
            }
    }

    @MainActor
    static func migrateLegacyPreferencesIfNeeded(context: ModelContext, deviceID: String = DeviceIdentity.current) throws {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        let existing = try context.fetch(FetchDescriptor<SyncedPreference>())
        let existingKeys = Set(existing.filter { $0.deletedAt == nil }.map(\.key))
        let defaults = AppPreferences.defaults

        for key in AppPreferenceKey.allCases where !existingKeys.contains(key.rawValue) {
            let valueJSON = legacyValueJSON(for: key, defaultPreferences: defaults)
            context.insert(SyncedPreference(key: key.rawValue, valueJSON: valueJSON, deviceID: deviceID))
        }

        try context.save()
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    static func syncLocalMirrors(_ preferences: AppPreferences) {
        UserDefaults.standard.set(preferences.cloudSyncEnabled, forKey: AppCloudSync.enabledKey)
    }

    private static func legacyValueJSON(for key: AppPreferenceKey, defaultPreferences: AppPreferences) -> String {
        let defaults = UserDefaults.standard
        switch key {
        case .preferredColorScheme:
            return PreferenceJSON.encode(defaults.string(forKey: key.rawValue) ?? defaultPreferences.preferredColorScheme)
        case .pomodoroDefaultMode:
            return PreferenceJSON.encode(defaults.string(forKey: key.rawValue) ?? defaultPreferences.pomodoroDefaultMode)
        case .defaultFocusMinutes:
            return PreferenceJSON.encode(defaults.object(forKey: key.rawValue) as? Int ?? defaultPreferences.defaultFocusMinutes)
        case .defaultBreakMinutes:
            return PreferenceJSON.encode(defaults.object(forKey: key.rawValue) as? Int ?? defaultPreferences.defaultBreakMinutes)
        case .defaultPomodoroRounds:
            return PreferenceJSON.encode(defaults.object(forKey: key.rawValue) as? Int ?? defaultPreferences.defaultPomodoroRounds)
        case .allowParallelTimers:
            return PreferenceJSON.encode(defaults.object(forKey: key.rawValue) as? Bool ?? defaultPreferences.allowParallelTimers)
        case .showGrossAndWallTogether:
            return PreferenceJSON.encode(defaults.object(forKey: key.rawValue) as? Bool ?? defaultPreferences.showGrossAndWallTogether)
        case .cloudSyncEnabled:
            return PreferenceJSON.encode(defaults.object(forKey: key.rawValue) as? Bool ?? defaultPreferences.cloudSyncEnabled)
        case .quickStartTaskIDs:
            let ids = defaults.string(forKey: key.rawValue)?
                .split(separator: ",")
                .map(String.init) ?? []
            return PreferenceJSON.encode(ids)
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
