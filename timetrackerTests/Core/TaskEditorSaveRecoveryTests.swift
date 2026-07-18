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
        var staleDraft = store.editorDraft(for: try #require(store.task(for: task.id)))
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
        #expect(store.saveTaskDraftResult(latestDraft) == .saved)
        let persisted = try #require(
            try SwiftDataTaskRepository(
                context: ModelContext(context.container),
                deviceID: "fresh"
            ).task(id: task.id)
        )
        #expect(persisted.title == "Saved after reload")
        #expect(persisted.statusRaw == LegacyTaskStatusRaw.completed)
    }
}
