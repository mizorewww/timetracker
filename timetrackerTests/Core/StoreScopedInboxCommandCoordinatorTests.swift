import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedInboxCommandCoordinatorTests {
    @Test
    func freshReorderPersistsOneCanonicalOrder() throws {
        let context = try makeTestContext()
        let items = try seedOpenItems(in: context.container)
        let orderedIDs = items.reversed().map(\.id)

        let outcome = try coordinator(container: context.container).reorder(
            baseline: InboxOrderMutationBaseline(items: items),
            orderedItemIDs: orderedIDs
        )

        #expect(outcome.didMutate)
        #expect(outcome.affectedItemIDs == Set(orderedIDs))
        #expect(try openItems(in: context.container).map(\.id) == orderedIDs)
    }

    @Test
    func staleReorderCannotOverwriteANewerItemMutation() throws {
        let context = try makeTestContext()
        let items = try seedOpenItems(in: context.container)
        let baseline = InboxOrderMutationBaseline(items: items)
        let siblingContext = ModelContext(context.container)
        let siblingItem = try #require(
            try siblingContext.fetch(FetchDescriptor<InboxItem>())
                .first(where: { $0.id == items[0].id })
        )
        try InboxCommandHandler().toggle(
            siblingItem,
            context: siblingContext,
            deviceID: "sibling"
        )

        #expect(throws: StoreScopedInboxMutationError.inboxChanged) {
            try coordinator(container: context.container).reorder(
                baseline: baseline,
                orderedItemIDs: items.reversed().map(\.id)
            )
        }
        let persisted = try allVisibleItems(in: context.container)
        #expect(persisted.first(where: { $0.id == items[0].id })?.isCompleted == true)
        #expect(persisted.first(where: { $0.id == items[0].id })?.deviceID == "sibling")
    }

    @Test
    func staleReorderCannotDropAConcurrentlyAddedItem() throws {
        let context = try makeTestContext()
        let items = try seedOpenItems(in: context.container)
        let baseline = InboxOrderMutationBaseline(items: items)
        let siblingContext = ModelContext(context.container)
        let siblingItems = try allVisibleItems(in: context.container)
        _ = try InboxCommandHandler().add(
            title: "Third",
            existingItems: siblingItems,
            context: siblingContext,
            deviceID: "sibling"
        )

        #expect(throws: StoreScopedInboxMutationError.inboxChanged) {
            try coordinator(container: context.container).reorder(
                baseline: baseline,
                orderedItemIDs: items.reversed().map(\.id)
            )
        }
        #expect(try openItems(in: context.container).map(\.title) == ["First", "Second", "Third"])
    }

    @Test
    func baselineAlsoRejectsAnOrderChangeWithoutARevisionUpdate() throws {
        let context = try makeTestContext()
        let items = try seedOpenItems(in: context.container)
        let baseline = InboxOrderMutationBaseline(items: items)
        let siblingContext = ModelContext(context.container)
        let siblingItems = try siblingContext.fetch(FetchDescriptor<InboxItem>())
        let first = try #require(siblingItems.first(where: { $0.id == items[0].id }))
        let second = try #require(siblingItems.first(where: { $0.id == items[1].id }))
        first.sortOrder = 20
        second.sortOrder = 10
        try siblingContext.save()

        #expect(throws: StoreScopedInboxMutationError.inboxChanged) {
            try coordinator(container: context.container).reorder(
                baseline: baseline,
                orderedItemIDs: items.reversed().map(\.id)
            )
        }
        #expect(try openItems(in: context.container).map(\.id) == [items[1].id, items[0].id])
    }

    @Test
    func staleItemBaselineCannotOverwriteANewerEdit() throws {
        let context = try makeTestContext()
        let item = try #require(try seedOpenItems(in: context.container).first)
        let baseline = InboxItemMutationBaseline(item: item)
        let siblingContext = ModelContext(context.container)
        let siblingItem = try #require(
            try siblingContext.fetch(FetchDescriptor<InboxItem>())
                .first(where: { $0.id == item.id })
        )
        try InboxCommandHandler().updateTitle(
            siblingItem,
            title: "Edited in another scene",
            context: siblingContext,
            deviceID: "sibling"
        )

        #expect(throws: StoreScopedInboxMutationError.inboxChanged) {
            try coordinator(container: context.container).toggle(baseline: baseline)
        }

        let persisted = try #require(
            try allVisibleItems(in: context.container).first(where: { $0.id == item.id })
        )
        #expect(persisted.title == "Edited in another scene")
        #expect(persisted.isCompleted == false)
        #expect(persisted.deviceID == "sibling")
    }

    @Test
    func facadeRefreshesAfterRejectingAStaleDrag() throws {
        let context = try makeTestContext()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.addInboxItem(title: "First"))
        #expect(store.addInboxItem(title: "Second"))
        let staleItems = store.openInboxItems
        let siblingContext = ModelContext(context.container)
        let siblingItem = try #require(
            try siblingContext.fetch(FetchDescriptor<InboxItem>())
                .first(where: { $0.id == staleItems[0].id })
        )
        try InboxCommandHandler().toggle(
            siblingItem,
            context: siblingContext,
            deviceID: "sibling"
        )

        #expect(
            store.reorderInboxItems(
                sourceOffsets: IndexSet(integer: 0),
                destination: 2
            ) == false
        )
        #expect(store.errorMessage == AppStrings.localized("inbox.error.changed"))
        #expect(store.openInboxItems.map(\.title) == ["Second"])
        #expect(store.completedInboxItems.map(\.title) == ["First"])
    }

    @Test
    func facadeRefreshesAfterRejectingAStaleTitleEdit() throws {
        let context = try makeTestContext()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.addInboxItem(title: "First"))
        let staleItem = try #require(store.openInboxItems.first)
        let siblingContext = ModelContext(context.container)
        let siblingItem = try #require(
            try siblingContext.fetch(FetchDescriptor<InboxItem>())
                .first(where: { $0.id == staleItem.id })
        )
        try InboxCommandHandler().updateTitle(
            siblingItem,
            title: "Edited in another scene",
            context: siblingContext,
            deviceID: "sibling"
        )

        store.updateInboxItemTitle(staleItem, title: "Overwritten title")

        #expect(store.errorMessage == AppStrings.localized("inbox.error.changed"))
        #expect(store.openInboxItems.map(\.title) == ["Edited in another scene"])
    }

    private func coordinator(container: ModelContainer) -> StoreScopedInboxCommandCoordinator {
        StoreScopedInboxCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "test"
        )
    }

    private func seedOpenItems(in container: ModelContainer) throws -> [InboxItem] {
        let context = ModelContext(container)
        let handler = InboxCommandHandler()
        let first = try #require(
            try handler.add(
                title: "First",
                existingItems: [],
                context: context,
                deviceID: "seed"
            )
        )
        _ = try #require(
            try handler.add(
                title: "Second",
                existingItems: [first],
                context: context,
                deviceID: "seed"
            )
        )
        return try openItems(in: container)
    }

    private func openItems(in container: ModelContainer) throws -> [InboxItem] {
        try allVisibleItems(in: container)
            .filter { $0.isCompleted == false }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func allVisibleItems(in container: ModelContainer) throws -> [InboxItem] {
        InboxSuggestionIdentityService().visibleLogicalItems(
            from: try ModelContext(container).fetch(FetchDescriptor<InboxItem>())
        )
    }
}
