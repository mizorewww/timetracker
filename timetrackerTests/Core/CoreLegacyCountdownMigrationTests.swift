import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreLegacyCountdownMigrationTests {
    @Test @MainActor
    func validLegacyPayloadMigratesWithoutChangingIdentityOrContent() throws {
        let defaults = try makeDefaults()
        defer { clear(defaults) }
        let preservedID = UUID()
        let earlierDate = Date(timeIntervalSince1970: 1_893_456_000)
        let laterDate = Date(timeIntervalSince1970: 1_924_992_000)
        defaults.set(
            """
            [
              {"id":"\(preservedID.uuidString)","title":"发布 🚀","date":"2030-01-01T00:00:00Z"},
              {"title":"","date":"2031-01-01T00:00:00Z"}
            ]
            """,
            forKey: LegacyCountdownMigrationPolicy.payloadKey
        )

        let context = try makeTestContext()
        try makeTestStore().migrateLegacyCountdownEventsIfNeeded(
            context: context,
            defaults: defaults,
            deviceID: "legacy-device"
        )

        let events = try context.fetch(FetchDescriptor<CountdownEvent>())
            .sorted { $0.date < $1.date }
        #expect(events.count == 2)
        #expect(events[0].id == preservedID)
        #expect(events[0].title == "发布 🚀")
        #expect(events[0].date == earlierDate)
        #expect(events[0].deviceID == "legacy-device")
        #expect(events[1].title.isEmpty)
        #expect(events[1].date == laterDate)
        #expect(defaults.bool(forKey: LegacyCountdownMigrationPolicy.migrationKey))
        #expect(defaults.object(forKey: LegacyCountdownMigrationPolicy.payloadKey) == nil)
    }

    @Test @MainActor
    func oversizedPayloadIsRejectedAndRetiredWithoutDecoding() throws {
        let defaults = try makeDefaults()
        defer { clear(defaults) }
        defaults.set(
            String(repeating: "x", count: LegacyCountdownMigrationPolicy.maximumPayloadByteCount + 1),
            forKey: LegacyCountdownMigrationPolicy.payloadKey
        )

        let context = try makeTestContext()
        try makeTestStore().migrateLegacyCountdownEventsIfNeeded(
            context: context,
            defaults: defaults,
            deviceID: "test"
        )

        #expect(try context.fetch(FetchDescriptor<CountdownEvent>()).isEmpty)
        #expect(defaults.bool(forKey: LegacyCountdownMigrationPolicy.migrationKey))
        #expect(defaults.object(forKey: LegacyCountdownMigrationPolicy.payloadKey) == nil)
    }

    @Test @MainActor
    func payloadAboveMaximumRecordCountIsRejected() throws {
        let defaults = try makeDefaults()
        defer { clear(defaults) }
        let records = (0...LegacyCountdownMigrationPolicy.maximumEventCount).map { index in
            "{\"title\":\"Event \(index)\",\"date\":\"2030-01-01T00:00:00Z\"}"
        }
        defaults.set("[\(records.joined(separator: ","))]", forKey: LegacyCountdownMigrationPolicy.payloadKey)

        let context = try makeTestContext()
        try makeTestStore().migrateLegacyCountdownEventsIfNeeded(
            context: context,
            defaults: defaults,
            deviceID: "test"
        )

        #expect(try context.fetch(FetchDescriptor<CountdownEvent>()).isEmpty)
        #expect(defaults.bool(forKey: LegacyCountdownMigrationPolicy.migrationKey))
    }

    @Test @MainActor
    func maximumCountTitleAndSupportedDatesRemainCompatible() {
        let records = (0..<LegacyCountdownMigrationPolicy.maximumEventCount).map { index in
            let title = index == 0
                ? String(repeating: "x", count: LegacyCountdownMigrationPolicy.maximumTitleByteCount)
                : "Event \(index)"
            let date = index == 0
                ? "1900-01-01T00:00:00Z"
                : "2200-12-31T23:59:59Z"
            return "{\"title\":\"\(title)\",\"date\":\"\(date)\"}"
        }

        let events = LegacyCountdownMigrationPolicy.decode(
            "[\(records.joined(separator: ","))]"
        )

        #expect(events.count == LegacyCountdownMigrationPolicy.maximumEventCount)
        #expect(events.first?.title.utf8.count == LegacyCountdownMigrationPolicy.maximumTitleByteCount)
        #expect(events.first?.date == LegacyCountdownMigrationPolicy.earliestSupportedDate)
        #expect(
            events.last?.date
                == LegacyCountdownMigrationPolicy.latestSupportedDate.addingTimeInterval(-1)
        )
    }

    @Test @MainActor
    func invalidRecordsAndDuplicateIDsAreFilteredWithoutLosingValidRecords() throws {
        let defaults = try makeDefaults()
        defer { clear(defaults) }
        let duplicateID = UUID()
        let longTitle = String(
            repeating: "🧑🏽‍💻",
            count: LegacyCountdownMigrationPolicy.maximumTitleByteCount
        )
        defaults.set(
            """
            [
              {"id":"\(duplicateID.uuidString)","title":"Keep first","date":"2030-01-01T00:00:00Z"},
              {"id":"\(duplicateID.uuidString)","title":"Drop duplicate","date":"2031-01-01T00:00:00Z"},
              {"title":"Same","date":"2032-01-01T00:00:00Z"},
              {"title":"Same","date":"2032-01-01T00:00:00Z"},
              {"title":"\(longTitle)","date":"2033-01-01T00:00:00Z"},
              {"title":"Too early","date":"1899-12-31T23:59:59Z"},
              {"title":"Too late","date":"2201-01-01T00:00:00Z"},
              {"id":"not-a-uuid","title":"Bad ID","date":"2034-01-01T00:00:00Z"}
            ]
            """,
            forKey: LegacyCountdownMigrationPolicy.payloadKey
        )

        let context = try makeTestContext()
        try makeTestStore().migrateLegacyCountdownEventsIfNeeded(
            context: context,
            defaults: defaults,
            deviceID: "test"
        )

        let events = try context.fetch(FetchDescriptor<CountdownEvent>())
        #expect(events.count == 3)
        #expect(events.filter { $0.id == duplicateID }.map(\.title) == ["Keep first"])
        #expect(events.filter { $0.title == "Same" }.count == 2)
    }

    @Test @MainActor
    func existingSwiftDataEventsMergeWithLegacyImportBeforeRetiringPayload() throws {
        let defaults = try makeDefaults()
        defer { clear(defaults) }
        defaults.set(
            "[{\"title\":\"Legacy\",\"date\":\"2030-01-01T00:00:00Z\"}]",
            forKey: LegacyCountdownMigrationPolicy.payloadKey
        )
        let context = try makeTestContext()
        context.insert(CountdownEvent(title: "Existing", date: Date(), deviceID: "test"))
        try context.save()

        try makeTestStore().migrateLegacyCountdownEventsIfNeeded(
            context: context,
            defaults: defaults,
            deviceID: "test"
        )

        let events = try context.fetch(FetchDescriptor<CountdownEvent>())
        #expect(Set(events.map(\.title)) == Set(["Existing", "Legacy"]))
        #expect(defaults.bool(forKey: LegacyCountdownMigrationPolicy.migrationKey))
        #expect(defaults.object(forKey: LegacyCountdownMigrationPolicy.payloadKey) == nil)
    }

    @Test @MainActor
    func existingLogicalIdentityWinsWhileUnrelatedLegacyEventsStillMigrate() throws {
        let defaults = try makeDefaults()
        defer { clear(defaults) }
        let existingID = UUID()
        defaults.set(
            """
            [
              {"id":"\(existingID.uuidString)","title":"Stale legacy copy","date":"2030-01-01T00:00:00Z"},
              {"title":"Keep this legacy event","date":"2031-01-01T00:00:00Z"}
            ]
            """,
            forKey: LegacyCountdownMigrationPolicy.payloadKey
        )
        let context = try makeTestContext()
        let existing = CountdownEvent(
            title: "CloudKit winner",
            date: Date(timeIntervalSince1970: 1_900_000_000),
            deviceID: "cloud"
        )
        existing.id = existingID
        context.insert(existing)
        try context.save()

        try makeTestStore().migrateLegacyCountdownEventsIfNeeded(
            context: context,
            defaults: defaults,
            deviceID: "local"
        )

        let events = try context.fetch(FetchDescriptor<CountdownEvent>()).deduplicatedByID()
        #expect(events.count == 2)
        #expect(events.first(where: { $0.id == existingID })?.title == "CloudKit winner")
        #expect(events.contains(where: { $0.title == "Keep this legacy event" }))
    }

    @Test @MainActor
    func retryAfterCommittedSaveDoesNotDuplicateIdentitylessLegacyEvents() throws {
        let defaults = try makeDefaults()
        defer { clear(defaults) }
        let payload = """
        [
          {"title":"Same","date":"2030-01-01T00:00:00Z"},
          {"title":"Same","date":"2030-01-01T00:00:00Z"}
        ]
        """
        defaults.set(payload, forKey: LegacyCountdownMigrationPolicy.payloadKey)
        let context = try makeTestContext()
        let store = makeTestStore()

        try store.migrateLegacyCountdownEventsIfNeeded(
            context: context,
            defaults: defaults,
            deviceID: "local"
        )
        defaults.set(false, forKey: LegacyCountdownMigrationPolicy.migrationKey)
        defaults.set(payload, forKey: LegacyCountdownMigrationPolicy.payloadKey)

        try store.migrateLegacyCountdownEventsIfNeeded(
            context: context,
            defaults: defaults,
            deviceID: "local"
        )

        let events = try context.fetch(FetchDescriptor<CountdownEvent>())
        #expect(events.count == 2)
        #expect(defaults.bool(forKey: LegacyCountdownMigrationPolicy.migrationKey))
        #expect(defaults.object(forKey: LegacyCountdownMigrationPolicy.payloadKey) == nil)
    }

    @Test @MainActor
    func failedSaveKeepsLegacyPayloadAndMigrationFlagRetryable() throws {
        let defaults = try makeDefaults()
        defer { clear(defaults) }
        let payload = "[{\"title\":\"Retry me\",\"date\":\"2030-01-01T00:00:00Z\"}]"
        defaults.set(payload, forKey: LegacyCountdownMigrationPolicy.payloadKey)

        let storeDirectory = FileManager.default.temporaryDirectory
            .appending(path: "ReadOnlyCountdownMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let storeURL = storeDirectory.appending(path: "countdown.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        try initializeWritableStore(at: storeURL, schema: schema)
        let configuration = ModelConfiguration(
            "ReadOnlyCountdownMigrationTests-\(UUID().uuidString)",
            schema: schema,
            url: storeURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)

        #expect(throws: (any Error).self) {
            try makeTestStore().migrateLegacyCountdownEventsIfNeeded(
                context: context,
                defaults: defaults,
                deviceID: "test"
            )
        }
        #expect(!defaults.bool(forKey: LegacyCountdownMigrationPolicy.migrationKey))
        #expect(defaults.string(forKey: LegacyCountdownMigrationPolicy.payloadKey) == payload)
    }

    @MainActor
    private func initializeWritableStore(at url: URL, schema: Schema) throws {
        let configuration = ModelConfiguration(
            "WritableCountdownMigrationTests-\(UUID().uuidString)",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        _ = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "CoreLegacyCountdownMigrationTests-\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suiteName))
    }

    private func clear(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: LegacyCountdownMigrationPolicy.payloadKey)
        defaults.removeObject(forKey: LegacyCountdownMigrationPolicy.migrationKey)
    }
}
