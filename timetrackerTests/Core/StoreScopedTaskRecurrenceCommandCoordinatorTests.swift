import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedTaskRecurrenceCommandCoordinatorTests {
    @Test
    func firstCreationMaterializesACompleteCurrentDayGraphWithGoal()
        throws
    {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        )
        let root = try repository.createTask(
            title: "Health",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let template = try repository.createTask(
            title: "Daily push-ups",
            parentID: root.id,
            colorHex: "16A34A",
            iconName: "figure.strengthtraining.traditional"
        )
        template.notes = "Keep a steady pace"
        template.estimatedSeconds = 600
        let templateGoal = TaskQuantityGoal(
            taskID: template.id,
            targetAmount: 50,
            unitLabel: "push-ups",
            deviceID: "seed"
        )
        context.insert(templateGoal)
        try context.save()
        let now = try singaporeDate(
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )

        let outcome = try coordinator(context.container).createDailyRule(
            templateTaskID: template.id,
            startDayKey: "2026-07-20",
            timeZoneIdentifier: "Asia/Singapore",
            now: now
        )

        let ruleID = TaskProgressIdentity.recurrenceRuleID(
            templateTaskID: template.id
        )
        let occurrenceID = TaskProgressIdentity.recurrenceOccurrenceID(
            ruleID: ruleID,
            dayKey: "2026-07-20"
        )
        let generatedTaskID = TaskProgressIdentity.generatedTaskID(
            ruleID: ruleID,
            dayKey: "2026-07-20"
        )
        let generatedGoalID = TaskProgressIdentity.quantityGoalID(
            taskID: generatedTaskID
        )
        #expect(outcome.changedRuleTemplateTaskIDs == [template.id])
        #expect(outcome.materializations.count == 1)
        #expect(outcome.materializations.first == TaskRecurrenceMaterializationMutation(
            ruleID: ruleID,
            templateTaskID: template.id,
            occurrenceID: occurrenceID,
            generatedTaskID: generatedTaskID,
            generatedQuantityGoalID: generatedGoalID,
            affectedAncestorTaskIDs: [root.id, template.id]
        ))
        #expect(outcome.events == [
            .taskChanged(
                taskID: template.id,
                affectedAncestorIDs: [root.id]
            ),
            .taskChanged(
                taskID: generatedTaskID,
                affectedAncestorIDs: [root.id, template.id]
            ),
        ])

        let fresh = ModelContext(context.container)
        let rule = try #require(
            try fresh.fetch(FetchDescriptor<TaskRecurrenceRule>())
                .visibleDeduplicatedByID()
                .first
        )
        let occurrence = try #require(
            try fresh.fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
                .visibleDeduplicatedByID()
                .first
        )
        let generatedTask = try #require(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .visibleDeduplicatedByID()
                .first { $0.id == generatedTaskID }
        )
        let generatedGoal = try #require(
            try fresh.fetch(FetchDescriptor<TaskQuantityGoal>())
                .visibleDeduplicatedByID()
                .first { $0.id == generatedGoalID }
        )
        #expect(rule.id == ruleID)
        #expect(rule.isEnabled)
        #expect(occurrence.id == occurrenceID)
        #expect(occurrence.generatedTaskID == generatedTaskID)
        #expect(generatedTask.parentID == template.id)
        #expect(generatedTask.depth == template.depth + 1)
        #expect(
            generatedTask.path ==
                TaskHierarchyMetadata.canonicalPath(for: generatedTaskID)
        )
        #expect(generatedTask.title == template.title)
        #expect(generatedTask.colorHex == template.colorHex)
        #expect(generatedTask.iconName == template.iconName)
        #expect(generatedTask.notes == template.notes)
        #expect(generatedTask.estimatedSeconds == template.estimatedSeconds)
        #expect(generatedTask.sortOrder == -20_260_720)
        #expect(generatedTask.clientMutationID == generatedTaskID)
        #expect(generatedGoal.taskID == generatedTaskID)
        #expect(generatedGoal.targetAmount == 50)
        #expect(generatedGoal.unitLabel == "push-ups")
        #expect(generatedGoal.clientMutationID == generatedGoalID)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskQuantityEntry>())
                .isEmpty
        )
    }

    @Test
    func oldStartDayMaterializesOnlyNowWithoutBackfilling() throws {
        let context = try makeTestContext()
        let template = try makeTemplate(in: context, title: "Current only")
        let now = try singaporeDate(
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )

        _ = try coordinator(context.container).createDailyRule(
            templateTaskID: template.id,
            startDayKey: "2026-07-15",
            timeZoneIdentifier: "Asia/Singapore",
            now: now
        )

        let fresh = ModelContext(context.container)
        let occurrences = try fresh.fetch(
            FetchDescriptor<TaskRecurrenceOccurrence>()
        ).visibleDeduplicatedByID()
        #expect(occurrences.map(\.occurrenceDayKey) == ["2026-07-20"])
        let generatedIDs = Set(occurrences.map(\.generatedTaskID))
        #expect(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .visibleDeduplicatedByID()
                .filter { generatedIDs.contains($0.id) }
                .count == 1
        )
    }

    @Test
    func sameDayReplayFromAnotherCoordinatorIsAnExactNoOp() throws {
        let context = try makeTestContext()
        let template = try makeTemplate(in: context, title: "Replay")
        let now = try singaporeDate(
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )
        let firstCoordinator = coordinator(
            context.container,
            deviceID: "first-scene"
        )
        _ = try firstCoordinator.createDailyRule(
            templateTaskID: template.id,
            startDayKey: "2026-07-20",
            timeZoneIdentifier: "Asia/Singapore",
            now: now
        )
        let before = try recurrenceRevisions(in: context.container)

        let replay = try coordinator(
            context.container,
            deviceID: "second-scene"
        ).materializeCurrentDay(now: now.addingTimeInterval(60))

        #expect(replay == .noChanges)
        #expect(try recurrenceRevisions(in: context.container) == before)
        let fresh = ModelContext(context.container)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskRecurrenceRule>())
                .count == 1
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
                .count == 1
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .visibleDeduplicatedByID()
                .count == 2
        )
    }

    @Test
    func pauseAcrossMidnightAndResumeSkipsThePausedDay() throws {
        let context = try makeTestContext()
        let template = try makeTemplate(in: context, title: "Pause")
        let dayOne = try singaporeDate(
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )
        let dayTwo = try singaporeDate(
            year: 2026,
            month: 7,
            day: 21,
            hour: 12
        )
        let dayThree = try singaporeDate(
            year: 2026,
            month: 7,
            day: 22,
            hour: 12
        )
        let command = coordinator(context.container)
        _ = try command.createDailyRule(
            templateTaskID: template.id,
            startDayKey: "2026-07-20",
            timeZoneIdentifier: "Asia/Singapore",
            now: dayOne
        )
        let activeRule = try requiredRule(in: context.container)
        let paused = try command.setEnabled(
            baseline: TaskRecurrenceRuleMutationBaseline(rule: activeRule),
            isEnabled: false,
            now: dayOne.addingTimeInterval(60)
        )
        #expect(paused.materializations.isEmpty)

        let whilePaused = try coordinator(
            context.container,
            deviceID: "restarted-scene"
        ).materializeCurrentDay(now: dayTwo)
        #expect(whilePaused == .noChanges)

        let pausedRule = try requiredRule(in: context.container)
        let resumed = try command.setEnabled(
            baseline: TaskRecurrenceRuleMutationBaseline(rule: pausedRule),
            isEnabled: true,
            now: dayThree
        )

        #expect(resumed.changedRuleTemplateTaskIDs == [template.id])
        #expect(
            resumed.materializations.map(\.generatedTaskID) == [
                TaskProgressIdentity.generatedTaskID(
                    ruleID: pausedRule.id,
                    dayKey: "2026-07-22"
                ),
            ]
        )
        let fresh = ModelContext(context.container)
        let dayKeys = try fresh.fetch(
            FetchDescriptor<TaskRecurrenceOccurrence>()
        )
        .visibleDeduplicatedByID()
        .map(\.occurrenceDayKey)
        .sorted()
        #expect(dayKeys == ["2026-07-20", "2026-07-22"])
    }

    @Test
    func stagedPartialRowsBlockBackgroundRepair() throws {
        let context = try makeTestContext()
        let occurrenceOnly = try makeTemplate(
            in: context,
            title: "Occurrence only"
        )
        let taskOnly = try makeTemplate(
            in: context,
            title: "Task only"
        )
        let goalOnly = try makeTemplate(
            in: context,
            title: "Goal only"
        )
        let dayKey = "2026-07-20"
        let occurrenceRule = insertRule(
            for: occurrenceOnly,
            startDayKey: dayKey,
            into: context
        )
        let taskRule = insertRule(
            for: taskOnly,
            startDayKey: dayKey,
            into: context
        )
        let goalRule = insertRule(
            for: goalOnly,
            startDayKey: dayKey,
            into: context
        )
        let stagedOccurrence = TaskRecurrenceOccurrence(
            ruleID: occurrenceRule.id,
            templateTaskID: occurrenceOnly.id,
            occurrenceDayKey: dayKey,
            timeZoneIdentifier: "Asia/Singapore",
            deviceID: "cloud-stage"
        )
        context.insert(stagedOccurrence)
        let stagedTaskID = TaskProgressIdentity.generatedTaskID(
            ruleID: taskRule.id,
            dayKey: dayKey
        )
        let stagedTask = TaskNode(
            title: "Staged generated task",
            parentID: taskOnly.id,
            deviceID: "cloud-stage"
        )
        stagedTask.id = stagedTaskID
        context.insert(stagedTask)
        let stagedGoalTaskID = TaskProgressIdentity.generatedTaskID(
            ruleID: goalRule.id,
            dayKey: dayKey
        )
        let stagedGoal = TaskQuantityGoal(
            taskID: stagedGoalTaskID,
            targetAmount: 25,
            unitLabel: "reps",
            deviceID: "cloud-stage"
        )
        context.insert(stagedGoal)
        try context.save()
        let now = try singaporeDate(
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )

        let outcome = try coordinator(context.container)
            .materializeCurrentDay(now: now)

        #expect(outcome == .noChanges)
        let fresh = ModelContext(context.container)
        let rawOccurrences = try fresh.fetch(
            FetchDescriptor<TaskRecurrenceOccurrence>()
        )
        let rawTasks = try fresh.fetch(FetchDescriptor<TaskNode>())
        let rawGoals = try fresh.fetch(FetchDescriptor<TaskQuantityGoal>())
        #expect(rawOccurrences.map(\.id) == [stagedOccurrence.id])
        #expect(
            rawTasks.filter {
                $0.id == stagedOccurrence.generatedTaskID
            }.isEmpty
        )
        #expect(rawTasks.filter { $0.id == stagedTaskID }.count == 1)
        #expect(
            rawOccurrences.contains {
                $0.ruleID == taskRule.id || $0.ruleID == goalRule.id
            } == false
        )
        #expect(rawGoals.map(\.id) == [stagedGoal.id])
    }

    @Test
    func occurrenceAndGeneratedTaskTombstonesBlockResurrection() throws {
        let context = try makeTestContext()
        let occurrenceTemplate = try makeTemplate(
            in: context,
            title: "Occurrence tombstone"
        )
        let taskTemplate = try makeTemplate(
            in: context,
            title: "Task tombstone"
        )
        let dayKey = "2026-07-20"
        let occurrenceRule = insertRule(
            for: occurrenceTemplate,
            startDayKey: dayKey,
            into: context
        )
        let taskRule = insertRule(
            for: taskTemplate,
            startDayKey: dayKey,
            into: context
        )
        let futureTombstone = try singaporeDate(
            year: 2027,
            month: 7,
            day: 20,
            hour: 12
        )
        let occurrence = TaskRecurrenceOccurrence(
            ruleID: occurrenceRule.id,
            templateTaskID: occurrenceTemplate.id,
            occurrenceDayKey: dayKey,
            timeZoneIdentifier: "Asia/Singapore",
            deviceID: "clear"
        )
        occurrence.deletedAt = futureTombstone
        occurrence.updatedAt = futureTombstone
        context.insert(occurrence)
        let generatedTaskID = TaskProgressIdentity.generatedTaskID(
            ruleID: taskRule.id,
            dayKey: dayKey
        )
        let generatedTask = TaskNode(
            title: "Cleared generated task",
            parentID: taskTemplate.id,
            deviceID: "clear"
        )
        generatedTask.id = generatedTaskID
        generatedTask.deletedAt = futureTombstone
        generatedTask.updatedAt = futureTombstone
        context.insert(generatedTask)
        try context.save()
        let now = try singaporeDate(
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )

        let outcome = try coordinator(context.container)
            .materializeCurrentDay(now: now)

        #expect(outcome == .noChanges)
        let fresh = ModelContext(context.container)
        let occurrenceWinner = try #require(
            try fresh.fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
                .latestByID()[occurrence.id]
        )
        let taskWinner = try #require(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .latestByID()[generatedTaskID]
        )
        #expect(occurrenceWinner.deletedAt == futureTombstone)
        #expect(taskWinner.deletedAt == futureTombstone)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
                .visibleDeduplicatedByID()
                .isEmpty
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .visibleDeduplicatedByID()
                .contains { $0.id == generatedTaskID } == false
        )
    }

    @Test
    func replayPreservesUserTaskAndQuantityGoalEdits() throws {
        let context = try makeTestContext()
        let template = try makeTemplate(
            in: context,
            title: "Editable generated task"
        )
        let blueprint = TaskQuantityGoal(
            taskID: template.id,
            targetAmount: 50,
            unitLabel: "push-ups",
            deviceID: "seed"
        )
        context.insert(blueprint)
        try context.save()
        let now = try singaporeDate(
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )
        let command = coordinator(context.container)
        let created = try command.createDailyRule(
            templateTaskID: template.id,
            startDayKey: "2026-07-20",
            timeZoneIdentifier: "Asia/Singapore",
            now: now
        )
        let generatedTaskID = try #require(
            created.materializations.first?.generatedTaskID
        )
        let generatedGoalID = try #require(
            created.materializations.first?.generatedQuantityGoalID
        )

        let siblingContext = ModelContext(context.container)
        let siblingRepository = SwiftDataTaskRepository(
            context: siblingContext,
            deviceID: "user"
        )
        let destination = try siblingRepository.createTask(
            title: "Custom parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        try siblingRepository.updateTask(
            taskID: generatedTaskID,
            title: "My custom push-ups",
            parentID: destination.id,
            categoryID: nil,
            colorHex: "7C3AED",
            iconName: "star.fill",
            notes: "User-authored note",
            estimatedSeconds: 900,
            dueAt: now.addingTimeInterval(3600)
        )
        try siblingRepository.archiveTask(taskID: generatedTaskID)
        let editedGoal = try #require(
            try siblingContext.fetch(FetchDescriptor<TaskQuantityGoal>())
                .latestByID()[generatedGoalID]
        )
        editedGoal.targetAmount = 75
        editedGoal.unitLabel = "reps"
        editedGoal.updatedAt = now.addingTimeInterval(120)
        editedGoal.deviceID = "user"
        editedGoal.clientMutationID = UUID()
        try siblingContext.save()
        let editedTask = try #require(
            try siblingContext.fetch(FetchDescriptor<TaskNode>())
                .latestByID()[generatedTaskID]
        )
        let taskMutationID = editedTask.clientMutationID
        let goalMutationID = editedGoal.clientMutationID

        let replay = try coordinator(
            context.container,
            deviceID: "background"
        ).materializeCurrentDay(now: now.addingTimeInterval(300))

        #expect(replay == .noChanges)
        let fresh = ModelContext(context.container)
        let preservedTask = try #require(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .latestByID()[generatedTaskID]
        )
        let preservedGoal = try #require(
            try fresh.fetch(FetchDescriptor<TaskQuantityGoal>())
                .latestByID()[generatedGoalID]
        )
        #expect(preservedTask.title == "My custom push-ups")
        #expect(preservedTask.parentID == destination.id)
        #expect(preservedTask.notes == "User-authored note")
        #expect(preservedTask.colorHex == "7C3AED")
        #expect(preservedTask.iconName == "star.fill")
        #expect(preservedTask.estimatedSeconds == 900)
        #expect(preservedTask.isArchivedForLifecycle)
        #expect(preservedTask.clientMutationID == taskMutationID)
        #expect(preservedGoal.targetAmount == 75)
        #expect(preservedGoal.unitLabel == "reps")
        #expect(preservedGoal.clientMutationID == goalMutationID)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
                .visibleDeduplicatedByID()
                .count == 1
        )
    }

    @Test
    func injectedFailureRollsBackEveryCreationCheckpoint() throws {
        for failureStage in RecurrenceRollbackStage.allCases {
            let context = try makeTestContext()
            let template = try makeTemplate(
                in: context,
                title: "Rollback \(failureStage)"
            )
            let blueprint = TaskQuantityGoal(
                taskID: template.id,
                targetAmount: 50,
                unitLabel: "push-ups",
                deviceID: "seed"
            )
            context.insert(blueprint)
            try context.save()
            let now = try singaporeDate(
                year: 2026,
                month: 7,
                day: 20,
                hour: 12
            )
            let command = coordinator(
                context.container,
                checkpoint: { checkpoint in
                    if failureStage.matches(checkpoint) {
                        throw RecurrenceInjectedFailure.stop
                    }
                }
            )

            #expect(throws: RecurrenceInjectedFailure.self) {
                try command.createDailyRule(
                    templateTaskID: template.id,
                    startDayKey: "2026-07-20",
                    timeZoneIdentifier: "Asia/Singapore",
                    now: now
                )
            }

            let fresh = ModelContext(context.container)
            #expect(
                try fresh.fetch(FetchDescriptor<TaskRecurrenceRule>())
                    .isEmpty
            )
            #expect(
                try fresh.fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
                    .isEmpty
            )
            #expect(
                try fresh.fetch(FetchDescriptor<TaskNode>())
                    .visibleDeduplicatedByID()
                    .map(\.id) == [template.id]
            )
            #expect(
                try fresh.fetch(FetchDescriptor<TaskQuantityGoal>())
                    .visibleDeduplicatedByID()
                    .map(\.id) == [blueprint.id]
            )
        }
    }
}

private extension StoreScopedTaskRecurrenceCommandCoordinatorTests {
    struct RecurrenceRevisionSnapshot: Equatable {
        let ruleMutationIDs: [UUID: UUID]
        let occurrenceMutationIDs: [UUID: UUID]
        let taskMutationIDs: [UUID: UUID]
        let goalMutationIDs: [UUID: UUID]
    }

    func coordinator(
        _ container: ModelContainer,
        deviceID: String = "recurrence-test",
        checkpoint: @escaping
        (TaskRecurrenceMutationCheckpoint) throws -> Void = { _ in }
    ) -> StoreScopedTaskRecurrenceCommandCoordinator {
        StoreScopedTaskRecurrenceCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: deviceID,
            didReachCheckpoint: checkpoint
        )
    }

    func makeTemplate(
        in context: ModelContext,
        title: String
    ) throws -> TaskNode {
        try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: title,
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
    }

    @discardableResult
    func insertRule(
        for template: TaskNode,
        startDayKey: String,
        into context: ModelContext
    ) -> TaskRecurrenceRule {
        let rule = TaskRecurrenceRule(
            templateTaskID: template.id,
            startDayKey: startDayKey,
            timeZoneIdentifier: "Asia/Singapore",
            deviceID: "cloud-stage"
        )
        context.insert(rule)
        return rule
    }

    func requiredRule(
        in container: ModelContainer
    ) throws -> TaskRecurrenceRule {
        try #require(
            try ModelContext(container)
                .fetch(FetchDescriptor<TaskRecurrenceRule>())
                .visibleDeduplicatedByID()
                .first
        )
    }

    func recurrenceRevisions(
        in container: ModelContainer
    ) throws -> RecurrenceRevisionSnapshot {
        let context = ModelContext(container)
        return try RecurrenceRevisionSnapshot(
            ruleMutationIDs: Dictionary(
                uniqueKeysWithValues:
                context.fetch(FetchDescriptor<TaskRecurrenceRule>())
                    .map { ($0.id, $0.clientMutationID) }
            ),
            occurrenceMutationIDs: Dictionary(
                uniqueKeysWithValues:
                context.fetch(
                    FetchDescriptor<TaskRecurrenceOccurrence>()
                ).map { ($0.id, $0.clientMutationID) }
            ),
            taskMutationIDs: Dictionary(
                uniqueKeysWithValues:
                context.fetch(FetchDescriptor<TaskNode>())
                    .map { ($0.id, $0.clientMutationID) }
            ),
            goalMutationIDs: Dictionary(
                uniqueKeysWithValues:
                context.fetch(FetchDescriptor<TaskQuantityGoal>())
                    .map { ($0.id, $0.clientMutationID) }
            )
        )
    }

    func singaporeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = try #require(
            TimeZone(identifier: "Asia/Singapore")
        )
        return try #require(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour
                )
            )
        )
    }
}

private enum RecurrenceRollbackStage: String, CaseIterable {
    case rule
    case generatedTask
    case quantityGoal
    case occurrence

    func matches(
        _ checkpoint: TaskRecurrenceMutationCheckpoint
    ) -> Bool {
        switch (self, checkpoint) {
        case (.rule, .ruleCreated),
             (.generatedTask, .generatedTaskCreated),
             (.quantityGoal, .quantityGoalCreated),
             (.occurrence, .occurrenceCreated):
            true
        default:
            false
        }
    }
}

private enum RecurrenceInjectedFailure: Error {
    case stop
}
