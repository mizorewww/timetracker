import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedCountdownCommandCoordinatorTests {
    @Test
    func addPersistsADefaultEventVisibleFromAFreshContext() throws {
        let context = try makeTestContext()
        let coordinator = makeCoordinator(container: context.container)

        try coordinator.add()

        let events = try allEvents(in: context.container)
        let event = try #require(events.only)
        #expect(event.title.isEmpty == false)
        #expect(event.date.timeIntervalSinceNow > 6 * 24 * 60 * 60)
        #expect(event.deviceID == "test")
        #expect(event.deletedAt == nil)
    }

    @Test
    func updatePersistsNormalizedTitleAndDateWithFreshMutationMetadata() throws {
        let context = try makeTestContext()
        let coordinator = makeCoordinator(container: context.container)
        try coordinator.add()
        let added = try #require(try allEvents(in: context.container).only)
        let baseline = CountdownMutationBaseline(event: added)
        let now = Date(timeIntervalSinceReferenceDate: 500_000)
        let newDate = Date(timeIntervalSinceReferenceDate: 900_000)

        try makeCoordinator(container: context.container, now: now)
            .update(baseline: baseline, title: "  Launch day  ", date: newDate)

        let persisted = try #require(try allEvents(in: context.container).only)
        #expect(persisted.title == "Launch day")
        #expect(persisted.date == newDate)
        #expect(persisted.updatedAt == now)
        #expect(persisted.clientMutationID != added.clientMutationID)
    }

    @Test
    func updateRejectsAnEmptyTitleWithoutTouchingThePersistedEvent() throws {
        let context = try makeTestContext()
        let coordinator = makeCoordinator(container: context.container)
        try coordinator.add()
        let added = try #require(try allEvents(in: context.container).only)
        let baseline = CountdownMutationBaseline(event: added)

        #expect(throws: CountdownTitleValidationError.empty) {
            try coordinator.update(baseline: baseline, title: "   ", date: nil)
        }

        let persisted = try #require(try allEvents(in: context.container).only)
        #expect(persisted.title == added.title)
        #expect(persisted.updatedAt == added.updatedAt)
        #expect(persisted.clientMutationID == added.clientMutationID)
    }

    @Test
    func staleBaselineCannotOverwriteANewerMutationFromAnotherScene() throws {
        let context = try makeTestContext()
        let coordinator = makeCoordinator(container: context.container)
        try coordinator.add()
        let added = try #require(try allEvents(in: context.container).only)
        let staleBaseline = CountdownMutationBaseline(event: added)
        let sibling = StoreScopedCountdownCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "sibling",
            nowProvider: { Date(timeIntervalSinceReferenceDate: 500_000) }
        )
        try sibling.update(
            baseline: staleBaseline,
            title: "Sibling edit",
            date: nil
        )

        #expect(throws: StoreScopedCountdownMutationError.eventChanged) {
            try coordinator.update(
                baseline: staleBaseline,
                title: "Stale overwrite",
                date: nil
            )
        }

        let persisted = try #require(try allEvents(in: context.container).only)
        #expect(persisted.title == "Sibling edit")
        #expect(persisted.deviceID == "sibling")
    }

    @Test
    func mutationAgainstATombstonedEventFailsAsUnavailable() throws {
        let context = try makeTestContext()
        let coordinator = makeCoordinator(container: context.container)
        try coordinator.add()
        let added = try #require(try allEvents(in: context.container).only)
        let baseline = CountdownMutationBaseline(event: added)
        let tombstonedAt = Date(timeIntervalSinceReferenceDate: 500_000)

        let siblingContext = ModelContext(context.container)
        let siblingEvent = try #require(
            try siblingContext.fetch(FetchDescriptor<CountdownEvent>())
                .first { $0.id == added.id }
        )
        siblingEvent.deletedAt = tombstonedAt
        siblingEvent.updatedAt = tombstonedAt
        siblingEvent.clientMutationID = UUID()
        try siblingContext.save()

        #expect(throws: StoreScopedCountdownMutationError.eventUnavailable) {
            try coordinator.update(baseline: baseline, title: "Revive", date: nil)
        }
        #expect(throws: StoreScopedCountdownMutationError.eventUnavailable) {
            try coordinator.delete(baseline: baseline)
        }

        let persisted = try #require(try allEvents(in: context.container).only)
        #expect(persisted.deletedAt == tombstonedAt)
        #expect(persisted.title == added.title)
    }

    @Test
    func deletePersistsATombstoneAndRejectsASecondDelete() throws {
        let context = try makeTestContext()
        let coordinator = makeCoordinator(container: context.container)
        try coordinator.add()
        let added = try #require(try allEvents(in: context.container).only)
        let baseline = CountdownMutationBaseline(event: added)
        let now = Date(timeIntervalSinceReferenceDate: 500_000)

        try makeCoordinator(container: context.container, now: now)
            .delete(baseline: baseline)

        let persisted = try #require(try allEvents(in: context.container).only)
        #expect(persisted.deletedAt == now)
        #expect(persisted.updatedAt == now)
        #expect(persisted.clientMutationID != added.clientMutationID)

        #expect(throws: StoreScopedCountdownMutationError.eventUnavailable) {
            try coordinator.delete(baseline: baseline)
        }
    }

    private func makeCoordinator(
        container: ModelContainer,
        now: Date = Date(timeIntervalSinceReferenceDate: 100_000)
    ) -> StoreScopedCountdownCommandCoordinator {
        StoreScopedCountdownCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "test",
            nowProvider: { now }
        )
    }

    private func allEvents(in container: ModelContainer) throws -> [CountdownEvent] {
        try ModelContext(container)
            .fetch(FetchDescriptor<CountdownEvent>())
            .deduplicatedByID()
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
