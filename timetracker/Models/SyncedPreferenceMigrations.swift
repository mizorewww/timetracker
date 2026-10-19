import Foundation
import SwiftData

@MainActor
extension SyncedPreferenceService {
    static func migrateSensitivePreferences(
        context: ModelContext,
        credentialStore: any LLMCredentialStoring,
        defaults: UserDefaults = AppDefaults.shared,
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
           !candidate.isEmpty
        {
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
                preference.markMutated(at: now, deviceID: deviceID)
            }
        }
    }
}
