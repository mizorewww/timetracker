import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct TaskProgressDraftEditingTests {
    @Test
    func simpleQuantityDraftCreatesNoRecurrenceGraph() throws {
        let context = try makeTestContext()
        var draft = TaskEditorDraft(parentID: nil)
        draft.title = "Drink water"
        draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 8,
            unitLabel: "glasses"
        )

        let outcome = try coordinator(context.container).save(
            draft: draft,
            sanitizedTitle: draft.title
        )
        let fresh = ModelContext(context.container)
        let goals = try fresh.fetch(FetchDescriptor<TaskQuantityGoal>())
            .visibleDeduplicatedByID()

        #expect(try fresh.fetch(FetchDescriptor<TaskNode>()).count == 1)
        #expect(goals.count == 1)
        #expect(goals.first?.taskID == outcome.savedTaskID)
        #expect(goals.first?.targetAmount == 8)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskRecurrenceRule>()).isEmpty
        )
        #expect(
            try fresh.fetch(
                FetchDescriptor<TaskRecurrenceOccurrence>()
            ).isEmpty
        )
    }

    @Test
    func newPausedRecurrencePersistsWithoutMaterializing() throws {
        let context = try makeTestContext()
        var draft = TaskEditorDraft(parentID: nil)
        draft.title = "Paused routine"
        draft.dailyRecurrence = TaskDailyRecurrenceDraft(
            isEnabled: false,
            startDayKey: "2026-07-21",
            timeZoneIdentifier: "Asia/Singapore"
        )

        let outcome = try coordinator(context.container).save(
            draft: draft,
            sanitizedTitle: draft.title
        )

        let fresh = ModelContext(context.container)
        let rule = try #require(
            try fresh.fetch(FetchDescriptor<TaskRecurrenceRule>())
                .visibleDeduplicatedByID().first
        )
        #expect(rule.templateTaskID == outcome.savedTaskID)
        #expect(rule.isEnabled == false)
        #expect(try fresh.fetch(FetchDescriptor<TaskNode>()).count == 1)
        #expect(
            try fresh.fetch(
                FetchDescriptor<TaskRecurrenceOccurrence>()
            ).isEmpty
        )
    }

    @Test
    func quantityGoalCannotBeRemovedWithoutExplicitConfirmation()
        throws {
        let context = try makeTestContext()
        let taskID = try createQuantityTask(in: context.container)
        let progressContext = ModelContext(context.container)
        progressContext.insert(
            TaskQuantityEntry(
                id: UUID(),
                taskID: taskID,
                amount: 20,
                deviceID: "quantity-entry"
            )
        )
        try progressContext.save()
        var draft = try editorDraft(
            taskID: taskID,
            container: context.container
        )
        draft.title = "Must roll back"
        draft.quantityGoal = nil

        #expect(
            throws: TaskProgressDraftMutationError
                .quantityGoalRemovalRequiresConfirmation
        ) {
            try coordinator(context.container).save(
                draft: draft,
                sanitizedTitle: draft.title
            )
        }

        let fresh = ModelContext(context.container)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .visibleDeduplicatedByID().first?.title == "Push-ups"
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskQuantityGoal>())
                .visibleDeduplicatedByID().count == 1
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskQuantityEntry>())
                .visibleDeduplicatedByID().count == 1
        )
    }

    @Test
    func removingQuantityGoalTombstonesExistingProgress() throws {
        let context = try makeTestContext()
        let taskID = try createQuantityTask(in: context.container)
        let progressContext = ModelContext(context.container)
        progressContext.insert(
            TaskQuantityEntry(
                id: UUID(),
                taskID: taskID,
                amount: 20,
                deviceID: "quantity-entry"
            )
        )
        try progressContext.save()
        var draft = try editorDraft(
            taskID: taskID,
            container: context.container
        )
        draft.quantityGoal = nil
        draft.confirmsQuantityProgressReset = true

        _ = try coordinator(context.container).save(
            draft: draft,
            sanitizedTitle: draft.title
        )

        let fresh = ModelContext(context.container)
        let goal = try #require(
            try fresh.fetch(FetchDescriptor<TaskQuantityGoal>()).first
        )
        let entry = try #require(
            try fresh.fetch(FetchDescriptor<TaskQuantityEntry>()).first
        )
        #expect(goal.deletedAt != nil)
        #expect(entry.deletedAt != nil)

        var reenabled = try editorDraft(
            taskID: taskID,
            container: context.container
        )
        reenabled.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 75,
            unitLabel: "reps"
        )
        _ = try coordinator(context.container).save(
            draft: reenabled,
            sanitizedTitle: reenabled.title
        )
        let verification = ModelContext(context.container)
        #expect(
            try verification.fetch(FetchDescriptor<TaskQuantityGoal>())
                .visibleDeduplicatedByID().first?.targetAmount == 75
        )
        #expect(
            try verification.fetch(FetchDescriptor<TaskQuantityEntry>())
                .visibleDeduplicatedByID().isEmpty
        )
    }

    @Test
    func unitChangeWithProgressRollsBackTaskAndGoalEdits() throws {
        let context = try makeTestContext()
        let taskID = try createQuantityTask(in: context.container)
        let progressContext = ModelContext(context.container)
        progressContext.insert(
            TaskQuantityEntry(
                id: UUID(),
                taskID: taskID,
                amount: 20,
                deviceID: "quantity-entry"
            )
        )
        try progressContext.save()
        var draft = try editorDraft(
            taskID: taskID,
            container: context.container
        )
        draft.title = "Must roll back"
        draft.quantityGoal?.unitLabel = "sets"

        #expect(
            throws: TaskProgressDraftMutationError
                .unitChangeRequiresProgressReset
        ) {
            try coordinator(context.container).save(
                draft: draft,
                sanitizedTitle: draft.title
            )
        }

        let fresh = ModelContext(context.container)
        let task = try #require(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .visibleDeduplicatedByID().first
        )
        let goal = try #require(
            try fresh.fetch(FetchDescriptor<TaskQuantityGoal>())
                .visibleDeduplicatedByID().first
        )
        #expect(task.title == "Push-ups")
        #expect(goal.unitLabel == "reps")
        #expect(
            try fresh.fetch(FetchDescriptor<TaskQuantityEntry>())
                .visibleDeduplicatedByID().count == 1
        )
    }

    @Test
    func concurrentProgressMakesGoalRemovalDraftStale() throws {
        let context = try makeTestContext()
        let taskID = try createQuantityTask(in: context.container)
        var staleDraft = try editorDraft(
            taskID: taskID,
            container: context.container
        )
        let sibling = ModelContext(context.container)
        sibling.insert(
            TaskQuantityEntry(
                id: UUID(),
                taskID: taskID,
                amount: 20,
                deviceID: "concurrent-entry"
            )
        )
        try sibling.save()
        staleDraft.quantityGoal = nil
        staleDraft.confirmsQuantityProgressReset = true

        #expect(throws: TaskLifecycleMutationError.staleDraft) {
            try coordinator(context.container).save(
                draft: staleDraft,
                sanitizedTitle: staleDraft.title
            )
        }

        let fresh = ModelContext(context.container)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskQuantityGoal>())
                .visibleDeduplicatedByID().count == 1
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskQuantityEntry>())
                .visibleDeduplicatedByID().count == 1
        )
    }

    @Test
    func concurrentProgressDoesNotBlockANonDestructiveTaskEdit() throws {
        let context = try makeTestContext()
        let taskID = try createQuantityTask(in: context.container)
        var draft = try editorDraft(
            taskID: taskID,
            container: context.container
        )
        let sibling = ModelContext(context.container)
        sibling.insert(
            TaskQuantityEntry(
                id: UUID(),
                taskID: taskID,
                amount: 20,
                deviceID: "concurrent-entry"
            )
        )
        try sibling.save()
        draft.title = "Safe title edit"

        _ = try coordinator(context.container).save(
            draft: draft,
            sanitizedTitle: draft.title
        )

        let fresh = ModelContext(context.container)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .visibleDeduplicatedByID().first?.title ==
                "Safe title edit"
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskQuantityEntry>())
                .visibleDeduplicatedByID().count == 1
        )
    }

    @Test
    func partialEntryClaimPreventsInventingAQuantityGoal() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "partial-claim"
        )
        let task = try repository.createTask(
            title: "Imported task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        context.insert(
            TaskQuantityEntry(
                id: UUID(),
                taskID: task.id,
                amount: 20,
                deviceID: "partial-claim"
            )
        )
        try context.save()
        var draft = try editorDraft(
            taskID: task.id,
            container: context.container
        )
        draft.title = "Must roll back"
        draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 50,
            unitLabel: "reps"
        )

        #expect(
            throws: TaskProgressDraftMutationError
                .incompleteQuantityGraph
        ) {
            try coordinator(context.container).save(
                draft: draft,
                sanitizedTitle: draft.title
            )
        }

        let fresh = ModelContext(context.container)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .visibleDeduplicatedByID().first?.title == "Imported task"
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskQuantityGoal>()).isEmpty
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskQuantityEntry>())
                .visibleDeduplicatedByID().count == 1
        )
    }

    @Test
    func lateProgressMakesQuantityGoalResurrectionStale() throws {
        let context = try makeTestContext()
        let taskID = try createQuantityTask(in: context.container)
        var removal = try editorDraft(
            taskID: taskID,
            container: context.container
        )
        removal.quantityGoal = nil
        removal.confirmsQuantityProgressReset = true
        _ = try coordinator(context.container).save(
            draft: removal,
            sanitizedTitle: removal.title
        )
        var resurrection = try editorDraft(
            taskID: taskID,
            container: context.container
        )
        let sibling = ModelContext(context.container)
        sibling.insert(
            TaskQuantityEntry(
                id: UUID(),
                taskID: taskID,
                amount: 20,
                deviceID: "late-entry"
            )
        )
        try sibling.save()
        resurrection.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 75,
            unitLabel: "reps"
        )

        #expect(throws: TaskLifecycleMutationError.staleDraft) {
            try coordinator(context.container).save(
                draft: resurrection,
                sanitizedTitle: resurrection.title
            )
        }

        let fresh = ModelContext(context.container)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskQuantityGoal>())
                .visibleDeduplicatedByID().isEmpty
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskQuantityEntry>())
                .visibleDeduplicatedByID().count == 1
        )
    }

    @Test
    func trimEquivalentLegacyUnitCanNormalizeWithProgress() throws {
        let context = try makeTestContext()
        let taskID = try createQuantityTask(in: context.container)
        let legacy = ModelContext(context.container)
        let goal = try #require(
            try legacy.fetch(FetchDescriptor<TaskQuantityGoal>())
                .visibleDeduplicatedByID().first
        )
        goal.unitLabel = " reps "
        goal.updatedAt = goal.updatedAt.addingTimeInterval(1)
        goal.clientMutationID = UUID()
        legacy.insert(
            TaskQuantityEntry(
                id: UUID(),
                taskID: taskID,
                amount: 20,
                deviceID: "legacy-entry"
            )
        )
        try legacy.save()
        var draft = try editorDraft(
            taskID: taskID,
            container: context.container
        )
        draft.title = "Edited title"

        _ = try coordinator(context.container).save(
            draft: draft,
            sanitizedTitle: draft.title
        )

        let fresh = ModelContext(context.container)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskQuantityGoal>())
                .visibleDeduplicatedByID().first?.unitLabel == "reps"
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskQuantityEntry>())
                .visibleDeduplicatedByID().count == 1
        )
    }
}

private extension TaskProgressDraftEditingTests {
    func coordinator(
        _ container: ModelContainer
    ) -> StoreScopedTaskLifecycleCommandCoordinator {
        StoreScopedTaskLifecycleCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "task-progress-editing-test"
        )
    }

    func createQuantityTask(in container: ModelContainer) throws -> UUID {
        var draft = TaskEditorDraft(parentID: nil)
        draft.title = "Push-ups"
        draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 50,
            unitLabel: "reps"
        )
        return try coordinator(container).save(
            draft: draft,
            sanitizedTitle: draft.title
        ).savedTaskID
    }

    func editorDraft(
        taskID: UUID,
        container: ModelContainer
    ) throws -> TaskEditorDraft {
        let context = ModelContext(container)
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "draft-reader"
        )
        return TaskEditorDraft(
            task: try #require(try repository.task(id: taskID)),
            checklistItems: [],
            quantityGoal: try repository.taskQuantityGoals().first {
                $0.taskID == taskID
            },
            recurrenceRule: try repository.taskRecurrenceRules().first {
                $0.templateTaskID == taskID
            },
            quantityEntries: try repository.taskQuantityEntries().filter {
                $0.taskID == taskID
            }
        )
    }
}
