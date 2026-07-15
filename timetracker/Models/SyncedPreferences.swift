import Foundation
import SwiftData

enum AppPreferenceKey: String, CaseIterable {
    case preferredColorScheme = "PreferredColorScheme"
    case pomodoroDefaultMode = "PomodoroDefaultMode"
    case defaultFocusMinutes = "DefaultFocusMinutes"
    case defaultBreakMinutes = "DefaultBreakMinutes"
    case defaultPomodoroRounds = "DefaultPomodoroRounds"
    case pomodoroPlans = "PomodoroPlans"
    case allowParallelTimers = "AllowParallelTimers"
    case showGrossAndWallTogether = "ShowGrossAndWallTogether"
    case quickStartTaskIDs = "QuickStartTaskIDs"
    case llmEndpoint = "LLMEndpoint"
    case llmSelectedModel = "LLMSelectedModel"
    case llmAvailableModelIDs = "LLMAvailableModelIDs"
}

enum AppLocalPreferenceKey {
    static let llmAutomaticSuggestionsEnabled = "LLMAutomaticSuggestionsEnabled"
}

struct AppPreferences: Equatable {
    var preferredColorScheme = "system"
    var pomodoroDefaultMode = PomodoroPreset.classic.rawValue
    var defaultFocusMinutes = 25
    var defaultBreakMinutes = 5
    var defaultPomodoroRounds = 1
    var pomodoroPlans = PomodoroPlan.defaultPlans
    var allowParallelTimers = true
    var showGrossAndWallTogether = true
    var cloudSyncEnabled = AppCloudSync.isEnabled
    var quickStartTaskIDs: [UUID] = []
    var llmEndpoint = "https://api.openai.com/v1"
    var llmAPIKey = ""
    var llmSelectedModel = ""
    var llmAvailableModelIDs: [String] = []
    var llmAutomaticSuggestionsEnabled = false

    static var defaults: AppPreferences { AppPreferences() }

    init() {}

    init(syncedPreferences: [SyncedPreference]) {
        self = .defaults
        for preference in SyncedPreferenceService.latestByKey(syncedPreferences).values {
            apply(preference)
        }
        normalizeRelatedValues()
    }

    mutating func apply(_ preference: SyncedPreference) {
        guard let key = AppPreferenceKey(rawValue: preference.key), preference.deletedAt == nil else { return }
        switch key {
        case .preferredColorScheme:
            preferredColorScheme = AppPreferenceValueSanitizer.preferredColorScheme(
                PreferenceJSON.decode(String.self, from: preference.valueJSON, default: preferredColorScheme)
            )
        case .pomodoroDefaultMode:
            pomodoroDefaultMode = AppPreferenceValueSanitizer.pomodoroMode(
                PreferenceJSON.decode(String.self, from: preference.valueJSON, default: pomodoroDefaultMode)
            )
        case .defaultFocusMinutes:
            defaultFocusMinutes = PreferenceJSON.decode(Int.self, from: preference.valueJSON, default: defaultFocusMinutes).clamped(to: 1...480)
        case .defaultBreakMinutes:
            defaultBreakMinutes = PreferenceJSON.decode(Int.self, from: preference.valueJSON, default: defaultBreakMinutes).clamped(to: 1...480)
        case .defaultPomodoroRounds:
            defaultPomodoroRounds = PreferenceJSON.decode(Int.self, from: preference.valueJSON, default: defaultPomodoroRounds).clamped(to: 1...24)
        case .pomodoroPlans:
            pomodoroPlans = AppPreferenceValueSanitizer.pomodoroPlans(
                PreferenceJSON.decode([PomodoroPlan].self, from: preference.valueJSON, default: pomodoroPlans)
            )
        case .allowParallelTimers:
            allowParallelTimers = PreferenceJSON.decode(Bool.self, from: preference.valueJSON, default: allowParallelTimers)
        case .showGrossAndWallTogether:
            showGrossAndWallTogether = PreferenceJSON.decode(Bool.self, from: preference.valueJSON, default: showGrossAndWallTogether)
        case .quickStartTaskIDs:
            let strings = PreferenceJSON.decode([String].self, from: preference.valueJSON, default: [])
            quickStartTaskIDs = AppPreferenceValueSanitizer.quickStartTaskIDs(
                strings.compactMap(UUID.init(uuidString:))
            )
        case .llmEndpoint:
            llmEndpoint = AppPreferenceValueSanitizer.llmEndpoint(
                PreferenceJSON.decode(String.self, from: preference.valueJSON, default: llmEndpoint)
            )
        case .llmSelectedModel:
            llmSelectedModel = AppPreferenceValueSanitizer.llmModelID(
                PreferenceJSON.decode(String.self, from: preference.valueJSON, default: llmSelectedModel)
            )
        case .llmAvailableModelIDs:
            llmAvailableModelIDs = AppPreferenceValueSanitizer.llmModelIDs(
                PreferenceJSON.decode([String].self, from: preference.valueJSON, default: [])
            )
        }
    }

    private mutating func normalizeRelatedValues() {
        if !llmSelectedModel.isEmpty, !llmAvailableModelIDs.contains(llmSelectedModel) {
            llmSelectedModel = ""
        }
    }

    func valueJSON(for key: AppPreferenceKey) -> String {
        switch key {
        case .preferredColorScheme:
            return PreferenceJSON.encode(AppPreferenceValueSanitizer.preferredColorScheme(preferredColorScheme))
        case .pomodoroDefaultMode:
            return PreferenceJSON.encode(AppPreferenceValueSanitizer.pomodoroMode(pomodoroDefaultMode))
        case .defaultFocusMinutes:
            return PreferenceJSON.encode(defaultFocusMinutes)
        case .defaultBreakMinutes:
            return PreferenceJSON.encode(defaultBreakMinutes)
        case .defaultPomodoroRounds:
            return PreferenceJSON.encode(defaultPomodoroRounds)
        case .pomodoroPlans:
            return PreferenceJSON.encode(AppPreferenceValueSanitizer.pomodoroPlans(pomodoroPlans))
        case .allowParallelTimers:
            return PreferenceJSON.encode(allowParallelTimers)
        case .showGrossAndWallTogether:
            return PreferenceJSON.encode(showGrossAndWallTogether)
        case .quickStartTaskIDs:
            return PreferenceJSON.encode(
                AppPreferenceValueSanitizer.quickStartTaskIDs(quickStartTaskIDs).map(\.uuidString)
            )
        case .llmEndpoint:
            return PreferenceJSON.encode(AppPreferenceValueSanitizer.llmEndpoint(llmEndpoint))
        case .llmSelectedModel:
            return PreferenceJSON.encode(AppPreferenceValueSanitizer.llmModelID(llmSelectedModel))
        case .llmAvailableModelIDs:
            return PreferenceJSON.encode(AppPreferenceValueSanitizer.llmModelIDs(llmAvailableModelIDs))
        }
    }
}

enum PreferenceJSON {
    static let maximumPayloadByteCount = 256 * 1_024

    static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              data.count <= maximumPayloadByteCount,
              let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return string
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String, default defaultValue: T) -> T {
        guard json.utf8.count <= maximumPayloadByteCount,
              let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(type, from: data) else {
            return defaultValue
        }
        return value
    }
}

enum SyncedPreferenceService {
    static let migrationKey = "SyncedPreferencesMigratedToSwiftDataV1"
    static let legacyLLMAPIKey = "LLMAPIKey"
    static let legacyCloudSyncEnabledKey = AppCloudSync.enabledKey

    static func isSensitiveKey(_ key: String) -> Bool {
        key == legacyLLMAPIKey
    }

    static func isDeviceLocalKey(_ key: String) -> Bool {
        key == legacyCloudSyncEnabledKey
    }

    static func shouldSyncKey(_ key: String) -> Bool {
        !isSensitiveKey(key) && !isDeviceLocalKey(key)
    }

    static func latestByKey(_ preferences: [SyncedPreference]) -> [String: SyncedPreference] {
        preferences
            .reduce(into: [String: SyncedPreference]()) { result, preference in
                guard let existing = result[preference.key] else {
                    result[preference.key] = preference
                    return
                }
                if preference.updatedAt > existing.updatedAt ||
                    (preference.updatedAt == existing.updatedAt &&
                        preference.deletedAt != nil && existing.deletedAt == nil) ||
                    (preference.updatedAt == existing.updatedAt &&
                        (preference.deletedAt == nil) == (existing.deletedAt == nil) &&
                        (preference.createdAt > existing.createdAt ||
                            (preference.createdAt == existing.createdAt &&
                                preference.id.uuidString > existing.id.uuidString))) {
                    result[preference.key] = preference
                }
            }
    }

    @MainActor
    static func migrateLegacyPreferencesIfNeeded(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        deviceID: String = DeviceIdentity.current
    ) throws {
        guard !defaults.bool(forKey: migrationKey) else { return }
        let existing = try context.fetch(FetchDescriptor<SyncedPreference>())
        // A logical-key tombstone is still an existing migrated value. Ignoring it
        // would let stale UserDefaults recreate a preference that another device
        // already deleted.
        let existingKeys = Set(latestByKey(existing.deduplicatedByID()).keys)

        for key in AppPreferenceKey.allCases
        where shouldSyncKey(key.rawValue) && !existingKeys.contains(key.rawValue) {
            if let valueJSON = legacyValueJSON(for: key, defaults: defaults) {
                context.insert(SyncedPreference(key: key.rawValue, valueJSON: valueJSON, deviceID: deviceID))
            }
        }

        try context.save()
        defaults.set(true, forKey: migrationKey)
    }

    @MainActor
    static func migrateSensitivePreferences(
        context: ModelContext,
        credentialStore: any LLMCredentialStoring,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        let sensitiveKey = legacyLLMAPIKey
        let descriptor = FetchDescriptor<SyncedPreference>(
            predicate: #Predicate { $0.key == sensitiveKey },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let storedPreferences = try context.fetch(descriptor)
        let syncedCandidate = latestByKey(storedPreferences.deduplicatedByID())[sensitiveKey]
            .flatMap { preference -> String? in
                guard preference.deletedAt == nil else { return nil }
                let value = PreferenceJSON.decode(String.self, from: preference.valueJSON, default: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        let defaults = UserDefaults.standard
        let legacyLocalCandidate = defaults.string(forKey: legacyLLMAPIKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if try credentialStore.readAPIKey() == nil {
            if let candidate = syncedCandidate ?? legacyLocalCandidate, !candidate.isEmpty {
                try credentialStore.writeAPIKey(candidate)
            }
        }

        var changed = false
        let redactedValue = PreferenceJSON.encode("")
        for preference in storedPreferences {
            var recordChanged = false
            if preference.valueJSON != redactedValue {
                preference.valueJSON = redactedValue
                recordChanged = true
            }
            if preference.deletedAt == nil {
                preference.deletedAt = now
                recordChanged = true
            }
            if recordChanged {
                preference.updatedAt = now
                preference.deviceID = deviceID
                preference.clientMutationID = UUID()
                changed = true
            }
        }

        if defaults.object(forKey: legacyLLMAPIKey) != nil {
            defaults.removeObject(forKey: legacyLLMAPIKey)
        }
        if changed {
            try context.save()
        }
    }

    private static func legacyValueJSON(for key: AppPreferenceKey, defaults: UserDefaults) -> String? {
        guard defaults.object(forKey: key.rawValue) != nil else { return nil }
        switch key {
        case .preferredColorScheme:
            guard let value = defaults.string(forKey: key.rawValue) else { return nil }
            return PreferenceJSON.encode(value)
        case .pomodoroDefaultMode:
            guard let value = defaults.string(forKey: key.rawValue) else { return nil }
            return PreferenceJSON.encode(value)
        case .defaultFocusMinutes:
            guard let value = defaults.object(forKey: key.rawValue) as? Int else { return nil }
            return PreferenceJSON.encode(value)
        case .defaultBreakMinutes:
            guard let value = defaults.object(forKey: key.rawValue) as? Int else { return nil }
            return PreferenceJSON.encode(value)
        case .defaultPomodoroRounds:
            guard let value = defaults.object(forKey: key.rawValue) as? Int else { return nil }
            return PreferenceJSON.encode(value)
        case .pomodoroPlans:
            guard let json = defaults.string(forKey: key.rawValue),
                  json.utf8.count <= PreferenceJSON.maximumPayloadByteCount,
                  let data = json.data(using: .utf8),
                  let plans = try? JSONDecoder().decode(LegacyPomodoroPlans.self, from: data).values else {
                return nil
            }
            return PreferenceJSON.encode(plans)
        case .allowParallelTimers:
            guard let value = defaults.object(forKey: key.rawValue) as? Bool else { return nil }
            return PreferenceJSON.encode(value)
        case .showGrossAndWallTogether:
            guard let value = defaults.object(forKey: key.rawValue) as? Bool else { return nil }
            return PreferenceJSON.encode(value)
        case .quickStartTaskIDs:
            let ids = defaults.string(forKey: key.rawValue)?
                .split(separator: ",")
                .map(String.init) ?? []
            return PreferenceJSON.encode(ids)
        case .llmEndpoint:
            guard let value = defaults.string(forKey: key.rawValue) else { return nil }
            return PreferenceJSON.encode(value)
        case .llmSelectedModel:
            guard let value = defaults.string(forKey: key.rawValue) else { return nil }
            return PreferenceJSON.encode(value)
        case .llmAvailableModelIDs:
            let models = defaults.string(forKey: key.rawValue)?
                .split(separator: ",")
                .map(String.init) ?? []
            return PreferenceJSON.encode(models)
        }
    }
}

private struct LegacyPomodoroPlans: Decodable {
    let values: [PomodoroPlan]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let maximumCount = AppPreferenceValueSanitizer.maximumPomodoroPlanCount
        if let count = container.count, count > maximumCount {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "Legacy Pomodoro plan count exceeds the supported maximum."
                )
            )
        }

        var values: [PomodoroPlan] = []
        values.reserveCapacity(min(container.count ?? maximumCount, maximumCount))
        while !container.isAtEnd {
            guard values.count < maximumCount else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath,
                        debugDescription: "Legacy Pomodoro plan count exceeds the supported maximum."
                    )
                )
            }
            values.append(try container.decode(PomodoroPlan.self))
        }
        self.values = values
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
