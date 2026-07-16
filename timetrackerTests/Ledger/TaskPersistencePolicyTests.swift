import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskPersistencePolicyTests {
    @Test @MainActor
    func invalidTaskCreatesFailBeforeInsertingAnyRows() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "local-device")
        let maximum = SyncDataSnapshotRestoreLimits.maximumTitleByteCount

        #expect(throws: TaskPersistenceValidationError.required(field: .taskTitle)) {
            try repository.createTask(
                title: "  \n  ",
                parentID: nil,
                colorHex: nil,
                iconName: nil
            )
        }
        #expect(throws: TaskPersistenceValidationError.controlCharacter(field: .taskTitle)) {
            try repository.createTask(
                title: "Unsafe\u{0000}title",
                parentID: nil,
                colorHex: nil,
                iconName: nil
            )
        }
        #expect(
            throws: TaskPersistenceValidationError.byteLimitExceeded(
                field: .taskTitle,
                actual: maximum + 1,
                maximum: maximum
            )
        ) {
            try repository.createTask(
                title: String(repeating: "a", count: maximum + 1),
                parentID: nil,
                colorHex: nil,
                iconName: nil
            )
        }

        #expect(try context.fetch(FetchDescriptor<TaskNode>()).isEmpty)
    }

    @Test @MainActor
    func invalidTaskUpdateLeavesEveryFieldAndAuditMarkerUnchanged() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "local-device")
        let task = try repository.createTask(
            title: "Original",
            parentID: nil,
            colorHex: "112233",
            iconName: "circle"
        )
        let originalDueAt = Date(timeIntervalSinceReferenceDate: 2_000_000)
        try repository.updateTask(
            taskID: task.id,
            title: task.title,
            status: .planned,
            parentID: nil,
            categoryID: nil,
            colorHex: task.colorHex,
            iconName: task.iconName,
            notes: "Original notes",
            estimatedSeconds: 1_800,
            dueAt: originalDueAt
        )
        task.deviceID = "remote-device"
        try context.save()

        let originalUpdatedAt = task.updatedAt
        let originalMutationID = task.clientMutationID
        let maximum = SyncDataSnapshotRestoreLimits.maximumNoteByteCount

        #expect(
            throws: TaskPersistenceValidationError.byteLimitExceeded(
                field: .notes,
                actual: maximum + 1,
                maximum: maximum
            )
        ) {
            try repository.updateTask(
                taskID: task.id,
                title: "Replacement",
                status: .completed,
                parentID: nil,
                categoryID: nil,
                colorHex: "AABBCC",
                iconName: "star",
                notes: String(repeating: "n", count: maximum + 1),
                estimatedSeconds: 3_600,
                dueAt: originalDueAt.addingTimeInterval(86_400)
            )
        }

        #expect(task.title == "Original")
        #expect(task.status == .planned)
        #expect(task.parentID == nil)
        #expect(task.colorHex == "112233")
        #expect(task.iconName == "circle")
        #expect(task.notes == "Original notes")
        #expect(task.estimatedSeconds == 1_800)
        #expect(task.dueAt == originalDueAt)
        #expect(task.updatedAt == originalUpdatedAt)
        #expect(task.deviceID == "remote-device")
        #expect(task.clientMutationID == originalMutationID)
    }

    @Test @MainActor
    func taskPersistenceAcceptsExactMultibyteLimitsAndNormalizesCompactFields() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "local-device")
        let title = String(repeating: "界", count: 1_365) + "a"
        let iconName = String(repeating: "界", count: 85) + "a"
        let notes = String(repeating: "界", count: 21_845) + "\n"

        #expect(title.utf8.count == SyncDataSnapshotRestoreLimits.maximumTitleByteCount)
        #expect(iconName.utf8.count == SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount)
        #expect(notes.utf8.count == SyncDataSnapshotRestoreLimits.maximumNoteByteCount)

        let task = try repository.createTask(
            title: "  \(title)  ",
            parentID: nil,
            colorHex: "  ",
            iconName: " \(iconName) "
        )
        try repository.updateTask(
            taskID: task.id,
            title: task.title,
            status: .active,
            parentID: nil,
            categoryID: nil,
            colorHex: task.colorHex,
            iconName: task.iconName,
            notes: notes,
            estimatedSeconds: nil,
            dueAt: nil
        )

        #expect(task.title == title)
        #expect(task.colorHex == nil)
        #expect(task.iconName == iconName)
        #expect(task.notes == notes)
    }

    @Test @MainActor
    func fullTaskUpdateMaintainsArchivedTimestampAcrossStatusTransitions() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "local-device")
        let task = try repository.createTask(
            title: "Lifecycle",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )

        try update(task, status: .archived, repository: repository)
        let firstArchivedAt = try #require(task.archivedAt)

        try update(task, status: .archived, repository: repository, title: "Renamed")
        #expect(task.archivedAt == firstArchivedAt)

        try update(task, status: .active, repository: repository)
        #expect(task.archivedAt == nil)
    }

    @Test @MainActor
    func statusCommandsPreserveTheOriginalArchiveTimestamp() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "local-device")
        let task = try repository.createTask(
            title: "Archive command lifecycle",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )

        try repository.setTaskStatus(taskID: task.id, status: .archived)
        #expect(task.archivedAt == task.updatedAt)

        let originalArchivedAt = Date(timeIntervalSince1970: 1_000)
        task.archivedAt = originalArchivedAt
        try context.save()

        try repository.setTaskStatus(taskID: task.id, status: .archived)
        #expect(task.archivedAt == originalArchivedAt)

        try repository.archiveTask(taskID: task.id)
        #expect(task.archivedAt == originalArchivedAt)

        try repository.setTaskStatus(taskID: task.id, status: .active)
        #expect(task.archivedAt == nil)
    }

    @Test @MainActor
    func invalidCategoryWritesHaveNoPersistentOrInMemorySideEffects() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "local-device")
        let compactMaximum = SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount

        #expect(throws: TaskPersistenceValidationError.required(field: .categoryTitle)) {
            try repository.createCategory(
                title: " \t ",
                colorHex: nil,
                iconName: nil
            )
        }
        #expect(throws: TaskPersistenceValidationError.controlCharacter(field: .categoryTitle)) {
            try repository.createCategory(
                title: "Work\nPrivate",
                colorHex: nil,
                iconName: nil
            )
        }
        #expect(try context.fetch(FetchDescriptor<TaskCategory>()).isEmpty)

        let category = try repository.createCategory(
            title: "Original",
            colorHex: "445566",
            iconName: "folder",
            includesInForecast: true
        )
        category.deviceID = "remote-device"
        try context.save()
        let originalUpdatedAt = category.updatedAt
        let originalMutationID = category.clientMutationID

        #expect(
            throws: TaskPersistenceValidationError.byteLimitExceeded(
                field: .iconName,
                actual: compactMaximum + 1,
                maximum: compactMaximum
            )
        ) {
            try repository.updateCategory(
                categoryID: category.id,
                title: "Replacement",
                colorHex: "AABBCC",
                iconName: String(repeating: "i", count: compactMaximum + 1),
                includesInForecast: false
            )
        }

        #expect(category.title == "Original")
        #expect(category.colorHex == "445566")
        #expect(category.iconName == "folder")
        #expect(category.includesInForecast)
        #expect(category.updatedAt == originalUpdatedAt)
        #expect(category.deviceID == "remote-device")
        #expect(category.clientMutationID == originalMutationID)
    }

    @MainActor
    private func update(
        _ task: TaskNode,
        status: TaskStatus,
        repository: SwiftDataTaskRepository,
        title: String? = nil
    ) throws {
        try repository.updateTask(
            taskID: task.id,
            title: title ?? task.title,
            status: status,
            parentID: task.parentID,
            categoryID: nil,
            colorHex: task.colorHex,
            iconName: task.iconName,
            notes: task.notes,
            estimatedSeconds: task.estimatedSeconds,
            dueAt: task.dueAt
        )
    }

    @Test @MainActor
    func taskEditorValidationAcceptsExactUtf8LimitsAndMultilineNotes() {
        let title = String(repeating: "界", count: 1_365) + "a"
        let compactValue = String(repeating: "界", count: 85) + "a"
        let notes = String(repeating: "界", count: 21_845) + "a"
        let validation = TaskEditorValidation(
            title: title,
            notes: notes,
            iconName: compactValue,
            colorHex: compactValue
        )

        #expect(title.utf8.count == SyncDataSnapshotRestoreLimits.maximumTitleByteCount)
        #expect(compactValue.utf8.count == SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount)
        #expect(notes.utf8.count == SyncDataSnapshotRestoreLimits.maximumNoteByteCount)
        #expect(validation.isValid)

        let multilineValidation = TaskEditorValidation(
            title: title,
            notes: "Line one\tcontinued\nLine two\r\nLine three",
            iconName: compactValue,
            colorHex: compactValue
        )
        #expect(multilineValidation.isValid)
    }

    @Test @MainActor
    func taskEditorValidationReportsEveryFieldWithoutMutatingDraftInput() {
        let title = " \n "
        let notes = "Line one\u{0000}Line two"
        let iconName = "circle\nfill"
        let colorHex = "AA\u{001F}BB"
        let validation = TaskEditorValidation(
            title: title,
            notes: notes,
            iconName: iconName,
            colorHex: colorHex
        )

        #expect(validation.titleError == .required(field: .taskTitle))
        #expect(validation.notesError == .controlCharacter(field: .notes))
        #expect(validation.iconNameError == .controlCharacter(field: .iconName))
        #expect(validation.colorHexError == .controlCharacter(field: .colorHex))
        #expect(validation.isValid == false)
        #expect(title == " \n ")
        #expect(notes == "Line one\u{0000}Line two")
        #expect(iconName == "circle\nfill")
        #expect(colorHex == "AA\u{001F}BB")
    }

    @Test @MainActor
    func taskEditorValidationReportsUtf8CountsBeyondEachLimit() throws {
        let titleMaximum = SyncDataSnapshotRestoreLimits.maximumTitleByteCount
        let compactMaximum = SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount
        let notesMaximum = SyncDataSnapshotRestoreLimits.maximumNoteByteCount
        let validation = TaskEditorValidation(
            title: String(repeating: "a", count: titleMaximum + 1),
            notes: String(repeating: "n", count: notesMaximum + 1),
            iconName: String(repeating: "i", count: compactMaximum + 1),
            colorHex: String(repeating: "c", count: compactMaximum + 1)
        )

        #expect(
            validation.titleError == .byteLimitExceeded(
                field: .taskTitle,
                actual: titleMaximum + 1,
                maximum: titleMaximum
            )
        )
        #expect(
            validation.notesError == .byteLimitExceeded(
                field: .notes,
                actual: notesMaximum + 1,
                maximum: notesMaximum
            )
        )
        #expect(
            validation.iconNameError == .byteLimitExceeded(
                field: .iconName,
                actual: compactMaximum + 1,
                maximum: compactMaximum
            )
        )
        #expect(
            validation.colorHexError == .byteLimitExceeded(
                field: .colorHex,
                actual: compactMaximum + 1,
                maximum: compactMaximum
            )
        )

        let message = try #require(validation.titleError?.errorDescription)
        let localizedActual = String.localizedStringWithFormat("%lld", Int64(titleMaximum + 1))
        let localizedMaximum = String.localizedStringWithFormat("%lld", Int64(titleMaximum))
        #expect(message.contains(localizedActual))
        #expect(message.contains(localizedMaximum))
    }
}
