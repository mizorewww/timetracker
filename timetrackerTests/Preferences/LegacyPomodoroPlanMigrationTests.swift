import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct LegacyPomodoroPlanMigrationTests {
    @Test @MainActor
    func validPayloadMigratesWithPomodoroPlanNormalization() throws {
        let defaults = try makeDefaults()
        defer { clear(defaults) }
        let planID = UUID()
        defaults.set(
            """
            [{
              "id":"\(planID.uuidString)",
              "name":"  Writing  ",
              "iconName":"timer",
              "colorHex":"FF2D55",
              "focusMinutes":63,
              "shortBreakMinutes":1,
              "longBreakMinutes":18,
              "rounds":99
            }]
            """,
            forKey: AppPreferenceKey.pomodoroPlans.rawValue
        )

        let context = try makeTestContext()
        try SyncedPreferenceService.migrateLegacyPreferencesIfNeeded(
            context: context,
            defaults: defaults,
            deviceID: "test"
        )

        let stored = try context.fetch(FetchDescriptor<SyncedPreference>())
        let preference = try #require(stored.first)
        let plans = PreferenceJSON.decode([PomodoroPlan].self, from: preference.valueJSON, default: [])
        let plan = try #require(plans.first)
        #expect(stored.count == 1)
        #expect(preference.key == AppPreferenceKey.pomodoroPlans.rawValue)
        #expect(plans.count == 1)
        #expect(plan.id == planID)
        #expect(plan.name == "Writing")
        #expect(plan.focusMinutes == 60)
        #expect(plan.shortBreakMinutes == 5)
        #expect(plan.longBreakMinutes == 20)
        #expect(plan.rounds == PomodoroPlan.roundRange.upperBound)
        #expect(defaults.bool(forKey: SyncedPreferenceService.migrationKey))
    }

    @Test @MainActor
    func payloadAboveMaximumByteCountIsRejectedAndMigrationCompletes() throws {
        let defaults = try makeDefaults()
        defer { clear(defaults) }
        let oversizedName = String(repeating: "x", count: PreferenceJSON.maximumPayloadByteCount)
        defaults.set(
            "[{\"name\":\"\(oversizedName)\"}]",
            forKey: AppPreferenceKey.pomodoroPlans.rawValue
        )

        let context = try makeTestContext()
        try SyncedPreferenceService.migrateLegacyPreferencesIfNeeded(
            context: context,
            defaults: defaults,
            deviceID: "test"
        )

        #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).isEmpty)
        #expect(defaults.bool(forKey: SyncedPreferenceService.migrationKey))
    }

    @Test @MainActor
    func payloadAboveMaximumPlanCountIsRejectedBeforeImport() throws {
        let defaults = try makeDefaults()
        defer { clear(defaults) }
        let records = Array(
            repeating: "{}",
            count: AppPreferenceValueSanitizer.maximumPomodoroPlanCount + 1
        )
        defaults.set(
            "[\(records.joined(separator: ","))]",
            forKey: AppPreferenceKey.pomodoroPlans.rawValue
        )

        let context = try makeTestContext()
        try SyncedPreferenceService.migrateLegacyPreferencesIfNeeded(
            context: context,
            defaults: defaults,
            deviceID: "test"
        )

        #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).isEmpty)
        #expect(defaults.bool(forKey: SyncedPreferenceService.migrationKey))
    }

    @Test @MainActor
    func malformedPayloadIsRejectedAndMigrationCompletes() throws {
        let defaults = try makeDefaults()
        defer { clear(defaults) }
        defaults.set("[{", forKey: AppPreferenceKey.pomodoroPlans.rawValue)

        let context = try makeTestContext()
        try SyncedPreferenceService.migrateLegacyPreferencesIfNeeded(
            context: context,
            defaults: defaults,
            deviceID: "test"
        )

        #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).isEmpty)
        #expect(defaults.bool(forKey: SyncedPreferenceService.migrationKey))
    }

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "LegacyPomodoroPlanMigrationTests-\(UUID().uuidString)"))
    }

    private func clear(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: AppPreferenceKey.pomodoroPlans.rawValue)
        defaults.removeObject(forKey: SyncedPreferenceService.migrationKey)
    }
}
