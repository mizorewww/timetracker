import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedInboxCommandCoordinatorTests {
    @Test
    func retriedExternalCaptureCreatesOneItem() throws {
        let context = try makeTestContext()
        let inbox = coordinator(context.container)
        let key = try ExternalCommandKey(origin: "shortcuts", id: UUID())
        let command = InboxCaptureCommand(title: "Call the bank", externalCommandKey: key)

        let first = try inbox.add(command: command)
        let retry = try inbox.add(command: command)

        #expect(first.didMutate)
        #expect(retry.didMutate == false)
        #expect(retry.affectedItemIDs == first.affectedItemIDs)
        #expect(try openItems(context.container).map(\.title) == ["Call the bank"])
        #expect(try ModelContext(context.container).fetch(FetchDescriptor<InboxCaptureReceipt>()).count == 1)
    }

    @Test
    func reusedExternalKeyWithDifferentTextIsRejected() throws {
        let context = try makeTestContext()
        let inbox = coordinator(context.container)
        let key = try ExternalCommandKey(origin: "shortcuts", id: UUID())
        _ = try inbox.add(command: InboxCaptureCommand(title: "First", externalCommandKey: key))

        #expect(throws: StoreScopedInboxMutationError.externalCommandPayloadChanged) {
            try inbox.add(command: InboxCaptureCommand(title: "Second", externalCommandKey: key))
        }
        #expect(try openItems(context.container).map(\.title) == ["First"])
    }

    @Test
    func routingToChecklistCreatesTheItemAndRemovesTheInboxRow() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "seed")
            .createTask(title: "Errands", parentID: nil)
        let inbox = coordinator(context.container)
        _ = try inbox.add(title: "Buy stamps")
        let item = try #require(try openItems(context.container).first)

        let outcome = try inbox.route(
            baseline: InboxManualRouteBaseline(item: item),
            destination: .checklist(taskID: task.id)
        )

        #expect(outcome.didMutate)
        #expect(try openItems(context.container).isEmpty)
        let checklist = try ModelContext(context.container)
            .fetch(FetchDescriptor<ChecklistItem>())
            .filter { $0.deletedAt == nil }
        #expect(checklist.map(\.title) == ["Buy stamps"])
        #expect(checklist.first?.taskID == task.id)
    }

    @Test
    func routingToChildTaskCreatesItUnderTheParent() throws {
        let context = try makeTestContext()
        let parent = try SwiftDataTaskRepository(context: context, deviceID: "seed")
            .createTask(title: "Home", parentID: nil)
        let inbox = coordinator(context.container)
        _ = try inbox.add(title: "Fix the shelf")
        let item = try #require(try openItems(context.container).first)

        _ = try inbox.route(
            baseline: InboxManualRouteBaseline(item: item),
            destination: .childTask(parentTaskID: parent.id)
        )

        let tasks = try ModelContext(context.container).fetch(FetchDescriptor<TaskNode>())
        let child = try #require(tasks.first { $0.title == "Fix the shelf" })
        #expect(child.parentID == parent.id)
        #expect(try openItems(context.container).isEmpty)
    }

    @Test
    func routingAnItemDeletedElsewhereFails() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "seed")
            .createTask(title: "Errands", parentID: nil)
        let scene = coordinator(context.container)
        _ = try scene.add(title: "Stale")
        let item = try #require(try openItems(context.container).first)
        let baseline = InboxManualRouteBaseline(item: item)
        _ = try coordinator(context.container, deviceID: "sibling").delete(itemID: item.id)

        #expect(throws: StoreScopedInboxMutationError.inboxChanged) {
            try scene.route(baseline: baseline, destination: .checklist(taskID: task.id))
        }
        #expect(try ModelContext(context.container).fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
    }

    @Test
    func editsPersistThroughTheCoordinator() throws {
        let context = try makeTestContext()
        let inbox = coordinator(context.container)
        _ = try inbox.add(title: "A")
        _ = try inbox.add(title: "B")
        let items = try openItems(context.container)
        let a = try #require(items.first { $0.title == "A" })
        let b = try #require(items.first { $0.title == "B" })

        _ = try inbox.reorder(orderedItemIDs: [b.id, a.id])
        _ = try inbox.updateTitle(itemID: a.id, title: "A renamed")
        _ = try inbox.toggle(itemID: b.id)
        _ = try inbox.delete(itemID: a.id)

        let rows = try ModelContext(context.container).fetch(FetchDescriptor<InboxItem>())
        #expect(rows.first { $0.id == a.id }?.title == "A renamed")
        #expect(rows.first { $0.id == a.id }?.deletedAt != nil)
        #expect(rows.first { $0.id == b.id }?.isCompleted == true)
    }

    private func coordinator(
        _ container: ModelContainer,
        deviceID: String = "scene"
    ) -> StoreScopedInboxCommandCoordinator {
        StoreScopedInboxCommandCoordinator(session: .testHarness(container), deviceID: deviceID)
    }

    private func openItems(_ container: ModelContainer) throws -> [InboxItem] {
        try ModelContext(container)
            .fetch(FetchDescriptor<InboxItem>())
            .filter { $0.deletedAt == nil && $0.isCompleted == false }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}
