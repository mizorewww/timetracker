import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct TaskEditorSessionTests {
    @Test
    func dirtyDraftRequiresConfirmationAndDiscardRestoresTheBaseline() {
        let store = makeTestStore()
        let initialDraft = TaskEditorDraft(parentID: nil)
        let session = TaskEditorSession(
            store: store,
            initialDraft: initialDraft
        )
        var cleanCancellationCount = 0

        session.requestCancel {
            cleanCancellationCount += 1
        }
        #expect(cleanCancellationCount == 1)
        #expect(session.isDiscardConfirmationPresented == false)

        session.draft.title = "Changed"
        session.requestCancel {
            cleanCancellationCount += 1
        }
        #expect(cleanCancellationCount == 1)
        #expect(session.isDiscardConfirmationPresented)
        #expect(session.navigationConfirmationRequestID == nil)

        session.discardChanges()
        #expect(session.draft == initialDraft)
        #expect(session.hasUnsavedChanges == false)
    }

    @Test
    func navigationConfirmationOwnershipRejectsStaleDismissals() {
        let session = TaskEditorSession(
            store: makeTestStore(),
            initialDraft: TaskEditorDraft(parentID: nil)
        )
        let firstRequestID = UUID()
        let replacementRequestID = UUID()

        session.requestDiscardConfirmation(for: firstRequestID)
        session.requestDiscardConfirmation(for: replacementRequestID)
        session.dismissDiscardConfirmation(for: firstRequestID)

        #expect(session.navigationConfirmationRequestID == replacementRequestID)
        #expect(session.isDiscardConfirmationPresented)

        session.dismissDiscardConfirmation(for: replacementRequestID)

        #expect(session.navigationConfirmationRequestID == nil)
        #expect(session.isDiscardConfirmationPresented == false)
    }

    @Test
    func checklistCommandsKeepIncompleteWorkBeforeCompletedWork() throws {
        let store = makeTestStore()
        var initialDraft = TaskEditorDraft(parentID: nil)
        let completed = ChecklistEditorDraft(
            title: "Completed",
            isCompleted: true
        )
        let incomplete = ChecklistEditorDraft(title: "Incomplete")
        initialDraft.checklistItems = [completed, incomplete]
        let session = TaskEditorSession(
            store: store,
            initialDraft: initialDraft
        )

        #expect(session.orderedChecklistIndices == [1, 0])
        let insertedID = session.addChecklistItem()
        #expect(session.draft.checklistItems.map(\.id) == [
            incomplete.id,
            insertedID,
            completed.id
        ])

        session.moveChecklistItems(
            fromOffsets: IndexSet(integer: 1),
            toOffset: 0
        )
        #expect(session.draft.checklistItems.map(\.id) == [
            insertedID,
            incomplete.id,
            completed.id
        ])
    }

    @Test
    func newlyCompletedChecklistItemMovesAfterEveryCompletedItem() {
        var initialDraft = TaskEditorDraft(parentID: nil)
        let newlyCompleted = ChecklistEditorDraft(title: "Finish me")
        let completedFirst = ChecklistEditorDraft(
            title: "Completed first",
            isCompleted: true
        )
        let completedSecond = ChecklistEditorDraft(
            title: "Completed second",
            isCompleted: true
        )
        initialDraft.checklistItems = [
            newlyCompleted,
            completedFirst,
            completedSecond,
        ]
        let session = TaskEditorSession(
            store: makeTestStore(),
            initialDraft: initialDraft
        )

        session.toggleChecklistItem(id: newlyCompleted.id)

        #expect(session.draft.checklistItems.map(\.id) == [
            completedFirst.id,
            completedSecond.id,
            newlyCompleted.id,
        ])
        #expect(session.draft.checklistItems.map(\.isCompleted) == [
            true,
            true,
            true,
        ])
    }

    @Test
    func reopeningChecklistItemMovesItBeforeCompletedHistory() {
        var initialDraft = TaskEditorDraft(parentID: nil)
        let completedFirst = ChecklistEditorDraft(
            title: "Completed first",
            isCompleted: true
        )
        let reopened = ChecklistEditorDraft(
            title: "Reopen me",
            isCompleted: true
        )
        let completedLast = ChecklistEditorDraft(
            title: "Completed last",
            isCompleted: true
        )
        initialDraft.checklistItems = [
            completedFirst,
            reopened,
            completedLast,
        ]
        let session = TaskEditorSession(
            store: makeTestStore(),
            initialDraft: initialDraft
        )

        session.toggleChecklistItem(id: reopened.id)

        #expect(session.draft.checklistItems.map(\.id) == [
            reopened.id,
            completedFirst.id,
            completedLast.id,
        ])
        #expect(session.draft.checklistItems[0].isCompleted == false)
    }

    @Test
    func rapidChecklistToggleUsesStableIdentityAfterReordering() {
        var initialDraft = TaskEditorDraft(parentID: nil)
        let item = ChecklistEditorDraft(title: "Toggle twice")
        let completed = ChecklistEditorDraft(
            title: "Completed",
            isCompleted: true
        )
        initialDraft.checklistItems = [item, completed]
        let session = TaskEditorSession(
            store: makeTestStore(),
            initialDraft: initialDraft
        )

        session.toggleChecklistItem(id: item.id)
        session.toggleChecklistItem(id: item.id)

        #expect(session.draft.checklistItems.map(\.id) == [
            item.id,
            completed.id,
        ])
        #expect(session.draft.checklistItems[0].isCompleted == false)
    }

    @Test
    func completedChecklistOrderPersistsAcrossSaveAndReload() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "checklist-order"
        ).createTask(
            title: "Persistent checklist",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        try ChecklistDraftService().save(
            drafts: [
                ChecklistEditorDraft(title: "Finish me"),
                ChecklistEditorDraft(
                    title: "Completed first",
                    isCompleted: true
                ),
                ChecklistEditorDraft(
                    title: "Completed second",
                    isCompleted: true
                ),
            ],
            taskID: task.id,
            context: context,
            deviceID: "checklist-order"
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let storedTask = try #require(store.task(for: task.id))
        let session = TaskEditorSession(
            store: store,
            initialDraft: store.editorDraft(for: storedTask)
        )
        let newlyCompletedID = try #require(
            session.draft.checklistItems.first {
                $0.title == "Finish me"
            }?.id
        )

        session.toggleChecklistItem(id: newlyCompletedID)

        #expect(store.saveTaskDraft(session.draft))
        let relaunchedStore = makeTestStore()
        relaunchedStore.configureIfNeeded(
            context: ModelContext(context.container)
        )
        #expect(relaunchedStore.checklistItems(for: task.id).map(\.title) == [
            "Completed first",
            "Completed second",
            "Finish me",
        ])
        #expect(
            relaunchedStore.checklistItems(for: task.id).map(\.isCompleted) ==
                [true, true, true]
        )
    }

    @Test
    func staleSaveOffersTheLatestDraftWithoutDiscardingTheCurrentDraft() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: "Original",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let initialDraft = store.editorDraft(
            for: try #require(store.task(for: task.id))
        )
        let session = TaskEditorSession(
            store: store,
            initialDraft: initialDraft
        )

        let siblingContext = ModelContext(context.container)
        let siblingRepository = SwiftDataTaskRepository(
            context: siblingContext,
            deviceID: "sibling"
        )
        let siblingTask = try #require(
            try siblingRepository.task(id: task.id)
        )
        try siblingRepository.updateTask(
            taskID: siblingTask.id,
            title: "Latest",
            parentID: siblingTask.parentID,
            categoryID: nil,
            colorHex: siblingTask.colorHex,
            iconName: siblingTask.iconName,
            notes: siblingTask.notes,
            estimatedSeconds: siblingTask.estimatedSeconds,
            dueAt: siblingTask.dueAt
        )
        session.draft.title = "My Draft"
        var didSave = false

        session.save(
            using: { store.saveTaskDraftResult($0) },
            onSaved: { _ in didSave = true }
        )

        #expect(didSave == false)
        #expect(session.draft.title == "My Draft")
        #expect(session.pendingReloadDraft?.title == "Latest")

        session.reloadLatestDraft()
        #expect(session.draft.title == "Latest")
        #expect(session.hasUnsavedChanges == false)
    }

    @Test
    func saveResultDismissesOnlyOnSuccessAndKeepsFailedDraft() {
        let store = makeTestStore()
        var initialDraft = TaskEditorDraft(parentID: nil)
        initialDraft.title = "Initial"
        let session = TaskEditorSession(
            store: store,
            initialDraft: initialDraft
        )
        var savedCount = 0
        let savedTaskID = UUID()

        session.save(
            using: { _ in .saved(taskID: savedTaskID) },
            onSaved: { taskID in
                #expect(taskID == savedTaskID)
                savedCount += 1
            }
        )
        #expect(savedCount == 1)

        session.draft.title = "Keep editing"
        session.save(
            using: { _ in .failed(message: "Could not save") },
            onSaved: { _ in savedCount += 1 }
        )

        #expect(savedCount == 1)
        #expect(session.draft.title == "Keep editing")
        #expect(store.errorMessage == "Could not save")
    }

    @Test
    func recoveryCopyPreservesContentButUsesFreshTaskAndChecklistIdentities() {
        var draft = TaskEditorDraft(parentID: UUID())
        draft.taskID = UUID()
        draft.title = "Recovered"
        draft.notes = "Keep this"
        draft.estimatedMinutes = 25
        draft.hasDueDate = true
        draft.dueAt = Date(timeIntervalSince1970: 1_234)
        let checklist = ChecklistEditorDraft(
            title: "Preserve item",
            isCompleted: true,
            iconName: "star",
            colorHex: "FF9500"
        )
        draft.checklistItems = [checklist]
        let recoveredParentID = UUID()

        let copy = draft.copyAsNew(
            parentID: recoveredParentID,
            categoryID: nil
        )

        #expect(copy.baseline == nil)
        #expect(copy.taskID == nil)
        #expect(copy.parentID == recoveredParentID)
        #expect(copy.title == draft.title)
        #expect(copy.notes == draft.notes)
        #expect(copy.estimatedMinutes == draft.estimatedMinutes)
        #expect(copy.hasDueDate == draft.hasDueDate)
        #expect(copy.dueAt == draft.dueAt)
        #expect(copy.checklistItems.count == 1)
        #expect(copy.checklistItems[0].id != checklist.id)
        #expect(copy.checklistItems[0].existingID == nil)
        #expect(copy.checklistItems[0].title == checklist.title)
        #expect(copy.checklistItems[0].isCompleted)
        #expect(copy.checklistItems[0].iconName == checklist.iconName)
        #expect(copy.checklistItems[0].colorHex == checklist.colorHex)
    }

    @Test
    func restoredDiskDraftKeepsTheCurrentStoreDraftAsItsSessionBaseline() throws {
        let context = try makeTestContext()
        let created = try SwiftDataTaskRepository(
            context: context,
            deviceID: "draft-restore"
        ).createTask(
            title: "Persisted",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let task = try #require(store.task(for: created.id))
        let current = store.editorDraft(for: task)
        var recovered = current
        recovered.title = "Recovered edit"
        recovered.notes = "Still unsaved"
        let session = TaskEditorSession(store: store, initialDraft: current)

        session.restoreRecoveredDraft(recovered)

        #expect(session.draft == recovered)
        #expect(session.sessionBaseline == current)
        #expect(session.hasUnsavedChanges)
        #expect(session.parentCandidates.map(\.id) ==
            store.validParentTasks(for: created.id).map(\.id))
    }

    @Test
    func existingTaskWorkspaceCanPreserveAStaleDraftWithoutOpeningReloadAlert() {
        let store = makeTestStore()
        let session = TaskEditorSession(
            store: store,
            initialDraft: TaskEditorDraft(parentID: nil)
        )
        session.draft.title = "Preserve this draft"
        var didPreserveStaleDraft = false

        session.save(
            using: { _ in .stale },
            onSaved: { _ in
                Issue.record("A stale draft must not report a successful save")
            },
            onStale: {
                didPreserveStaleDraft = true
            }
        )

        #expect(didPreserveStaleDraft)
        #expect(session.pendingReloadDraft == nil)
        #expect(session.draft.title == "Preserve this draft")
    }
}
