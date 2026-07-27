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
    func checklistCommandsKeepIncompleteWorkBeforeCompletedWork() {
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
            completed.id,
        ])

        session.moveChecklistItems(
            fromOffsets: IndexSet(integer: 1),
            toOffset: 0
        )
        #expect(session.draft.checklistItems.map(\.id) == [
            insertedID,
            incomplete.id,
            completed.id,
        ])
    }

    @Test
    func directChecklistReorderPersistsAcrossDraftSaveAndFreshReload() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "direct-checklist-reorder"
        ).createTask(
            title: "Persistent direct reorder",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        try ChecklistDraftService().save(
            drafts: [
                ChecklistEditorDraft(title: "First"),
                ChecklistEditorDraft(title: "Second"),
                ChecklistEditorDraft(title: "Third"),
            ],
            taskID: task.id,
            context: context,
            deviceID: "direct-checklist-reorder"
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let storedTask = try #require(store.task(for: task.id))
        let session = TaskEditorSession(
            store: store,
            initialDraft: store.editorDraft(for: storedTask)
        )

        session.moveChecklistItems(
            fromOffsets: IndexSet(integer: 0),
            toOffset: 3
        )

        #expect(session.draft.checklistItems.map(\.title) == [
            "Second",
            "Third",
            "First",
        ])
        #expect(store.saveTaskDraft(session.draft))

        let relaunchedStore = makeTestStore()
        relaunchedStore.configureIfNeeded(
            context: ModelContext(context.container)
        )
        #expect(relaunchedStore.checklistItems(for: task.id).map(\.title) == [
            "Second",
            "Third",
            "First",
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
        let openFirst = ChecklistEditorDraft(title: "Open first")
        let item = ChecklistEditorDraft(title: "Toggle twice")
        let openLast = ChecklistEditorDraft(title: "Open last")
        let completed = ChecklistEditorDraft(
            title: "Completed",
            isCompleted: true
        )
        initialDraft.checklistItems = [
            openFirst,
            item,
            openLast,
            completed,
        ]
        let session = TaskEditorSession(
            store: makeTestStore(),
            initialDraft: initialDraft
        )

        session.toggleChecklistItem(id: item.id)
        session.toggleChecklistItem(id: item.id)

        // Completing then uncompleting restores the original position.
        #expect(session.draft.checklistItems.map(\.id) == [
            openFirst.id,
            item.id,
            openLast.id,
            completed.id,
        ])
        #expect(session.draft.checklistItems[1].isCompleted == false)
    }

    @Test
    func uncompletingChecklistItemRestoresItsOriginalPosition() {
        var initialDraft = TaskEditorDraft(parentID: nil)
        let first = ChecklistEditorDraft(title: "First")
        let item = ChecklistEditorDraft(title: "Round trip")
        let last = ChecklistEditorDraft(title: "Last")
        initialDraft.checklistItems = [first, item, last]
        let session = TaskEditorSession(
            store: makeTestStore(),
            initialDraft: initialDraft
        )

        session.toggleChecklistItem(id: item.id)
        #expect(session.draft.checklistItems.map(\.id) == [
            first.id,
            last.id,
            item.id,
        ])

        session.toggleChecklistItem(id: item.id)
        #expect(session.draft.checklistItems.map(\.id) == [
            first.id,
            item.id,
            last.id,
        ])
        #expect(session.draft.checklistItems[1].isCompleted == false)
    }

    @Test
    func uncompletingChecklistItemClampsRestoredPositionInsideIncompleteGroup() {
        var initialDraft = TaskEditorDraft(parentID: nil)
        let first = ChecklistEditorDraft(title: "First")
        let item = ChecklistEditorDraft(title: "Round trip")
        let last = ChecklistEditorDraft(title: "Last")
        initialDraft.checklistItems = [first, item, last]
        let session = TaskEditorSession(
            store: makeTestStore(),
            initialDraft: initialDraft
        )

        session.toggleChecklistItem(id: item.id)
        session.toggleChecklistItem(id: first.id)
        // `first` was completed after `item`; uncompleting `item` must not
        // jump ahead of the remaining incomplete rows.
        session.toggleChecklistItem(id: item.id)
        #expect(session.draft.checklistItems.map(\.id) == [
            last.id,
            item.id,
            first.id,
        ])
        #expect(session.draft.checklistItems[1].isCompleted == false)
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
        let initialDraft = try store.editorDraft(
            for: #require(store.task(for: task.id))
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
        draft.dueAt = Date(timeIntervalSince1970: 1234)
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

    @Test
    func acceptedAutosaveRebasesChecklistIdentityWithoutNormalizingVisibleText() throws {
        let context = try makeTestContext()
        let created = try SwiftDataTaskRepository(
            context: context,
            deviceID: "autosave-rebase"
        ).createTask(
            title: "Original",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let task = try #require(store.task(for: created.id))
        let session = TaskEditorSession(
            store: store,
            initialDraft: store.editorDraft(for: task)
        )
        session.draft.title = "Visible title  "
        session.draft.checklistItems.append(
            ChecklistEditorDraft(title: "New item  ")
        )
        let savedDraft = session.draft
        let visibleChecklistID = try #require(
            savedDraft.checklistItems.first?.id
        )

        #expect(
            store.saveTaskDraftResult(savedDraft) ==
                .saved(taskID: created.id)
        )
        session.acceptAutosavedDraft(
            savedDraft,
            for: created.id
        )

        #expect(session.hasUnsavedChanges == false)
        #expect(session.draft.title == "Visible title  ")
        #expect(session.draft.checklistItems.first?.title == "New item  ")
        #expect(session.draft.checklistItems.first?.id == visibleChecklistID)
        #expect(session.draft.checklistItems.first?.existingID != nil)
        #expect(
            try session.draft.baseline ==
                store.editorDraft(for: #require(store.task(for: created.id)))
                .baseline
        )

        let sourceDraft = try store.editorDraft(
            for: #require(store.task(for: created.id))
        )
        session.synchronizeWithStoreIfClean(
            taskID: created.id,
            sourceBaseline: sourceDraft.baseline,
            parentCandidateIDs: store.validParentTasks(
                for: created.id
            ).map(\.id)
        )

        #expect(session.draft.title == "Visible title  ")
        #expect(session.draft.checklistItems.first?.id == visibleChecklistID)

        session.draft.notes = "A later edit"
        #expect(
            store.saveTaskDraftResult(session.draft) ==
                .saved(taskID: created.id)
        )
    }

    @Test
    func acceptedAutosavePreservesInputThatArrivesDuringThePreviousCommit() throws {
        let context = try makeTestContext()
        let created = try SwiftDataTaskRepository(
            context: context,
            deviceID: "autosave-concurrent-input"
        ).createTask(
            title: "Original",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let task = try #require(store.task(for: created.id))
        let session = TaskEditorSession(
            store: store,
            initialDraft: store.editorDraft(for: task)
        )

        session.draft.title = "Saved prefix"
        let savedItemID = session.addChecklistItem()
        let savedItemIndex = try #require(
            session.draft.checklistItems.firstIndex {
                $0.id == savedItemID
            }
        )
        session.draft.checklistItems[savedItemIndex].title = "Saved item"
        let savedDraft = session.draft

        session.draft.title = "Saved prefix and later input"
        session.draft.checklistItems[savedItemIndex].title =
            "Saved item continued"
        let laterItemID = session.addChecklistItem()
        let laterItemIndex = try #require(
            session.draft.checklistItems.firstIndex {
                $0.id == laterItemID
            }
        )
        session.draft.checklistItems[laterItemIndex].title = "Later item"

        #expect(
            store.saveTaskDraftResult(savedDraft) ==
                .saved(taskID: created.id)
        )
        session.acceptAutosavedDraft(savedDraft, for: created.id)

        #expect(session.draft.title == "Saved prefix and later input")
        #expect(session.draft.checklistItems.map(\.id) == [
            savedItemID,
            laterItemID,
        ])
        #expect(session.draft.checklistItems.map(\.title) == [
            "Saved item continued",
            "Later item",
        ])
        #expect(session.draft.checklistItems[0].existingID != nil)
        #expect(session.draft.checklistItems[1].existingID == nil)
        #expect(session.sessionBaseline.title == "Saved prefix")
        #expect(session.sessionBaseline.checklistItems.map(\.id) == [
            savedItemID,
        ])
        #expect(session.hasUnsavedChanges)

        let nextDraft = session.draft
        #expect(
            store.saveTaskDraftResult(nextDraft) ==
                .saved(taskID: created.id)
        )
        session.acceptAutosavedDraft(nextDraft, for: created.id)

        #expect(session.hasUnsavedChanges == false)
        #expect(session.draft.checklistItems.map(\.id) == [
            savedItemID,
            laterItemID,
        ])
        #expect(session.draft.checklistItems.allSatisfy {
            $0.existingID != nil
        })
    }

    @Test
    func acceptedAutosaveFailsClosedWhenPersistedChecklistIdentityDiverges() throws {
        let context = try makeTestContext()
        let created = try SwiftDataTaskRepository(
            context: context,
            deviceID: "autosave-checklist-divergence"
        ).createTask(
            title: "Original",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let task = try #require(store.task(for: created.id))
        let session = TaskEditorSession(
            store: store,
            initialDraft: store.editorDraft(for: task)
        )
        let itemID = session.addChecklistItem()
        session.draft.checklistItems[0].title = "Saved item"
        let savedDraft = session.draft

        #expect(
            store.saveTaskDraftResult(savedDraft) ==
                .saved(taskID: created.id)
        )
        var externallyChangedDraft = try store.editorDraft(
            for: #require(store.task(for: created.id))
        )
        externallyChangedDraft.checklistItems = []
        #expect(
            store.saveTaskDraftResult(externallyChangedDraft) ==
                .saved(taskID: created.id)
        )

        session.draft.title = "Keep this later input"
        let draftBeforeAcceptance = session.draft
        let baselineBeforeAcceptance = session.sessionBaseline

        #expect(session.acceptAutosavedDraft(savedDraft, for: created.id) == false)
        #expect(session.draft == draftBeforeAcceptance)
        #expect(session.sessionBaseline == baselineBeforeAcceptance)
        #expect(session.draft.checklistItems.first?.id == itemID)
        #expect(session.draft.checklistItems.first?.existingID == nil)
        #expect(session.hasUnsavedChanges)
    }

    @Test
    func autosaveConsumesQuantityResetConfirmationExactlyOnce()
        throws
    {
        let context = try makeTestContext()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var newDraft = TaskEditorDraft(parentID: nil)
        newDraft.title = "Push-ups"
        newDraft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 50,
            unitLabel: "reps"
        )
        let taskID: UUID
        switch store.saveTaskDraftResult(newDraft) {
        case let .saved(savedTaskID):
            taskID = savedTaskID
        case .stale, .failed:
            Issue.record("Quantity task creation should succeed")
            return
        }
        let session = try TaskEditorSession(
            store: store,
            initialDraft: store.editorDraft(
                for: #require(store.task(for: taskID))
            )
        )
        session.draft.quantityGoal = nil
        session.draft.confirmsQuantityProgressReset = true
        let removalDraft = session.draft

        #expect(
            store.saveTaskDraftResult(removalDraft) ==
                .saved(taskID: taskID)
        )
        #expect(session.acceptAutosavedDraft(removalDraft, for: taskID))
        #expect(session.draft.confirmsQuantityProgressReset == false)
        #expect(
            session.sessionBaseline.confirmsQuantityProgressReset ==
                false
        )

        session.draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 75,
            unitLabel: "reps"
        )
        let restoredDraft = session.draft
        #expect(
            store.saveTaskDraftResult(restoredDraft) ==
                .saved(taskID: taskID)
        )
        #expect(session.acceptAutosavedDraft(restoredDraft, for: taskID))
        #expect(session.draft.confirmsQuantityProgressReset == false)

        session.draft.quantityGoal = nil
        #expect(session.isPersistenceValid == false)
        #expect(
            store.saveTaskDraftResult(session.draft) == .failed(
                message: TaskProgressDraftMutationError
                    .quantityGoalRemovalRequiresConfirmation
                    .localizedDescription
            )
        )
    }

    @Test
    func autosaveValidationWaitsForAnEmptyChecklistDraftToBecomePersistable() {
        let store = makeTestStore()
        var initialDraft = TaskEditorDraft(parentID: nil)
        initialDraft.title = "Existing task"
        let session = TaskEditorSession(
            store: store,
            initialDraft: initialDraft
        )
        let checklistID = session.addChecklistItem()

        #expect(session.isPersistenceValid == false)

        session.draft.checklistItems[0].title = "Persist me"

        #expect(session.isPersistenceValid)
        #expect(session.draft.checklistItems[0].id == checklistID)
    }

    @Test
    func persistenceValidationIncludesQuantityAndRecurrenceDrafts() {
        var initialDraft = TaskEditorDraft(parentID: nil)
        initialDraft.title = "Push-ups"
        let session = TaskEditorSession(
            store: makeTestStore(),
            initialDraft: initialDraft
        )

        session.draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 0,
            unitLabel: "reps"
        )
        #expect(session.isPersistenceValid == false)

        session.draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 50,
            unitLabel: "reps"
        )
        #expect(session.isPersistenceValid)

        session.draft.dailyRecurrence = TaskDailyRecurrenceDraft(
            startDayKey: "2026-02-30",
            timeZoneIdentifier: "Asia/Singapore"
        )
        #expect(session.isPersistenceValid == false)

        session.draft.dailyRecurrence = TaskDailyRecurrenceDraft(
            startDayKey: "2026-07-21",
            timeZoneIdentifier: "Asia/Singapore"
        )
        #expect(session.isPersistenceValid)
    }

    @Test
    func quantityRemovalRequiresConfirmationBeforeAutosave() {
        var draft = TaskEditorDraft(parentID: nil)
        draft.title = "Existing quantity task"
        draft.baseline = TaskEditorDraftBaseline(
            taskMutationID: UUID(),
            checklistItemMutationIDs: [:],
            checklistVisualMutationIDs: [:],
            categoryAssignmentMutationID: nil,
            quantityGoalMutationID: UUID()
        )
        let session = TaskEditorSession(
            store: makeTestStore(),
            initialDraft: draft
        )

        #expect(session.isPersistenceValid == false)

        session.draft.confirmsQuantityProgressReset = true

        #expect(session.isPersistenceValid)
    }

    @Test
    func reEnablingQuantityGoalConsumesAnUnusedRemovalConfirmation() {
        var draft = TaskEditorDraft(parentID: nil)
        draft.title = "Existing quantity task"
        draft.baseline = TaskEditorDraftBaseline(
            taskMutationID: UUID(),
            checklistItemMutationIDs: [:],
            checklistVisualMutationIDs: [:],
            categoryAssignmentMutationID: nil,
            quantityGoalMutationID: UUID()
        )
        draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 50,
            unitLabel: "reps"
        )
        let session = TaskEditorSession(
            store: makeTestStore(),
            initialDraft: draft
        )

        session.confirmQuantityGoalRemoval()
        #expect(session.draft.confirmsQuantityProgressReset)

        session.setQuantityGoal(
            TaskQuantityGoalDraft(
                targetAmount: 50,
                unitLabel: "reps"
            )
        )
        session.setQuantityGoal(nil)

        #expect(session.draft.confirmsQuantityProgressReset == false)
        #expect(session.isPersistenceValid == false)
    }
}
