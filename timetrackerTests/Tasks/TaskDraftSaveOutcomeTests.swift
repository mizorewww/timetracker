import Foundation
import SwiftData
import Testing
@testable import timetracker

@MainActor
struct TaskDraftSaveOutcomeTests {
    @Test
    func reparentingReportsTheOldAndNewAncestorsAndTheMovedSubtree() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "seed")
        let oldRoot = try repository.createTask(title: "Old root", parentID: nil)
        let oldParent = try repository.createTask(title: "Old parent", parentID: oldRoot.id)
        let newRoot = try repository.createTask(title: "New root", parentID: nil)
        let newParent = try repository.createTask(title: "New parent", parentID: newRoot.id)
        let moved = try repository.createTask(title: "Moved", parentID: oldParent.id)
        let child = try repository.createTask(title: "Child", parentID: moved.id)
        let unrelated = try repository.createTask(title: "Unrelated", parentID: nil)
        let store = makeTestStore()
        try store.configureIfNeeded(context: context)

        var draft = try store.editorDraft(for: #require(store.task(for: moved.id)))
        draft.parentID = newParent.id
        let outcome = try StoreScopedTaskLifecycleCommandCoordinator(
            session: .testHarness(context.container)
        ).save(draft: draft, sanitizedTitle: "Moved")

        let ancestors: Set<UUID> = [oldRoot.id, oldParent.id, newRoot.id, newParent.id]
        let subtree: Set<UUID> = [moved.id, child.id]
        #expect(outcome.relatedTaskIDs == ancestors.union(subtree))
        #expect(outcome.checklistAncestorIDs == ancestors)
        #expect(outcome.relatedTaskIDs.contains(unrelated.id) == false)
    }
}
