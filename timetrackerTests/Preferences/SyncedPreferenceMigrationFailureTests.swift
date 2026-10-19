import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct SyncedPreferenceMigrationFailureTests {
    @Test @MainActor
    func sensitiveMigrationRollsBackRedactionWhenSaveFails() throws {
        let defaults = try makeDefaults()
        defer { clear(defaults) }
        let storeDirectory = try makeStoreDirectory()
        let storeURL = storeDirectory.appending(path: "sensitive-preferences.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        let recordID = UUID()
        let originalValue = PreferenceJSON.encode("legacy-secret")
        let originalDate = Date(timeIntervalSinceReferenceDate: 100_000)
        try initializeWritableStore(at: storeURL, schema: schema) { context in
            let preference = SyncedPreference(
                key: SyncedPreferenceService.legacyLLMAPIKey,
                valueJSON: originalValue,
                deviceID: "legacy-device"
            )
            preference.id = recordID
            preference.createdAt = originalDate
            preference.updatedAt = originalDate
            context.insert(preference)
        }
        let readOnlyContainer = try makeReadOnlyContainer(at: storeURL, schema: schema)
        let context = ModelContext(readOnlyContainer)
        let credentialStore = RecordingCredentialStore()

        #expect(throws: (any Error).self) {
            try SyncedPreferenceService.migrateSensitivePreferences(
                context: context,
                credentialStore: credentialStore,
                defaults: defaults,
                now: originalDate.addingTimeInterval(100),
                deviceID: "migration"
            )
        }

        let stored = try #require(
            context.fetch(FetchDescriptor<SyncedPreference>()).first { $0.id == recordID }
        )
        #expect(stored.valueJSON == originalValue)
        #expect(stored.deletedAt == nil)
        #expect(stored.updatedAt == originalDate)
        #expect(stored.deviceID == "legacy-device")
        #expect(try credentialStore.readAPIKey() == "legacy-secret")
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SyncedPreferenceMigrationFailureTests-\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suiteName))
    }

    private func clear(_ defaults: UserDefaults) {
        for key in AppPreferenceKey.allCases.map(\.rawValue) + [
            SyncedPreferenceService.legacyLLMAPIKey,
        ] {
            defaults.removeObject(forKey: key)
        }
    }
}

private final class RecordingCredentialStore: LLMCredentialStoring {
    private var apiKey: String?

    func readAPIKey() throws -> String? {
        apiKey
    }

    func writeAPIKey(_ apiKey: String) throws {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = normalized.isEmpty ? nil : normalized
    }
}
