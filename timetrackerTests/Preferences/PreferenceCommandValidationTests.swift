import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct PreferenceCommandValidationTests {
    @Test @MainActor
    func malformedNullWrongTypeAndOversizedValuesNeverCreateRecords() throws {
        let context = try makeTestContext()
        let handler = PreferenceCommandHandler()
        let invalidValues: [(AppPreferenceKey, String, PreferenceJSONError)] = [
            (.defaultFocusMinutes, "{", .invalidValue),
            (.defaultFocusMinutes, "null", .invalidValue),
            (.defaultFocusMinutes, PreferenceJSON.encode("25"), .invalidValue),
            (
                .llmEndpoint,
                String(repeating: "x", count: PreferenceJSON.maximumPayloadByteCount + 1),
                .payloadTooLarge
            )
        ]

        for (key, valueJSON, expectedError) in invalidValues {
            #expect(throws: expectedError) {
                try handler.set(key: key, valueJSON: valueJSON, context: context)
            }
            #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).isEmpty)
        }
    }

    @Test @MainActor
    func invalidLaterBatchValueLeavesEveryExistingRecordUnchanged() throws {
        let context = try makeTestContext()
        let originalDate = Date(timeIntervalSinceReferenceDate: 100_000)
        let originalMutationID = UUID()
        let preference = SyncedPreference(
            key: AppPreferenceKey.defaultFocusMinutes.rawValue,
            valueJSON: PreferenceJSON.encode(25),
            deviceID: "original-device"
        )
        preference.createdAt = originalDate
        preference.updatedAt = originalDate
        preference.clientMutationID = originalMutationID
        context.insert(preference)
        try context.save()

        #expect(throws: PreferenceJSONError.invalidValue) {
            try PreferenceCommandHandler().set(
                values: [
                    (.defaultFocusMinutes, PreferenceJSON.encode(55)),
                    (.defaultBreakMinutes, PreferenceJSON.encode("wrong-type"))
                ],
                context: context,
                now: originalDate.addingTimeInterval(100)
            )
        }

        let stored = try context.fetch(FetchDescriptor<SyncedPreference>())
        let unchanged = try #require(stored.first)
        #expect(stored.count == 1)
        #expect(unchanged.id == preference.id)
        #expect(unchanged.valueJSON == PreferenceJSON.encode(25))
        #expect(unchanged.updatedAt == originalDate)
        #expect(unchanged.deviceID == "original-device")
        #expect(unchanged.clientMutationID == originalMutationID)
        #expect(unchanged.deletedAt == nil)
    }

    @Test @MainActor
    func validBatchIsCanonicalizedBeforeItIsPersisted() throws {
        let context = try makeTestContext()
        let validTaskID = UUID()

        try PreferenceCommandHandler().set(
            values: [
                (.preferredColorScheme, PreferenceJSON.encode("neon")),
                (.defaultFocusMinutes, PreferenceJSON.encode(999)),
                (
                    .quickStartTaskIDs,
                    PreferenceJSON.encode([
                        validTaskID.uuidString,
                        "not-a-uuid",
                        validTaskID.uuidString.lowercased()
                    ])
                )
            ],
            context: context
        )

        let stored = try context.fetch(FetchDescriptor<SyncedPreference>())
        let valuesByKey = Dictionary(uniqueKeysWithValues: stored.map { ($0.key, $0.valueJSON) })
        #expect(valuesByKey[AppPreferenceKey.preferredColorScheme.rawValue] == PreferenceJSON.encode("system"))
        #expect(valuesByKey[AppPreferenceKey.defaultFocusMinutes.rawValue] == PreferenceJSON.encode(480))
        #expect(
            valuesByKey[AppPreferenceKey.quickStartTaskIDs.rawValue] ==
                PreferenceJSON.encode([validTaskID.uuidString])
        )
    }

    @Test @MainActor
    func standaloneCommandRollsBackWhenReadOnlyStoreCannotSave() throws {
        let storeDirectory = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let storeURL = storeDirectory.appending(path: "preferences.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        let preferenceID = UUID()
        let originalDate = Date(timeIntervalSinceReferenceDate: 100_000)
        let originalMutationID = UUID()

        try initializeWritableStore(at: storeURL, schema: schema) { context in
            let preference = SyncedPreference(
                key: AppPreferenceKey.defaultFocusMinutes.rawValue,
                valueJSON: PreferenceJSON.encode(25),
                deviceID: "original-device"
            )
            preference.id = preferenceID
            preference.createdAt = originalDate
            preference.updatedAt = originalDate
            preference.clientMutationID = originalMutationID
            context.insert(preference)
        }

        let readOnlyContainer = try makeReadOnlyContainer(at: storeURL, schema: schema)
        let context = ModelContext(readOnlyContainer)
        #expect(throws: (any Error).self) {
            try PreferenceCommandHandler().set(
                key: .defaultFocusMinutes,
                valueJSON: PreferenceJSON.encode(55),
                context: context,
                now: originalDate.addingTimeInterval(100)
            )
        }

        let stored = try #require(
            context.fetch(FetchDescriptor<SyncedPreference>()).first { $0.id == preferenceID }
        )
        #expect(stored.valueJSON == PreferenceJSON.encode(25))
        #expect(stored.updatedAt == originalDate)
        #expect(stored.deviceID == "original-device")
        #expect(stored.clientMutationID == originalMutationID)
        #expect(stored.deletedAt == nil)
    }

    @Test @MainActor
    func oversizedLegacyValueIsSkippedInsteadOfBecomingJSONNull() throws {
        let suiteName = "PreferenceCommandValidationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            String(repeating: "x", count: PreferenceJSON.maximumPayloadByteCount + 1),
            forKey: AppPreferenceKey.llmEndpoint.rawValue
        )
        let context = try makeTestContext()

        try SyncedPreferenceService.migrateLegacyPreferencesIfNeeded(
            context: context,
            defaults: defaults,
            deviceID: "migration-device"
        )

        let stored = try context.fetch(FetchDescriptor<SyncedPreference>())
        #expect(stored.isEmpty)
        #expect(defaults.bool(forKey: SyncedPreferenceService.migrationKey))
        #expect(stored.allSatisfy { $0.valueJSON != "null" })
    }

    @Test
    func checkedEncodingReportsEncodingFailuresInsteadOfReturningJSONNull() {
        #expect(throws: PreferenceJSONError.encodingFailed) {
            try PreferenceJSON.encodeChecked(FailingEncodable())
        }
    }

    @MainActor
    private func initializeWritableStore(
        at url: URL,
        schema: Schema,
        seed: (ModelContext) throws -> Void
    ) throws {
        let configuration = ModelConfiguration(
            "WritablePreferenceCommandValidationTests-\(UUID().uuidString)",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        try seed(context)
        try context.save()
    }

    @MainActor
    private func makeReadOnlyContainer(at url: URL, schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "ReadOnlyPreferenceCommandValidationTests-\(UUID().uuidString)",
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
        let url = FileManager.default.temporaryDirectory.appending(
            path: "PreferenceCommandValidationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct FailingEncodable: Encodable {
    func encode(to encoder: Encoder) throws {
        throw FailingEncodingError()
    }
}

private struct FailingEncodingError: Error {}
