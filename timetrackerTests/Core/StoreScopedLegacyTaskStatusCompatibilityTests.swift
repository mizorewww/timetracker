import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
/// Exercises stale-store admission against inert legacy raw values and archive.
struct StoreScopedLegacyTaskStatusCompatibilityTests {
    @Test
    func staleSceneTreatsLegacyCompletedAncestorChainAsOrdinaryWork() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let parent = try makeTask("Parent", parentID: nil, repository: repository)
        let child = try makeTask("Child", parentID: parent.id, repository: repository)
        let grandchild = try makeTask("Grandchild", parentID: child.id, repository: repository)
        parent.statusRaw = LegacyTaskStatusRaw.completed
        child.statusRaw = LegacyTaskStatusRaw.planned
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.isTaskAvailableForTracking(grandchild))

        let segmentID = try makeTestSystemActionCommandHandler().startTimer(
            taskID: grandchild.id,
            context: ModelContext(context.container)
        )

        #expect(segmentID != nil)
        let fresh = freshRepository(context.container)
        #expect(try fresh.task(id: parent.id)?.statusRaw == LegacyTaskStatusRaw.completed)
        #expect(try fresh.task(id: child.id)?.statusRaw == LegacyTaskStatusRaw.planned)
        #expect(store.isTaskAvailableForTracking(grandchild))
    }

    @Test
    func legacyCompletedDestinationAcceptsAReparentedTask() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let oldParent = try makeTask("Old", parentID: nil, repository: repository)
        let destination = try makeTask("Imported destination", parentID: nil, repository: repository)
        let child = try makeTask("Child", parentID: oldParent.id, repository: repository)
        destination.statusRaw = LegacyTaskStatusRaw.completed
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var draft = store.editorDraft(for: try #require(store.task(for: child.id)))
        draft.parentID = destination.id

        #expect(store.saveTaskDraft(draft))
        let fresh = freshRepository(context.container)
        #expect(try fresh.task(id: child.id)?.parentID == destination.id)
        #expect(
            try fresh.task(id: destination.id)?.statusRaw ==
                LegacyTaskStatusRaw.completed
        )
    }

    @Test
    func staleTimerAdmissionStillRejectsAnArchivedAncestor() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let parent = try makeTask("Parent", parentID: nil, repository: repository)
        let child = try makeTask("Child", parentID: parent.id, repository: repository)

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        try freshRepository(context.container, deviceID: "sibling")
            .archiveTask(taskID: parent.id)

        #expect(throws: SystemActionCommandError.taskNotFound) {
            try makeTestSystemActionCommandHandler().startTimer(
                taskID: child.id,
                context: context
            )
        }
        #expect(
            try SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
                .activeSegments()
                .isEmpty
        )
        #expect(store.task(for: child.id) != nil)
    }

    private func makeTask(
        _ title: String,
        parentID: UUID?,
        repository: SwiftDataTaskRepository
    ) throws -> TaskNode {
        try repository.createTask(
            title: title,
            parentID: parentID,
            colorHex: nil,
            iconName: nil
        )
    }

    private func freshRepository(
        _ container: ModelContainer,
        deviceID: String = "test"
    ) -> SwiftDataTaskRepository {
        SwiftDataTaskRepository(
            context: ModelContext(container),
            deviceID: deviceID
        )
    }
}
