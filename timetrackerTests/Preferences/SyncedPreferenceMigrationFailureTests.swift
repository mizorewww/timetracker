import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct SyncedPreferenceMigrationFailureTests {
    @Test @MainActor
    func legacyMigrationRollsBackPendingRecordsWhenSaveFails() throws {
        let defaults = try makeDefaults()
        defer { clear(defaults) }
        defaults.set(55, forKey: AppPreferenceKey.defaultFocusMinutes.rawValue)

        let storeDirectory = try makeStoreDirectory()
        let storeURL = storeDirectory.appending(path: "legacy-preferences.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        try initializeWritableStore(at: storeURL, schema: schema)
        let readOnlyContainer = try makeReadOnlyContainer(at: storeURL, schema: schema)
        let context = ModelContext(readOnlyContainer)

        #expect(throws: (any Error).self) {
            try SyncedPreferenceService.migrateLegacyPreferencesIfNeeded(
                context: context,
                defaults: defaults,
                deviceID: "migration"
            )
        }

        #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).isEmpty)
        #expect(!defaults.bool(forKey: SyncedPreferenceService.migrationKey))
        #expect(defaults.object(forKey: AppPreferenceKey.defaultFocusMinutes.rawValue) as? Int == 55)
    }

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

    @MainActor
    private func initializeWritableStore(
        at url: URL,
        schema: Schema,
        seed: ((ModelContext) throws -> Void)? = nil
    ) throws {
        let configuration = ModelConfiguration(
            "WritableSyncedPreferenceMigrationTests-\(UUID().uuidString)",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
        guard let seed else { return }
        let context = ModelContext(container)
        try seed(context)
        try context.save()
    }

    @MainActor
    private func makeReadOnlyContainer(at url: URL, schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "ReadOnlySyncedPreferenceMigrationTests-\(UUID().uuidString)",
            schema: schema,
            url: url,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private func makeStoreDirectory() throws -> URL {
        // SwiftData may close SQLite sidecars asynchronously. Keep these unique
        // stores in the sandbox temp directory for operating-system cleanup.
        let url = FileManager.default.temporaryDirectory.appending(
            path: "SyncedPreferenceMigrationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SyncedPreferenceMigrationFailureTests-\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suiteName))
    }

    private func clear(_ defaults: UserDefaults) {
        for key in AppPreferenceKey.allCases.map(\.rawValue) + [
            SyncedPreferenceService.migrationKey,
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
