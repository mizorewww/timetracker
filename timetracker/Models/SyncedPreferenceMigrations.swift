import Foundation
import SwiftData

extension SyncedPreferenceService {
    @MainActor
    static func migrateLegacyPreferencesIfNeeded(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        deviceID: String = DeviceIdentity.current
    ) throws {
        guard !defaults.bool(forKey: migrationKey) else { return }

        try context.performAtomicMutation {
            let existing = try context.fetch(FetchDescriptor<SyncedPreference>())
            // A logical-key tombstone is still an existing migrated value. Ignoring it
            // would let stale UserDefaults recreate a preference that another device
            // already deleted.
            let existingKeys = Set(latestByKey(existing.deduplicatedByID()).keys)

            for key in AppPreferenceKey.allCases
            where shouldSyncKey(key.rawValue) && !existingKeys.contains(key.rawValue) {
                if let valueJSON = legacyValueJSON(for: key, defaults: defaults) {
                    context.insert(
                        SyncedPreference(
                            key: key.rawValue,
                            valueJSON: valueJSON,
                            deviceID: deviceID
                        )
                    )
                }
            }
        }

        defaults.set(true, forKey: migrationKey)
    }

    @MainActor
    static func migrateSensitivePreferences(
        context: ModelContext,
        credentialStore: any LLMCredentialStoring,
        defaults: UserDefaults = .standard,
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
        let legacyLocalCandidate = defaults.string(forKey: legacyLLMAPIKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if try credentialStore.readAPIKey() == nil,
           let candidate = syncedCandidate ?? legacyLocalCandidate,
           !candidate.isEmpty {
            try credentialStore.writeAPIKey(candidate)
        }

        if defaults.object(forKey: legacyLLMAPIKey) != nil {
            defaults.removeObject(forKey: legacyLLMAPIKey)
        }

        let redactedValue = try PreferenceJSON.encodeChecked("")
        let requiresRedaction = storedPreferences.contains {
            $0.valueJSON != redactedValue || $0.deletedAt == nil
        }
        guard requiresRedaction else { return }

        try context.performAtomicMutation {
            for preference in storedPreferences {
                guard preference.valueJSON != redactedValue || preference.deletedAt == nil else {
                    continue
                }
                preference.valueJSON = redactedValue
                preference.deletedAt = preference.deletedAt ?? now
                preference.updatedAt = now
                preference.deviceID = deviceID
                preference.clientMutationID = UUID()
            }
        }
    }

    private static func legacyValueJSON(for key: AppPreferenceKey, defaults: UserDefaults) -> String? {
        guard defaults.object(forKey: key.rawValue) != nil else { return nil }
        let encodedValue: String?
        switch key {
        case .preferredColorScheme:
            guard let value = defaults.string(forKey: key.rawValue) else { return nil }
            encodedValue = try? PreferenceJSON.encodeChecked(value)
        case .pomodoroDefaultMode:
            guard let value = defaults.string(forKey: key.rawValue) else { return nil }
            encodedValue = try? PreferenceJSON.encodeChecked(value)
        case .defaultFocusMinutes:
            guard let value = defaults.object(forKey: key.rawValue) as? Int else { return nil }
            encodedValue = try? PreferenceJSON.encodeChecked(value)
        case .defaultBreakMinutes:
            guard let value = defaults.object(forKey: key.rawValue) as? Int else { return nil }
            encodedValue = try? PreferenceJSON.encodeChecked(value)
        case .defaultPomodoroRounds:
            guard let value = defaults.object(forKey: key.rawValue) as? Int else { return nil }
            encodedValue = try? PreferenceJSON.encodeChecked(value)
        case .pomodoroPlans:
            guard let json = defaults.string(forKey: key.rawValue),
                  json.utf8.count <= PreferenceJSON.maximumPayloadByteCount,
                  let data = json.data(using: .utf8),
                  let plans = try? JSONDecoder().decode(LegacyPomodoroPlans.self, from: data).values else {
                return nil
            }
            encodedValue = try? PreferenceJSON.encodeChecked(plans)
        case .allowParallelTimers:
            guard let value = defaults.object(forKey: key.rawValue) as? Bool else { return nil }
            encodedValue = try? PreferenceJSON.encodeChecked(value)
        case .showGrossAndWallTogether:
            guard let value = defaults.object(forKey: key.rawValue) as? Bool else { return nil }
            encodedValue = try? PreferenceJSON.encodeChecked(value)
        case .quickStartTaskIDs:
            let ids = defaults.string(forKey: key.rawValue)?
                .split(separator: ",")
                .map(String.init) ?? []
            encodedValue = try? PreferenceJSON.encodeChecked(ids)
        case .llmEndpoint:
            guard let value = defaults.string(forKey: key.rawValue) else { return nil }
            encodedValue = try? PreferenceJSON.encodeChecked(value)
        case .llmSelectedModel:
            guard let value = defaults.string(forKey: key.rawValue) else { return nil }
            encodedValue = try? PreferenceJSON.encodeChecked(value)
        case .llmAvailableModelIDs:
            let models = defaults.string(forKey: key.rawValue)?
                .split(separator: ",")
                .map(String.init) ?? []
            encodedValue = try? PreferenceJSON.encodeChecked(models)
        case .llmTaskPlanInstructions:
            guard let value = defaults.string(forKey: key.rawValue) else { return nil }
            encodedValue = try? PreferenceJSON.encodeChecked(value)
        }
        guard let encodedValue else { return nil }
        return try? PreferenceJSON.canonicalValueJSON(for: key, from: encodedValue)
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
