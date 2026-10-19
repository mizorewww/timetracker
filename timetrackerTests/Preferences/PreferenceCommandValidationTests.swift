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
            (.allowParallelTimers, "{", .invalidValue),
            (.allowParallelTimers, "null", .invalidValue),
            (.allowParallelTimers, PreferenceJSON.encode("true"), .invalidValue),
            (.todayHeatmapPeriod, PreferenceJSON.encode(42), .invalidValue),
            (
                .llmEndpoint,
                String(repeating: "x", count: PreferenceJSON.maximumPayloadByteCount + 1),
                .payloadTooLarge
            ),
        ]

        for (key, valueJSON, expectedError) in invalidValues {
            #expect(throws: expectedError) {
                try handler.set(key: key, valueJSON: valueJSON, context: context)
            }
            #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).isEmpty)
        }
    }

    @Test @MainActor
    func taskPlanInstructionsWithControlCharactersNeverCreateAPreferenceRecord() throws {
        let context = try makeTestContext()
        let handler = PreferenceCommandHandler()

        #expect(throws: LLMPromptInstructionsValidationError.controlCharacter) {
            try handler.set(
                key: .llmTaskPlanInstructions,
                valueJSON: PreferenceJSON.encode("Plan\u{0000}tasks"),
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
            key: AppPreferenceKey.allowParallelTimers.rawValue,
            valueJSON: PreferenceJSON.encode(true),
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
                    (.allowParallelTimers, PreferenceJSON.encode(false)),
                    (.showGrossAndWallTogether, PreferenceJSON.encode("wrong-type")),
                ],
                context: context,
                now: originalDate.addingTimeInterval(100)
            )
        }

        let stored = try context.fetch(FetchDescriptor<SyncedPreference>())
        let unchanged = try #require(stored.first)
        #expect(stored.count == 1)
        #expect(unchanged.id == preference.id)
        #expect(unchanged.valueJSON == PreferenceJSON.encode(true))
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
                (.todayHeatmapPeriod, PreferenceJSON.encode("futurePeriod")),
                (
                    .quickStartTaskIDs,
                    PreferenceJSON.encode([
                        validTaskID.uuidString,
                        "not-a-uuid",
                        validTaskID.uuidString.lowercased(),
                    ])
                ),
            ],
            context: context
        )

        let stored = try context.fetch(FetchDescriptor<SyncedPreference>())
        let valuesByKey = Dictionary(uniqueKeysWithValues: stored.map { ($0.key, $0.valueJSON) })
        #expect(valuesByKey[AppPreferenceKey.preferredColorScheme.rawValue] == PreferenceJSON.encode("system"))
        #expect(
            valuesByKey[AppPreferenceKey.todayHeatmapPeriod.rawValue] ==
                PreferenceJSON.encode(ActivityHeatmapPeriod.standard.rawValue)
        )
        #expect(
            valuesByKey[AppPreferenceKey.quickStartTaskIDs.rawValue] ==
                PreferenceJSON.encode([validTaskID.uuidString])
        )
    }

    @Test @MainActor
    func settingLogicalKeySupersedesActiveAndDeletedPhysicalSiblings() throws {
        let base = Date(timeIntervalSinceReferenceDate: 250_000)
        let mutationDate = base.addingTimeInterval(100)
        let key = AppPreferenceKey.llmSelectedModel

        for reverseInsertionOrder in [false, true] {
            let context = try makeTestContext()
            let activeWinner = SyncedPreference(
                key: key.rawValue,
                valueJSON: PreferenceJSON.encode("model-a"),
                deviceID: "cloud-a"
            )
            activeWinner.createdAt = base
            activeWinner.updatedAt = base.addingTimeInterval(20)
            let activeSibling = SyncedPreference(
                key: key.rawValue,
                valueJSON: PreferenceJSON.encode("model-b"),
                deviceID: "cloud-b"
            )
            activeSibling.createdAt = base.addingTimeInterval(10)
            activeSibling.updatedAt = base.addingTimeInterval(10)
            let deletedSibling = SyncedPreference(
                key: key.rawValue,
                valueJSON: PreferenceJSON.encode("model-c"),
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
                valueJSON: PreferenceJSON.encode("model-new"),
                context: context,
                now: mutationDate
            )

            let stored = try context.fetch(FetchDescriptor<SyncedPreference>())
            let winner = try #require(SyncedPreferenceService.latestByKey(stored)[key.rawValue])
            #expect(winner.deletedAt == nil)
            #expect(winner.valueJSON == PreferenceJSON.encode("model-new"))
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
        let storeURL = storeDirectory.appending(path: "preferences.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        let preferenceID = UUID()
        let originalDate = Date(timeIntervalSinceReferenceDate: 100_000)
        let originalMutationID = UUID()

        try initializeWritableStore(at: storeURL, schema: schema) { context in
            let preference = SyncedPreference(
                key: AppPreferenceKey.allowParallelTimers.rawValue,
                valueJSON: PreferenceJSON.encode(true),
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
                key: .allowParallelTimers,
                valueJSON: PreferenceJSON.encode(false),
                context: context,
                now: originalDate.addingTimeInterval(100)
            )
        }

        let stored = try #require(
            context.fetch(FetchDescriptor<SyncedPreference>()).first { $0.id == preferenceID }
        )
        #expect(stored.valueJSON == PreferenceJSON.encode(true))
        #expect(stored.updatedAt == originalDate)
        #expect(stored.deviceID == "original-device")
        #expect(stored.clientMutationID == originalMutationID)
        #expect(stored.deletedAt == nil)
    }

    @Test
    func checkedEncodingReportsEncodingFailuresInsteadOfReturningJSONNull() {
        #expect(throws: PreferenceJSONError.encodingFailed) {
            try PreferenceJSON.encodeChecked(FailingEncodable())
        }
    }

    @Test
    func opaqueModelIdentifiersUseAByteLimitAndAreNeverTruncatedIntoAnotherIdentity() {
        let exactBoundary = String(
            repeating: "m",
            count: AppPreferenceValueSanitizer.maximumLLMModelIDByteCount
        )
        // "🧭" is four UTF-8 bytes, so this is one character past the byte limit.
        let oversizedUnicode = String(
            repeating: "🧭",
            count: AppPreferenceValueSanitizer.maximumLLMModelIDByteCount / 4 + 1
        )
        let controlCharacter = "model\u{0000}suffix"

        #expect(AppPreferenceValueSanitizer.llmModelID("  \(exactBoundary)  ") == exactBoundary)
        #expect(AppPreferenceValueSanitizer.llmModelID(oversizedUnicode).isEmpty)
        #expect(AppPreferenceValueSanitizer.llmModelID(controlCharacter).isEmpty)
        #expect(
            AppPreferenceValueSanitizer.llmModelIDs([
                exactBoundary,
                oversizedUnicode,
                controlCharacter,
            ]) == [exactBoundary]
        )
    }
}

private struct FailingEncodable: Encodable {
    func encode(to _: Encoder) throws {
        throw FailingEncodingError()
    }
}

private struct FailingEncodingError: Error {}
