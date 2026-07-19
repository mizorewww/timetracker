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

        session.discardChanges()
        #expect(session.draft == initialDraft)
        #expect(session.hasUnsavedChanges == false)
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
            onSaved: { didSave = true }
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

        session.save(
            using: { _ in .saved },
            onSaved: { savedCount += 1 }
        )
        #expect(savedCount == 1)

        session.draft.title = "Keep editing"
        session.save(
            using: { _ in .failed(message: "Could not save") },
            onSaved: { savedCount += 1 }
        )

        #expect(savedCount == 1)
        #expect(session.draft.title == "Keep editing")
        #expect(store.errorMessage == "Could not save")
    }
}
