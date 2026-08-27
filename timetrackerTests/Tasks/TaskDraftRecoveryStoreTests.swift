import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskDraftRecoveryStoreTests {
    @Test
    func savedDraftIsRecoveredByAFreshStoreInstanceAfterRelaunch() throws {
        let directory = makeScratchDirectory()
        let taskID = UUID()
        let persisted = makeDraft(taskID: taskID, title: "Persisted title")
        var edited = makeDraft(taskID: taskID, title: "Unsaved edit")
        edited.notes = "Typed right before the crash"
        edited.checklistItems = [
            ChecklistEditorDraft(title: "Recovered item", isCompleted: true),
        ]

        try TaskDraftRecoveryStore(directoryURL: directory)
            .save(edited, for: taskID)

        let relaunchedStore = TaskDraftRecoveryStore(directoryURL: directory)
        let recovered = try relaunchedStore.load(
            for: taskID,
            currentDraft: persisted
        )

        #expect(recovered?.title == "Unsaved edit")
        #expect(recovered?.notes == "Typed right before the crash")
        #expect(recovered?.checklistItems.map(\.title) == ["Recovered item"])
        #expect(recovered?.checklistItems.first?.isCompleted == true)
        #expect(recovered?.taskID == taskID)
        #expect(recovered?.baseline != nil)
    }

    @Test
    func loadSuppressesAndRemovesADraftMatchingThePersistedState() throws {
        let directory = makeScratchDirectory()
        let taskID = UUID()
        let store = TaskDraftRecoveryStore(directoryURL: directory)
        let draft = makeDraft(taskID: taskID, title: "Already saved")
        try store.save(draft, for: taskID)

        let recovered = try store.load(for: taskID, currentDraft: draft)

        #expect(recovered == nil)
        let fileURL = try store.fileURL(for: taskID)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test
    func disabledDueDateDifferenceDoesNotTriggerRecovery() throws {
        let directory = makeScratchDirectory()
        let taskID = UUID()
        let store = TaskDraftRecoveryStore(directoryURL: directory)
        var saved = makeDraft(taskID: taskID, title: "Same content")
        saved.hasDueDate = false
        saved.dueAt = Date(timeIntervalSinceReferenceDate: 100_000)
        try store.save(saved, for: taskID)

        var persisted = makeDraft(taskID: taskID, title: "Same content")
        persisted.hasDueDate = false
        persisted.dueAt = Date(timeIntervalSinceReferenceDate: 200_000)
        let recovered = try store.load(for: taskID, currentDraft: persisted)

        #expect(recovered == nil)
        let fileURL = try store.fileURL(for: taskID)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test
    func expiredDraftIsNotRecoveredAndIsRemoved() throws {
        let directory = makeScratchDirectory()
        let taskID = UUID()
        let clock = DateBox(Date(timeIntervalSinceReferenceDate: 100_000))
        let store = TaskDraftRecoveryStore(
            directoryURL: directory,
            now: { clock.date }
        )
        try store.save(makeDraft(taskID: taskID), for: taskID)
        clock.date = clock.date.addingTimeInterval(
            TaskDraftRecoveryStore.defaultRetentionInterval + 60
        )

        let recovered = try store.load(
            for: taskID,
            currentDraft: makeDraft(taskID: taskID)
        )

        #expect(recovered == nil)
        let fileURL = try store.fileURL(for: taskID)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test
    func corruptRecoveryFileIsRemovedAndTreatedAsAbsent() throws {
        let directory = makeScratchDirectory()
        let taskID = UUID()
        let store = TaskDraftRecoveryStore(directoryURL: directory)
        try store.save(makeDraft(taskID: taskID), for: taskID)
        let fileURL = try store.fileURL(for: taskID)
        try Data("not a recovery envelope".utf8).write(to: fileURL)

        let recovered = try store.load(
            for: taskID,
            currentDraft: makeDraft(taskID: taskID)
        )

        #expect(recovered == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test
    func saveRejectsDraftsThatAreNotExistingTaskEdits() throws {
        let directory = makeScratchDirectory()
        let taskID = UUID()
        let store = TaskDraftRecoveryStore(directoryURL: directory)

        var newTaskDraft = makeDraft(taskID: taskID)
        newTaskDraft.baseline = nil
        #expect(throws: TaskDraftRecoveryStoreError.invalidExistingTaskDraft) {
            try store.save(newTaskDraft, for: taskID)
        }
        #expect(throws: TaskDraftRecoveryStoreError.invalidExistingTaskDraft) {
            try store.save(makeDraft(taskID: UUID()), for: taskID)
        }
        let fileURL = try store.fileURL(for: taskID)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test
    func oversizedDraftIsRejectedBeforeAnyFileIsWritten() throws {
        let directory = makeScratchDirectory()
        let taskID = UUID()
        let store = TaskDraftRecoveryStore(
            directoryURL: directory,
            maximumEncodedByteCount: 64
        )

        #expect(
            throws: TaskDraftRecoveryStoreError.self
        ) {
            try store.save(makeDraft(taskID: taskID), for: taskID)
        }
        let fileURL = try store.fileURL(for: taskID)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test
    func recoverableRecordsSortNewestFirstAndCleanupRemovesOnlyInvalidEntries() throws {
        let directory = makeScratchDirectory()
        let firstTaskID = UUID()
        let secondTaskID = UUID()
        let clock = DateBox(Date(timeIntervalSinceReferenceDate: 100_000))
        let store = TaskDraftRecoveryStore(
            directoryURL: directory,
            now: { clock.date }
        )
        try store.save(
            makeDraft(taskID: firstTaskID, title: "Older draft"),
            for: firstTaskID
        )
        clock.date = clock.date.addingTimeInterval(10)
        try store.save(
            makeDraft(taskID: secondTaskID, title: "Newer draft"),
            for: secondTaskID
        )
        let corruptTaskID = UUID()
        let corruptURL = directory.appendingPathComponent(
            store.fileName(for: corruptTaskID)
        )
        try Data("{".utf8).write(to: corruptURL)

        let records = try store.recoverableRecords()

        #expect(records.map(\.sourceTaskID) == [secondTaskID, firstTaskID])
        #expect(records.map(\.draft.title) == ["Newer draft", "Older draft"])
        #expect(FileManager.default.fileExists(atPath: corruptURL.path) == false)

        clock.date = clock.date.addingTimeInterval(
            TaskDraftRecoveryStore.defaultRetentionInterval + 60
        )
        #expect(try store.removeExpired() == 2)
        #expect(try store.recoverableRecords().isEmpty)
    }

    private func makeScratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TaskDraftRecoveryStoreTests-\(UUID().uuidString)",
                isDirectory: true
            )
    }

    private func makeDraft(
        taskID: UUID,
        title: String = "Persisted title"
    ) -> TaskEditorDraft {
        var draft = TaskEditorDraft(parentID: nil)
        draft.taskID = taskID
        draft.baseline = TaskEditorDraftBaseline(
            taskMutationID: UUID(),
            checklistItemMutationIDs: [:],
            checklistVisualMutationIDs: [:],
            categoryAssignmentMutationID: nil
        )
        draft.title = title
        return draft
    }

    private final class DateBox: @unchecked Sendable {
        var date: Date

        init(_ date: Date) {
            self.date = date
        }
    }
}
