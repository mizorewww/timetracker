import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct TaskProgressDraftPersistenceTests {
    @Test
    func newDailyQuantityDraftSavesACompleteCurrentDayGraph()
        throws {
        let context = try makeTestContext()
        let now = try singaporeDate(day: 21)
        var draft = TaskEditorDraft(parentID: nil)
        draft.title = "Daily push-ups"
        draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 50,
            unitLabel: " push-ups "
        )
        draft.dailyRecurrence = TaskDailyRecurrenceDraft(
            startDayKey: "2026-07-21",
            timeZoneIdentifier: "Asia/Singapore"
        )

        let outcome = try coordinator(context.container).save(
            draft: draft,
            sanitizedTitle: draft.title,
            now: now
        )

        let fresh = ModelContext(context.container)
        let tasks = try fresh.fetch(FetchDescriptor<TaskNode>())
            .visibleDeduplicatedByID()
        let rules = try fresh.fetch(FetchDescriptor<TaskRecurrenceRule>())
            .visibleDeduplicatedByID()
        let occurrences = try fresh.fetch(
            FetchDescriptor<TaskRecurrenceOccurrence>()
        ).visibleDeduplicatedByID()
        let goals = try fresh.fetch(FetchDescriptor<TaskQuantityGoal>())
            .visibleDeduplicatedByID()
        let template = try #require(
            tasks.first { $0.id == outcome.savedTaskID }
        )
        let occurrence = try #require(occurrences.first)
        let generated = try #require(
            tasks.first { $0.id == occurrence.generatedTaskID }
        )
        let templateGoal = try #require(
            goals.first { $0.taskID == template.id }
        )
        let generatedGoal = try #require(
            goals.first { $0.taskID == generated.id }
        )

        #expect(tasks.count == 2)
        #expect(rules.count == 1)
        #expect(occurrences.count == 1)
        #expect(goals.count == 2)
        #expect(generated.parentID == template.id)
        #expect(occurrence.occurrenceDayKey == "2026-07-21")
        #expect(templateGoal.targetAmount == 50)
        #expect(templateGoal.unitLabel == "push-ups")
        #expect(generatedGoal.targetAmount == 50)
        #expect(generatedGoal.unitLabel == "push-ups")
        #expect(outcome.recurrenceOutcome.materializations.count == 1)

        let directWorkIDs = TaskTrackingAvailabilityService()
            .directWorkTaskIDs(
                tasks: tasks,
                recurrenceRules: rules,
                recurrenceOccurrences: occurrences
            )
        #expect(directWorkIDs.contains(template.id) == false)
        #expect(directWorkIDs.contains(generated.id))
    }

    @Test
    func recoveredProposedIDRetryKeepsOneCompleteProgressGraph()
        throws {
        let context = try makeTestContext()
        let proposedTaskID = UUID()
        var draft = TaskEditorDraft(parentID: nil)
        draft.title = "Recovered daily push-ups"
        draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 50,
            unitLabel: "reps"
        )
        draft.dailyRecurrence = TaskDailyRecurrenceDraft(
            startDayKey: "2026-07-21",
            timeZoneIdentifier: "Asia/Singapore"
        )
        let command = coordinator(context.container)

        let first = try command.save(
            draft: draft,
            sanitizedTitle: draft.title,
            proposedTaskID: proposedTaskID,
            now: try singaporeDate(day: 21)
        )
        let retry = try command.save(
            draft: draft,
            sanitizedTitle: draft.title,
            proposedTaskID: proposedTaskID,
            now: try singaporeDate(day: 21, hour: 13)
        )

        let fresh = ModelContext(context.container)
        #expect(first.savedTaskID == proposedTaskID)
        #expect(retry.savedTaskID == proposedTaskID)
        #expect(retry.recurrenceOutcome == .noChanges)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .visibleDeduplicatedByID().count == 2
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskQuantityGoal>())
                .visibleDeduplicatedByID().count == 2
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskRecurrenceRule>())
                .visibleDeduplicatedByID().count == 1
        )
        #expect(
            try fresh.fetch(
                FetchDescriptor<TaskRecurrenceOccurrence>()
            ).visibleDeduplicatedByID().count == 1
        )
    }

    @Test
    func everyCombinedCreationCheckpointRollsBackTheWholeGraph()
        throws {
        for stage in CombinedCreationFailureStage.allCases {
            let context = try makeTestContext()
            var draft = TaskEditorDraft(parentID: nil)
            draft.title = "Rollback \(stage)"
            draft.quantityGoal = TaskQuantityGoalDraft(
                targetAmount: 50,
                unitLabel: "push-ups"
            )
            draft.dailyRecurrence = TaskDailyRecurrenceDraft(
                startDayKey: "2026-07-21",
                timeZoneIdentifier: "Asia/Singapore"
            )
            let command = coordinator(
                context.container,
                checkpoint: { checkpoint in
                    if stage.matches(checkpoint) {
                        throw InjectedDraftFailure.stop
                    }
                }
            )

            #expect(throws: InjectedDraftFailure.self) {
                try command.save(
                    draft: draft,
                    sanitizedTitle: draft.title,
                    now: try singaporeDate(day: 21)
                )
            }

            let fresh = ModelContext(context.container)
            #expect(try fresh.fetch(FetchDescriptor<TaskNode>()).isEmpty)
            #expect(
                try fresh.fetch(FetchDescriptor<TaskQuantityGoal>())
                    .isEmpty
            )
            #expect(
                try fresh.fetch(FetchDescriptor<TaskRecurrenceRule>())
                    .isEmpty
            )
            #expect(
                try fresh.fetch(
                    FetchDescriptor<TaskRecurrenceOccurrence>()
                ).isEmpty
            )
        }
    }

    @Test
    func invalidQuantityDraftFailsBeforeWritingAnything() throws {
        let context = try makeTestContext()
        var draft = TaskEditorDraft(parentID: nil)
        draft.title = "Invalid quantity"
        draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 0,
            unitLabel: "reps"
        )

        #expect(throws: TaskProgressDraftMutationError.invalidTargetAmount) {
            try coordinator(context.container).save(
                draft: draft,
                sanitizedTitle: draft.title
            )
        }
        #expect(
            try ModelContext(context.container)
                .fetch(FetchDescriptor<TaskNode>())
                .isEmpty
        )
    }

    @Test
    func staleGoalMutationCannotBeOverwrittenByAnEditorDraft() throws {
        let context = try makeTestContext()
        var newDraft = TaskEditorDraft(parentID: nil)
        newDraft.title = "Quantity"
        newDraft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 50,
            unitLabel: "reps"
        )
        let created = try coordinator(context.container).save(
            draft: newDraft,
            sanitizedTitle: newDraft.title
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let task = try #require(store.task(for: created.savedTaskID))
        var staleDraft = store.editorDraft(for: task)

        let sibling = ModelContext(context.container)
        let goal = try #require(
            try sibling.fetch(FetchDescriptor<TaskQuantityGoal>())
                .visibleDeduplicatedByID()
                .first
        )
        goal.targetAmount = 75
        goal.updatedAt = goal.updatedAt.addingTimeInterval(1)
        goal.clientMutationID = UUID()
        try sibling.save()
        staleDraft.quantityGoal?.targetAmount = 100

        #expect(throws: TaskLifecycleMutationError.staleDraft) {
            try coordinator(context.container).save(
                draft: staleDraft,
                sanitizedTitle: staleDraft.title
            )
        }
        let persisted = try #require(
            try ModelContext(context.container)
                .fetch(FetchDescriptor<TaskQuantityGoal>())
                .visibleDeduplicatedByID()
                .first
        )
        #expect(persisted.targetAmount == 75)
    }

    @Test
    func staleRecurrenceMutationCannotBeOverwrittenByAnEditorDraft()
        throws {
        let context = try makeTestContext()
        var newDraft = TaskEditorDraft(parentID: nil)
        newDraft.title = "Daily"
        newDraft.dailyRecurrence = TaskDailyRecurrenceDraft(
            startDayKey: "2026-07-21",
            timeZoneIdentifier: "Asia/Singapore"
        )
        let created = try coordinator(context.container).save(
            draft: newDraft,
            sanitizedTitle: newDraft.title,
            now: try singaporeDate(day: 21)
        )
        var staleDraft = try editorDraft(
            taskID: created.savedTaskID,
            container: context.container
        )

        let sibling = ModelContext(context.container)
        let rule = try #require(
            try sibling.fetch(FetchDescriptor<TaskRecurrenceRule>())
                .visibleDeduplicatedByID().first
        )
        rule.isEnabled = false
        rule.updatedAt = rule.updatedAt.addingTimeInterval(1)
        rule.clientMutationID = UUID()
        try sibling.save()
        staleDraft.title = "Must not save"
        staleDraft.dailyRecurrence?.isEnabled = true

        #expect(throws: TaskLifecycleMutationError.staleDraft) {
            try coordinator(context.container).save(
                draft: staleDraft,
                sanitizedTitle: staleDraft.title,
                now: try singaporeDate(day: 22)
            )
        }

        let fresh = ModelContext(context.container)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .visibleDeduplicatedByID().first {
                    $0.id == created.savedTaskID
                }?.title == "Daily"
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskRecurrenceRule>())
                .visibleDeduplicatedByID().first?.isEnabled == false
        )
        #expect(
            try fresh.fetch(
                FetchDescriptor<TaskRecurrenceOccurrence>()
            ).visibleDeduplicatedByID().count == 1
        )
    }

    @Test
    func pausedDraftResumesOnlyTheCurrentDay() throws {
        let context = try makeTestContext()
        var newDraft = TaskEditorDraft(parentID: nil)
        newDraft.title = "Daily"
        newDraft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 50,
            unitLabel: "reps"
        )
        newDraft.dailyRecurrence = TaskDailyRecurrenceDraft(
            startDayKey: "2026-07-21",
            timeZoneIdentifier: "Asia/Singapore"
        )
        let command = coordinator(context.container)
        let created = try command.save(
            draft: newDraft,
            sanitizedTitle: newDraft.title,
            now: try singaporeDate(day: 21)
        )

        var paused = try editorDraft(
            taskID: created.savedTaskID,
            container: context.container
        )
        paused.dailyRecurrence?.isEnabled = false
        _ = try command.save(
            draft: paused,
            sanitizedTitle: paused.title,
            now: try singaporeDate(day: 21, hour: 13)
        )

        var resumed = try editorDraft(
            taskID: created.savedTaskID,
            container: context.container
        )
        resumed.dailyRecurrence?.isEnabled = true
        _ = try command.save(
            draft: resumed,
            sanitizedTitle: resumed.title,
            now: try singaporeDate(day: 23)
        )

        let dayKeys = try ModelContext(context.container).fetch(
            FetchDescriptor<TaskRecurrenceOccurrence>()
        ).visibleDeduplicatedByID().map(\.occurrenceDayKey).sorted()
        #expect(dayKeys == ["2026-07-21", "2026-07-23"])
    }
}

private extension TaskProgressDraftPersistenceTests {
    func coordinator(
        _ container: ModelContainer,
        checkpoint: @escaping
            (TaskDraftMutationCheckpoint) throws -> Void = { _ in }
    ) -> StoreScopedTaskLifecycleCommandCoordinator {
        StoreScopedTaskLifecycleCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "task-progress-draft-test",
            didReachDraftCheckpoint: checkpoint
        )
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
        let task = try #require(try repository.task(id: taskID))
        let goals = try repository.taskQuantityGoals()
        let rules = try repository.taskRecurrenceRules()
        let entries = try repository.taskQuantityEntries()
        return TaskEditorDraft(
            task: task,
            checklistItems: [],
            quantityGoal: goals.first { $0.taskID == taskID },
            recurrenceRule: rules.first { $0.templateTaskID == taskID },
            quantityEntries: entries.filter { $0.taskID == taskID }
        )
    }

    func singaporeDate(
        day: Int,
        hour: Int = 12
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(
            TimeZone(identifier: "Asia/Singapore")
        )
        return try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: day,
                    hour: hour
                )
            )
        )
    }
}

private enum InjectedDraftFailure: Error {
    case stop
}

private enum CombinedCreationFailureStage: CaseIterable {
    case task
    case templateGoal
    case rule
    case generatedTask
    case generatedGoal
    case occurrence

    func matches(_ checkpoint: TaskDraftMutationCheckpoint) -> Bool {
        switch (self, checkpoint) {
        case (.task, .taskAndChecklistSaved),
             (.templateGoal, .quantityGoalChanged),
             (.rule, .recurrence(.ruleCreated)),
             (.generatedTask, .recurrence(.generatedTaskCreated)),
             (.generatedGoal, .recurrence(.quantityGoalCreated)),
             (.occurrence, .recurrence(.occurrenceCreated)):
            true
        default:
            false
        }
    }
}
