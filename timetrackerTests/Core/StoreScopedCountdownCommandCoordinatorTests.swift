import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedCountdownCommandCoordinatorTests {
    @Test
    func staleBaselineCannotOverwriteANewerCountdownMutation() throws {
        let context = try makeTestContext()
        let event = CountdownEvent(
            title: "Original",
            date: Date(timeIntervalSince1970: 10_000),
            deviceID: "original"
        )
        context.insert(event)
        try context.save()
        let baseline = CountdownMutationBaseline(event: event)
        let coordinator = StoreScopedCountdownCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "sibling",
            nowProvider: { Date(timeIntervalSince1970: 20_000) }
        )

        try coordinator.update(
            baseline: baseline,
            title: "Sibling winner",
            date: nil
        )

        #expect(throws: StoreScopedCountdownMutationError.eventChanged) {
            try coordinator.update(
                baseline: baseline,
                title: "Stale overwrite",
                date: nil
            )
        }
        let winner = try #require(
            ModelContext(context.container)
                .fetch(FetchDescriptor<CountdownEvent>())
                .visibleDeduplicatedByID()
                .first
        )
        #expect(winner.title == "Sibling winner")
        #expect(winner.deviceID == "sibling")
    }

    @Test
    func staleSceneCannotResurrectADeletedCountdown() throws {
        let context = try makeTestContext()
        let event = CountdownEvent(
            title: "Delete in sibling",
            date: Date(timeIntervalSince1970: 10_000),
            deviceID: "original"
        )
        context.insert(event)
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let staleEvent = try #require(store.countdownEvents.first)
        try StoreScopedCountdownCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "sibling",
            nowProvider: { Date(timeIntervalSince1970: 20_000) }
        ).delete(baseline: CountdownMutationBaseline(event: staleEvent))

        #expect(store.updateCountdownEvent(staleEvent, title: "Resurrect") == false)
        #expect(store.errorMessage == AppStrings.localized("settings.countdown.error.unavailable"))
        #expect(store.countdownEvents.isEmpty)
        let persisted = try ModelContext(context.container)
            .fetch(FetchDescriptor<CountdownEvent>())
            .deduplicatedByID()
        #expect(persisted.count == 1)
        #expect(persisted[0].deletedAt != nil)
        #expect(persisted[0].title == "Delete in sibling")
        #expect(persisted[0].deviceID == "sibling")
    }
}
