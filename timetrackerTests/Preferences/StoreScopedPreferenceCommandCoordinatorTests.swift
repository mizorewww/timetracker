import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedPreferenceCommandCoordinatorTests {
    @Test
    func latestPreferenceWriteUsesTheLockedFreshStoreContext() throws {
        let context = try makeTestContext()
        let key = AppPreferenceKey.defaultFocusMinutes
        try PreferenceCommandHandler().set(
            key: key,
            valueJSON: PreferenceJSON.encode(25),
            context: context
        )

        try PreferenceCommandHandler().set(
            key: key,
            valueJSON: PreferenceJSON.encode(30),
            context: ModelContext(context.container)
        )
        try StoreScopedPreferenceCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness
        ).set(key: key, valueJSON: PreferenceJSON.encode(45))

        let stored = try ModelContext(context.container)
            .fetch(FetchDescriptor<SyncedPreference>())
        let winner = try #require(
            SyncedPreferenceService.latestByKey(stored)[key.rawValue]
        )
        #expect(winner.valueJSON == PreferenceJSON.encode(45))
        #expect(winner.deletedAt == nil)
        #expect(stored.filter { $0 !== winner }.allSatisfy { $0.deletedAt != nil })
    }
}
