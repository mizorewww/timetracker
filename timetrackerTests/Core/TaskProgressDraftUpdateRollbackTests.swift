import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct TaskProgressDraftUpdateRollbackTests {
    @Test
    func quantityGoalUpdateAndRemovalCheckpointFailuresRollBack()
        throws
    {
        for operation in QuantityRollbackOperation.allCases {
            let context = try makeTestContext()
            let taskID = try createQuantityTask(
                in: context.container,
                withEntry: operation == .remove
            )
            let before = try graphFingerprint(context.container)
            var draft = try editorDraft(
                taskID: taskID,
                container: context.container
            )
            draft.title = "Must roll back"
            switch operation {
            case .update:
                draft.quantityGoal?.targetAmount = 75
            case .remove:
                draft.quantityGoal = nil
                draft.confirmsQuantityProgressReset = true
            }
            let command = coordinator(
                context.container,
                checkpoint: { checkpoint in
                    guard case .quantityGoalChanged = checkpoint else {
                        return
                    }
                    throw InjectedUpdateFailure.stop
                }
            )

            #expect(throws: InjectedUpdateFailure.self) {
                try command.save(
                    draft: draft,
                    sanitizedTitle: draft.title
                )
            }
            #expect(try graphFingerprint(context.container) == before)
        }
    }

    @Test
    func everyResumeCheckpointFailureRollsBackTheExistingGraph()
        throws
    {
        for stage in ResumeRollbackStage.allCases {
            let context = try makeTestContext()
            let taskID = try createDailyQuantityTask(
                in: context.container
            )
            var paused = try editorDraft(
                taskID: taskID,
                container: context.container
            )
            paused.dailyRecurrence?.isEnabled = false
            _ = try coordinator(context.container).save(
                draft: paused,
                sanitizedTitle: paused.title,
                now: singaporeDate(day: 21, hour: 13)
            )
            let before = try graphFingerprint(context.container)
            var resumed = try editorDraft(
                taskID: taskID,
                container: context.container
            )
            resumed.title = "Must roll back"
            resumed.dailyRecurrence?.isEnabled = true
            let command = coordinator(
                context.container,
                checkpoint: { checkpoint in
                    if stage.matches(checkpoint) {
                        throw InjectedUpdateFailure.stop
                    }
                }
            )

            #expect(throws: InjectedUpdateFailure.self) {
                try command.save(
                    draft: resumed,
                    sanitizedTitle: resumed.title,
                    now: singaporeDate(day: 22)
                )
            }
            #expect(try graphFingerprint(context.container) == before)
        }
    }
}

private extension TaskProgressDraftUpdateRollbackTests {
    func coordinator(
        _ container: ModelContainer,
        checkpoint: @escaping
        (TaskDraftMutationCheckpoint) throws -> Void = { _ in }
    ) -> StoreScopedTaskLifecycleCommandCoordinator {
        StoreScopedTaskLifecycleCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "task-progress-update-rollback-test",
            didReachDraftCheckpoint: checkpoint
        )
    }

    func createQuantityTask(
        in container: ModelContainer,
        withEntry: Bool
    ) throws -> UUID {
        var draft = TaskEditorDraft(parentID: nil)
        draft.title = "Push-ups"
        draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 50,
            unitLabel: "reps"
        )
        let taskID = try coordinator(container).save(
            draft: draft,
            sanitizedTitle: draft.title
        ).savedTaskID
        if withEntry {
            let context = ModelContext(container)
            context.insert(
                TaskQuantityEntry(
                    id: UUID(),
                    taskID: taskID,
                    amount: 20,
                    deviceID: "rollback-entry"
                )
            )
            try context.save()
        }
        return taskID
    }

    func createDailyQuantityTask(
        in container: ModelContainer
    ) throws -> UUID {
        var draft = TaskEditorDraft(parentID: nil)
        draft.title = "Daily push-ups"
        draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 50,
            unitLabel: "reps"
        )
        draft.dailyRecurrence = TaskDailyRecurrenceDraft(
            startDayKey: "2026-07-21",
            timeZoneIdentifier: "Asia/Singapore"
        )
        return try coordinator(container).save(
            draft: draft,
            sanitizedTitle: draft.title,
            now: singaporeDate(day: 21)
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
        return try TaskEditorDraft(
            task: #require(try repository.task(id: taskID)),
            checklistItems: [],
            quantityGoal: repository.taskQuantityGoals().first {
                $0.taskID == taskID
            },
            recurrenceRule: repository.taskRecurrenceRules().first {
                $0.templateTaskID == taskID
            },
            quantityEntries: repository.taskQuantityEntries().filter {
                $0.taskID == taskID
            }
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

    func graphFingerprint(
        _ container: ModelContainer
    ) throws -> [String] {
        let context = ModelContext(container)
        var values = try context.fetch(FetchDescriptor<TaskNode>()).map {
            "task|\($0.id)|\($0.title)|\($0.parentID?.uuidString ?? "-")|" +
                "\($0.clientMutationID)|\($0.updatedAt.timeIntervalSince1970)|" +
                "\($0.deletedAt?.timeIntervalSince1970 ?? -1)"
        }
        values += try context.fetch(
            FetchDescriptor<TaskQuantityGoal>()
        ).map {
            "goal|\($0.id)|\($0.taskID)|\($0.targetAmount)|" +
                "\($0.unitLabel)|\($0.clientMutationID)|" +
                "\($0.updatedAt.timeIntervalSince1970)|" +
                "\($0.deletedAt?.timeIntervalSince1970 ?? -1)"
        }
        values += try context.fetch(
            FetchDescriptor<TaskQuantityEntry>()
        ).map {
            "entry|\($0.id)|\($0.taskID)|\($0.amount)|" +
                "\($0.clientMutationID)|\($0.updatedAt.timeIntervalSince1970)|" +
                "\($0.deletedAt?.timeIntervalSince1970 ?? -1)"
        }
        values += try context.fetch(
            FetchDescriptor<TaskRecurrenceRule>()
        ).map {
            "rule|\($0.id)|\($0.templateTaskID)|\($0.isEnabled)|" +
                "\($0.clientMutationID)|\($0.updatedAt.timeIntervalSince1970)|" +
                "\($0.deletedAt?.timeIntervalSince1970 ?? -1)"
        }
        values += try context.fetch(
            FetchDescriptor<TaskRecurrenceOccurrence>()
        ).map {
            "occurrence|\($0.id)|\($0.ruleID)|\($0.occurrenceDayKey)|" +
                "\($0.generatedTaskID)|\($0.clientMutationID)|" +
                "\($0.updatedAt.timeIntervalSince1970)|" +
                "\($0.deletedAt?.timeIntervalSince1970 ?? -1)"
        }
        return values.sorted()
    }
}

private enum QuantityRollbackOperation: CaseIterable {
    case update
    case remove
}

private enum ResumeRollbackStage: CaseIterable {
    case rule
    case generatedTask
    case quantityGoal
    case occurrence

    func matches(_ checkpoint: TaskDraftMutationCheckpoint) -> Bool {
        switch (self, checkpoint) {
        case (.rule, .recurrence(.ruleUpdated)),
             (.generatedTask, .recurrence(.generatedTaskCreated)),
             (.quantityGoal, .recurrence(.quantityGoalCreated)),
             (.occurrence, .recurrence(.occurrenceCreated)):
            true
        default:
            false
        }
    }
}

private enum InjectedUpdateFailure: Error {
    case stop
}
