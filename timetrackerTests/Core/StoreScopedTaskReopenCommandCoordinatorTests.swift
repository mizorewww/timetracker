import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedTaskReopenCommandCoordinatorTests {
    @Test
    func staleSceneReopensCanonicalBlockerChain() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let parent = try makeTask("Parent", parentID: nil, repository: repository)
        let child = try makeTask("Child", parentID: parent.id, repository: repository)
        let grandchild = try makeTask("Grandchild", parentID: child.id, repository: repository)
        try repository.setTaskStatus(taskID: parent.id, status: .completed)

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.completedWorkBlockers(for: grandchild).map(\.id) == [parent.id])

        try freshRepository(context.container, deviceID: "sibling")
            .setTaskStatus(taskID: child.id, status: .completed)

        #expect(store.reopenTaskForWork(grandchild.id))
        let fresh = freshRepository(context.container)
        #expect(try fresh.task(id: parent.id)?.status == .active)
        #expect(try fresh.task(id: child.id)?.status == .active)
        #expect(store.isTaskAvailableForTracking(grandchild))
    }

    @Test
    func reparentedTargetDoesNotReopenItsOldAncestor() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let oldParent = try makeTask("Old", parentID: nil, repository: repository)
        let newParent = try makeTask("New", parentID: nil, repository: repository)
        let child = try makeTask("Child", parentID: oldParent.id, repository: repository)
        try repository.setTaskStatus(taskID: oldParent.id, status: .completed)

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.completedWorkBlockers(for: child).map(\.id) == [oldParent.id])

        let siblingRepository = freshRepository(context.container, deviceID: "sibling")
        try siblingRepository.moveTask(
            taskID: child.id,
            newParentID: newParent.id,
            sortOrder: 10
        )
        try siblingRepository.setTaskStatus(taskID: newParent.id, status: .completed)

        #expect(store.reopenTaskForWork(child.id))
        let fresh = freshRepository(context.container)
        #expect(try fresh.task(id: oldParent.id)?.status == .completed)
        #expect(try fresh.task(id: newParent.id)?.status == .active)
        #expect(try fresh.task(id: child.id)?.parentID == newParent.id)
    }

    @Test
    func deletedTargetCannotReopenStaleAncestor() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let parent = try makeTask("Parent", parentID: nil, repository: repository)
        let child = try makeTask("Child", parentID: parent.id, repository: repository)
        try repository.setTaskStatus(taskID: parent.id, status: .completed)

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        try freshRepository(context.container, deviceID: "sibling")
            .softDeleteTask(taskID: child.id)

        #expect(store.reopenTaskForWork(child.id) == false)
        #expect(
            try freshRepository(context.container).task(id: parent.id)?.status == .completed
        )
        #expect(store.task(for: child.id) == nil)
        #expect(store.errorMessage == AppStrings.localized("systemAction.error.taskNotFound"))
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
