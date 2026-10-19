import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct TaskLifecycleAndCategoryCommandTests {
    @Test
    func archivingABranchWithARunningTimerIsRefusedUntilItStops() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "seed")
        let parent = try repository.createTask(title: "Project", parentID: nil)
        let child = try repository.createTask(title: "Subtask", parentID: parent.id)
        let timer = StoreScopedTimerCommandCoordinator(session: .testHarness(context.container))
        let lifecycle = StoreScopedTaskLifecycleCommandCoordinator(session: .testHarness(context.container))
        let started = try timer.start(taskID: child.id)

        #expect(throws: TaskLifecycleMutationError.activeWorkMustStop) {
            try lifecycle.archive(taskID: parent.id)
        }
        #expect(try task(parent.id, in: context.container).archivedAt == nil)

        _ = try timer.stop(segmentID: #require(started.subjectSegmentID))
        let archived = try lifecycle.archive(taskID: parent.id)

        #expect(archived.didMutate)
        #expect(try task(parent.id, in: context.container).archivedAt != nil)
    }

    @Test
    func archiveThenRestoreMakesTheTaskTrackableAgain() throws {
        let context = try makeTestContext()
        let created = try SwiftDataTaskRepository(context: context, deviceID: "seed")
            .createTask(title: "Side project", parentID: nil)
        let lifecycle = StoreScopedTaskLifecycleCommandCoordinator(session: .testHarness(context.container))

        _ = try lifecycle.archive(taskID: created.id)
        #expect(try lifecycle.archive(taskID: created.id).didMutate == false)
        _ = try lifecycle.unarchive(taskID: created.id)

        let restored = try task(created.id, in: context.container)
        #expect(restored.archivedAt == nil)
        #expect(restored.deletedAt == nil)
        let started = try StoreScopedTimerCommandCoordinator(session: .testHarness(context.container))
            .start(taskID: created.id)
        #expect(started.subjectSegmentID != nil)
    }

    @Test
    func deletingACategoryRemovesItsAssignmentsButNotItsTasks() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "seed")
        let root = try repository.createTask(title: "Work", parentID: nil)
        let categories = StoreScopedTaskCategoryCommandCoordinator(session: .testHarness(context.container))
        var draft = TaskCategoryEditorDraft()
        draft.title = "Career"
        let categoryID = try categories.save(draft: draft).categoryID
        try repository.setCategoryAssignment(categoryID: categoryID, forRootTaskID: root.id)
        try context.save()

        let category = try #require(
            try ModelContext(context.container).fetch(FetchDescriptor<TaskCategory>()).first
        )
        _ = try categories.delete(baseline: TaskCategoryMutationBaseline(category: category))

        let fresh = ModelContext(context.container)
        #expect(try fresh.fetch(FetchDescriptor<TaskCategory>()).allSatisfy { $0.deletedAt != nil })
        #expect(try fresh.fetch(FetchDescriptor<TaskCategoryAssignment>()).allSatisfy { $0.deletedAt != nil })
        #expect(try task(root.id, in: context.container).deletedAt == nil)
    }

    @Test
    func reorderingWithAStaleCategorySetIsRejected() throws {
        let context = try makeTestContext()
        let categories = StoreScopedTaskCategoryCommandCoordinator(session: .testHarness(context.container))
        var draft = TaskCategoryEditorDraft()
        draft.title = "A"
        let first = try categories.save(draft: draft).categoryID
        draft.title = "B"
        let second = try categories.save(draft: draft).categoryID

        _ = try categories.reorder(orderedCategoryIDs: [second, first])
        #expect(throws: StoreScopedTaskCategoryMutationError.categoryChanged) {
            try categories.reorder(orderedCategoryIDs: [first])
        }

        let ordered = try ModelContext(context.container)
            .fetch(FetchDescriptor<TaskCategory>())
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.id)
        #expect(ordered == [second, first])
    }

    private func task(_ id: UUID, in container: ModelContainer) throws -> TaskNode {
        try #require(
            try ModelContext(container)
                .fetch(FetchDescriptor<TaskNode>(predicate: #Predicate { $0.id == id }))
                .first
        )
    }
}
