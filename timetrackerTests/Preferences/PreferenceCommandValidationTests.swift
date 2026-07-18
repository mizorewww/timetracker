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
    func invalidTaskPlanInstructionsNeverCreateAPreferenceRecord() throws {
        let context = try makeTestContext()
        let handler = PreferenceCommandHandler()
        let oversized = String(
            repeating: "🧭",
            count: AppPreferenceValueSanitizer.maximumLLMTaskPlanInstructionsByteCount / 4 + 1
        )

        #expect(throws: LLMTaskPlanInstructionsValidationError.controlCharacter) {
            try handler.set(
                key: .llmTaskPlanInstructions,
                valueJSON: PreferenceJSON.encode("Plan\u{0000}tasks"),
                context: context
            )
        }
        #expect(throws: LLMTaskPlanInstructionsValidationError.byteLimitExceeded(
            actual: oversized.utf8.count,
            maximum: AppPreferenceValueSanitizer.maximumLLMTaskPlanInstructionsByteCount
        )) {
            try handler.set(
                key: .llmTaskPlanInstructions,
                valueJSON: PreferenceJSON.encode(oversized),
                context: context
            )
        }
        #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).isEmpty)
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
    func settingLogicalKeySupersedesActiveAndDeletedPhysicalSiblings() throws {
        let base = Date(timeIntervalSinceReferenceDate: 250_000)
        let mutationDate = base.addingTimeInterval(100)
        let key = AppPreferenceKey.defaultFocusMinutes

        for reverseInsertionOrder in [false, true] {
            let context = try makeTestContext()
            let activeWinner = SyncedPreference(
                key: key.rawValue,
                valueJSON: PreferenceJSON.encode(20),
                deviceID: "cloud-a"
            )
            activeWinner.createdAt = base
            activeWinner.updatedAt = base.addingTimeInterval(20)
            let activeSibling = SyncedPreference(
                key: key.rawValue,
                valueJSON: PreferenceJSON.encode(10),
                deviceID: "cloud-b"
            )
            activeSibling.createdAt = base.addingTimeInterval(10)
            activeSibling.updatedAt = base.addingTimeInterval(10)
            let deletedSibling = SyncedPreference(
                key: key.rawValue,
                valueJSON: PreferenceJSON.encode(5),
                deviceID: "cloud-c"
            )
            deletedSibling.createdAt = base.addingTimeInterval(30)
            deletedSibling.updatedAt = base.addingTimeInterval(30)
            deletedSibling.deletedAt = base.addingTimeInterval(30)

            let rows = [activeWinner, activeSibling, deletedSibling]
            let insertionOrder = reverseInsertionOrder ? Array(rows.reversed()) : rows
            for row in insertionOrder {
                context.insert(row)
            }
            try context.save()

            try PreferenceCommandHandler().set(
                key: key,
                valueJSON: PreferenceJSON.encode(55),
                context: context,
                now: mutationDate
            )

            let stored = try context.fetch(FetchDescriptor<SyncedPreference>())
            let winner = try #require(SyncedPreferenceService.latestByKey(stored)[key.rawValue])
            #expect(winner.deletedAt == nil)
            #expect(winner.valueJSON == PreferenceJSON.encode(55))
            #expect(winner.updatedAt == mutationDate)
            #expect(stored.filter { $0 !== winner }.allSatisfy {
                $0.deletedAt == mutationDate.addingTimeInterval(-1) &&
                    $0.updatedAt == mutationDate.addingTimeInterval(-1)
            })
        }
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

    @Test
    func opaqueModelIdentifiersUseAByteLimitAndAreNeverTruncatedIntoAnotherIdentity() {
        #expect(
            AppPreferenceValueSanitizer.maximumLLMModelIDByteCount ==
                LLMSuggestionInputPolicy.maximumModelIDByteCount
        )
        #expect(
            AppPreferenceValueSanitizer.maximumLLMModelIDByteCount ==
                SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount
        )

        let exactBoundary = String(
            repeating: "m",
            count: AppPreferenceValueSanitizer.maximumLLMModelIDByteCount
        )
        let oversizedUnicode = String(repeating: "🧭", count: 65)
        let controlCharacter = "model\u{0000}suffix"

        #expect(AppPreferenceValueSanitizer.llmModelID("  \(exactBoundary)  ") == exactBoundary)
        #expect(AppPreferenceValueSanitizer.llmModelID(oversizedUnicode).isEmpty)
        #expect(AppPreferenceValueSanitizer.llmModelID(controlCharacter).isEmpty)
        #expect(
            AppPreferenceValueSanitizer.llmModelIDs([
                exactBoundary,
                oversizedUnicode,
                controlCharacter
            ]) == [exactBoundary]
        )
        #expect(!AppPreferenceValueSanitizer.llmModelIDs([oversizedUnicode]).contains {
            $0 == LLMSuggestionInputPolicy.boundedTrimmedUTF8(
                oversizedUnicode,
                maximumByteCount: LLMSuggestionInputPolicy.maximumModelIDByteCount
            )
        })
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
