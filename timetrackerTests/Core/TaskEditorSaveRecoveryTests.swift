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

        _ = try StoreScopedTaskLifecycleCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "sibling"
        ).setStatus(.completed, taskID: task.id)
        staleDraft.title = "Must not overwrite"

        #expect(store.saveTaskDraftResult(staleDraft) == .stale)
        #expect(store.errorMessage == nil)
        let refreshedTask = try #require(store.task(for: task.id))
        var latestDraft = store.editorDraft(for: refreshedTask)
        #expect(latestDraft.status == .completed)
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
        #expect(persisted.status == .completed)
    }
}
