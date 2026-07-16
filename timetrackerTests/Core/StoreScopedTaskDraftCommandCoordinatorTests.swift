import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedTaskDraftCommandCoordinatorTests {
    @Test
    func staleSceneDraftCannotCompleteTaskStartedBySiblingContext() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "test").createTask(
            title: "Original title",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var draft = store.editorDraft(for: try #require(store.task(for: task.id)))

        _ = try makeTestSystemActionCommandHandler().startTimerMutation(
            taskID: task.id,
            allowParallelTimers: true,
            container: context.container
        )
        draft.title = "Must not persist"
        draft.status = .completed

        #expect(store.saveTaskDraft(draft) == false)
        let fetched = try freshTaskRepository(context.container).task(id: task.id)
        let persisted = try #require(fetched)
        #expect(persisted.title == "Original title")
        #expect(persisted.status == .active)
        #expect(store.activeSegments.count == 1)
        #expect(store.errorMessage == AppStrings.localized("task.action.complete.stopFirst"))
    }

    @Test
    func staleSceneDraftCannotMoveIntoSiblingCompletedParent() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let originalParent = try repository.createTask(
            title: "Original parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let destinationParent = try repository.createTask(
            title: "Destination parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try repository.createTask(
            title: "Child",
            parentID: originalParent.id,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var draft = store.editorDraft(for: try #require(store.task(for: child.id)))
        #expect(store.trackableTaskIDs.contains(destinationParent.id))

        _ = try StoreScopedTaskLifecycleCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "sibling"
        ).setStatus(.completed, taskID: destinationParent.id)
        draft.parentID = destinationParent.id
        draft.title = "Must not move"

        #expect(store.saveTaskDraft(draft) == false)
        let fetched = try freshTaskRepository(context.container).task(id: child.id)
        let persisted = try #require(fetched)
        #expect(persisted.parentID == originalParent.id)
        #expect(persisted.title == "Child")
        #expect(store.task(for: destinationParent.id)?.status == .completed)
        #expect(store.errorMessage == AppStrings.localized("task.parentUnavailable"))
    }

    @Test
    func metadataEditOnAlreadyCompletedTaskDoesNotReapplyStopGate() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Completed metadata",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        _ = try SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
            .startTask(taskID: task.id, source: .timer)
        try taskRepository.setTaskStatus(taskID: task.id, status: .completed)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var draft = store.editorDraft(for: try #require(store.task(for: task.id)))
        draft.title = "Updated metadata"

        #expect(store.saveTaskDraft(draft))
        let fetched = try freshTaskRepository(context.container).task(id: task.id)
        let persisted = try #require(fetched)
        #expect(persisted.title == "Updated metadata")
        #expect(persisted.status == .completed)
        #expect(store.activeSegments.count == 1)
    }

    @Test
    func staleDraftCannotOverwriteSiblingTaskMutation() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "test").createTask(
            title: "Canonical title",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var draft = store.editorDraft(for: try #require(store.task(for: task.id)))

        _ = try StoreScopedTaskLifecycleCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "sibling"
        ).setStatus(.completed, taskID: task.id)
        draft.title = "Stale title"

        #expect(store.saveTaskDraft(draft) == false)
        let fetched = try freshTaskRepository(context.container).task(id: task.id)
        let persisted = try #require(fetched)
        #expect(persisted.title == "Canonical title")
        #expect(persisted.status == .completed)
        #expect(store.task(for: task.id)?.status == .completed)
        #expect(store.errorMessage == AppStrings.localized("task.editor.staleDraft"))
    }

    @Test
    func staleChecklistDraftDoesNotDeleteSiblingAddedItem() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "test").createTask(
            title: "Checklist owner",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var draft = store.editorDraft(for: try #require(store.task(for: task.id)))

        try ChecklistDraftService().save(
            drafts: [ChecklistEditorDraft(title: "Sibling item")],
            taskID: task.id,
            context: ModelContext(context.container),
            deviceID: "sibling"
        )
        draft.title = "Stale metadata"

        #expect(store.saveTaskDraft(draft) == false)
        let freshContext = ModelContext(context.container)
        let items = try freshContext.fetch(FetchDescriptor<ChecklistItem>())
            .filter { $0.taskID == task.id && $0.deletedAt == nil }
        #expect(items.map(\.title) == ["Sibling item"])
        #expect(store.checklistItems(for: task.id).map(\.title) == ["Sibling item"])
        #expect(store.errorMessage == AppStrings.localized("task.editor.staleDraft"))
    }

    @Test
    func staleChecklistDraftDoesNotResurrectSiblingDeletedItem() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "test").createTask(
            title: "Checklist owner",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        try ChecklistDraftService().save(
            drafts: [ChecklistEditorDraft(title: "Delete elsewhere")],
            taskID: task.id,
            context: context,
            deviceID: "test"
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let draft = store.editorDraft(for: try #require(store.task(for: task.id)))

        try ChecklistDraftService().save(
            drafts: [],
            taskID: task.id,
            context: ModelContext(context.container),
            deviceID: "sibling"
        )

        #expect(store.saveTaskDraft(draft) == false)
        let items = try ModelContext(context.container).fetch(FetchDescriptor<ChecklistItem>())
            .filter { $0.taskID == task.id }
        #expect(items.count == 1)
        #expect(items.first?.deletedAt != nil)
        #expect(store.checklistItems(for: task.id).isEmpty)
        #expect(store.errorMessage == AppStrings.localized("task.editor.staleDraft"))
    }

    @Test
    func staleDraftCannotCreateChecklistOrphansAfterSiblingDeletion() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "test").createTask(
            title: "Soon deleted",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var draft = store.editorDraft(for: try #require(store.task(for: task.id)))
        draft.checklistItems = [ChecklistEditorDraft(title: "Must not orphan")]

        _ = try StoreScopedTaskLifecycleCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "sibling"
        ).delete(taskID: task.id)

        #expect(store.saveTaskDraft(draft) == false)
        let items = try ModelContext(context.container).fetch(FetchDescriptor<ChecklistItem>())
            .filter { $0.taskID == task.id }
        #expect(items.isEmpty)
        #expect(store.task(for: task.id) == nil)
        #expect(store.errorMessage == AppStrings.localized("systemAction.error.taskNotFound"))
    }

    @Test
    func staleDraftCannotOverwriteSiblingCategoryAssignment() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let firstCategory = try repository.createCategory(title: "First", includesInForecast: true)
        let secondCategory = try repository.createCategory(title: "Second", includesInForecast: true)
        let task = try repository.createTask(
            title: "Categorized",
            parentID: nil,
            categoryID: firstCategory.id,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var draft = store.editorDraft(for: try #require(store.task(for: task.id)))

        let siblingContext = ModelContext(context.container)
        let siblingRepository = SwiftDataTaskRepository(
            context: siblingContext,
            deviceID: "sibling"
        )
        try siblingRepository.setCategoryAssignment(
            categoryID: secondCategory.id,
            forRootTaskID: task.id
        )
        try siblingContext.save()
        draft.title = "Stale category edit"

        #expect(store.saveTaskDraft(draft) == false)
        #expect(try siblingRepository.categoryID(forRootTaskID: task.id) == secondCategory.id)
        let refreshedTask = try #require(store.task(for: task.id))
        #expect(store.effectiveCategory(for: refreshedTask)?.id == secondCategory.id)
        #expect(store.errorMessage == AppStrings.localized("task.editor.staleDraft"))
    }

    @Test
    func staleDraftCannotOverwriteSiblingChecklistVisual() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "test").createTask(
            title: "Visual owner",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        try ChecklistDraftService().save(
            drafts: [ChecklistEditorDraft(title: "Visual item")],
            taskID: task.id,
            context: context,
            deviceID: "test"
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var draft = store.editorDraft(for: try #require(store.task(for: task.id)))

        let siblingContext = ModelContext(context.container)
        let visuals = try siblingContext.fetch(FetchDescriptor<ChecklistItemVisual>())
        let visual = try #require(visuals.first)
        visual.iconName = "star.fill"
        visual.updatedAt = Date()
        visual.deviceID = "sibling"
        visual.clientMutationID = UUID()
        try siblingContext.save()
        draft.title = "Stale visual edit"

        #expect(store.saveTaskDraft(draft) == false)
        let freshVisuals = try ModelContext(context.container)
            .fetch(FetchDescriptor<ChecklistItemVisual>())
        #expect(freshVisuals.first?.iconName == "star.fill")
        #expect(store.checklistVisualByItemID[visual.checklistItemID]?.iconName == "star.fill")
        #expect(store.errorMessage == AppStrings.localized("task.editor.staleDraft"))
    }

    private func freshTaskRepository(
        _ container: ModelContainer
    ) -> SwiftDataTaskRepository {
        SwiftDataTaskRepository(
            context: ModelContext(container),
            deviceID: "test"
        )
    }
}
