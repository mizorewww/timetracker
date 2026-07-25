import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct TaskEditorSaveRecoveryTests {
    @Test
    func typedStaleResultCanReloadAndSaveAgainstTheLatestBaseline() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "seed")
            .createTask(
                title: "Original",
                parentID: nil,
                colorHex: nil,
                iconName: nil
            )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var staleDraft = try store.editorDraft(for: #require(store.task(for: task.id)))
        let staleMutationID = try #require(staleDraft.baseline?.taskMutationID)

        let siblingContext = ModelContext(context.container)
        let siblingRepository = SwiftDataTaskRepository(
            context: siblingContext,
            deviceID: "sibling"
        )
        let siblingTask = try #require(try siblingRepository.task(id: task.id))
        siblingTask.statusRaw = LegacyTaskStatusRaw.completed
        try siblingRepository.updateTask(
            taskID: siblingTask.id,
            title: "Sibling edit",
            parentID: siblingTask.parentID,
            categoryID: nil,
            colorHex: siblingTask.colorHex,
            iconName: siblingTask.iconName,
            notes: siblingTask.notes,
            estimatedSeconds: siblingTask.estimatedSeconds,
            dueAt: siblingTask.dueAt
        )
        staleDraft.title = "Must not overwrite"

        #expect(store.saveTaskDraftResult(staleDraft) == .stale)
        #expect(store.errorMessage == nil)
        let refreshedTask = try #require(store.task(for: task.id))
        var latestDraft = store.editorDraft(for: refreshedTask)
        #expect(refreshedTask.title == "Sibling edit")
        #expect(refreshedTask.statusRaw == LegacyTaskStatusRaw.completed)
        #expect(latestDraft.baseline?.taskMutationID != staleMutationID)

        latestDraft.title = "Saved after reload"
        #expect(
            store.saveTaskDraftResult(latestDraft) ==
                .saved(taskID: task.id)
        )
        let persisted = try #require(
            try SwiftDataTaskRepository(
                context: ModelContext(context.container),
                deviceID: "fresh"
            ).task(id: task.id)
        )
        #expect(persisted.title == "Saved after reload")
        #expect(persisted.statusRaw == LegacyTaskStatusRaw.completed)
    }

    @Test
    func recoveryCopySavesNewIdentitiesWithoutMutatingTheOriginalTask() throws {
        let context = try makeTestContext()
        let original = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: "Original",
            parentID: nil,
            colorHex: "1677FF",
            iconName: "checkmark.circle"
        )
        try ChecklistDraftService().save(
            drafts: [
                ChecklistEditorDraft(
                    title: "Original item",
                    iconName: "book",
                    colorHex: "16A34A"
                ),
            ],
            taskID: original.id,
            context: context,
            deviceID: "seed"
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var edited = try store.editorDraft(
            for: #require(store.task(for: original.id))
        )
        let originalItemID = try #require(
            edited.checklistItems.first?.existingID
        )
        #expect(edited.baseline != nil)
        #expect(edited.taskID == original.id)
        edited.title = "Recovered copy"
        edited.notes = "Preserved notes"
        edited.checklistItems[0].title = "Recovered item"
        let copy = edited.copyAsNew(parentID: nil, categoryID: nil)
        #expect(copy.baseline == nil)
        #expect(copy.taskID == nil)
        #expect(copy.id != edited.id)
        #expect(copy.checklistItems[0].existingID == nil)
        #expect(copy.checklistItems[0].id != edited.checklistItems[0].id)

        let recoveryTaskID = edited.id
        let savedTaskID: UUID
        switch store.saveRecoveredTaskDraftResult(
            copy,
            proposedTaskID: recoveryTaskID
        ) {
        case let .saved(taskID):
            savedTaskID = taskID
        case .stale, .failed:
            Issue.record("Recovery copy should save as a new task")
            return
        }

        #expect(savedTaskID != original.id)
        #expect(savedTaskID == recoveryTaskID)
        #expect(store.task(for: original.id)?.title == "Original")
        #expect(store.task(for: savedTaskID)?.title == "Recovered copy")
        #expect(store.task(for: savedTaskID)?.notes == "Preserved notes")
        let originalItems = store.checklistItems(for: original.id)
        let recoveredItems = store.checklistItems(for: savedTaskID)
        #expect(originalItems.map(\.id) == [originalItemID])
        #expect(originalItems.map(\.title) == ["Original item"])
        #expect(recoveredItems.count == 1)
        #expect(recoveredItems[0].id != originalItemID)
        #expect(recoveredItems[0].title == "Recovered item")
        #expect(
            store.checklistVisualByItemID[recoveredItems[0].id]?.iconName ==
                "book"
        )
        #expect(
            store.checklistVisualByItemID[recoveredItems[0].id]?.colorHex ==
                "16A34A"
        )

        let relaunchedStore = makeTestStore()
        relaunchedStore.configureIfNeeded(
            context: ModelContext(context.container)
        )
        #expect(
            relaunchedStore.saveRecoveredTaskDraftResult(
                copy,
                proposedTaskID: recoveryTaskID
            ) == .saved(taskID: recoveryTaskID)
        )
        let verificationContext = ModelContext(context.container)
        let expectedTaskID = recoveryTaskID
        #expect(
            try verificationContext.fetch(
                FetchDescriptor<TaskNode>(
                    predicate: #Predicate {
                        $0.id == expectedTaskID
                    }
                )
            ).count == 1
        )
    }

    @Test
    func archivedRecoverySourceRestoresItsOriginalHierarchy() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "recovery-restore"
        )
        let root = try repository.createTask(
            title: "Archived root",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try repository.createTask(
            title: "Preserved child",
            parentID: root.id,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        #expect(store.archiveSelectedTask(taskID: root.id))
        #expect(store.task(for: child.id) != nil)
        #expect(store.isTaskDetailRouteValid(child.id) == false)

        #expect(
            store.restoreArchivedHierarchyForRecovery(taskID: child.id)
        )
        #expect(store.isTaskDetailRouteValid(root.id))
        #expect(store.isTaskDetailRouteValid(child.id))
    }

    @Test
    func savedRecoveryCopyStillRequiresCleanupAfterTheSourceReturns() {
        let savedCopyTaskID = UUID()

        #expect(
            TaskDraftRecoveryPresentation.isRequired(
                reason: nil,
                savedCopyTaskID: savedCopyTaskID
            )
        )
        #expect(
            TaskDraftRecoveryPresentation.isRequired(
                reason: .sourceChanged,
                savedCopyTaskID: nil
            )
        )
        #expect(
            TaskDraftRecoveryPresentation.isRequired(
                reason: nil,
                savedCopyTaskID: nil
            ) == false
        )
    }
}
