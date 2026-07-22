import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedAITaskPlanCommandCoordinatorTests {
    @Test
    func createsCategoriesTopologicalTasksAssignmentsAndChecklists() throws {
        let context = try makeTestContext()
        let fixture = makePlanFixture()

        let outcome = try coordinator(container: context.container).apply(fixture.draft)

        #expect(outcome.didCreate)
        #expect(outcome.createdCategoryIDs == [fixture.categoryID])
        #expect(outcome.createdTaskIDs == [fixture.childTaskID, fixture.rootTaskID])
        #expect(outcome.firstRootTaskID == fixture.rootTaskID)
        #expect(
            outcome.events == [
                .taskChanged(taskID: nil, affectedAncestorIDs: []),
                .checklistChanged(taskID: nil, affectedAncestorIDs: []),
            ]
        )

        let freshContext = ModelContext(context.container)
        let categories = try freshContext.fetch(FetchDescriptor<TaskCategory>())
        #expect(categories.map(\.id) == [fixture.categoryID])
        #expect(categories.first?.title == "Work")

        let tasks = try freshContext.fetch(FetchDescriptor<TaskNode>())
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let root = try #require(taskByID[fixture.rootTaskID])
        let child = try #require(taskByID[fixture.childTaskID])
        #expect(root.parentID == nil)
        #expect(root.notes == "Deliver this week")
        #expect(root.estimatedSeconds == 45 * 60)
        #expect(child.parentID == root.id)
        #expect(child.depth == root.depth + 1)
        #expect(child.path.isEmpty == false)

        let assignments = try freshContext.fetch(
            FetchDescriptor<TaskCategoryAssignment>()
        )
        #expect(assignments.count == 1)
        #expect(assignments.first?.taskID == root.id)
        #expect(assignments.first?.categoryID == fixture.categoryID)

        let checklistItems = try freshContext.fetch(FetchDescriptor<ChecklistItem>())
        #expect(checklistItems.count == 2)
        #expect(Set(checklistItems.map(\.taskID)) == [fixture.childTaskID])
        #expect(Set(checklistItems.map(\.title)) == ["Draft", "Review"])
        let checklistVisuals = try freshContext.fetch(
            FetchDescriptor<ChecklistItemVisual>()
        )
        #expect(checklistVisuals.count == 2)
        #expect(
            Set(checklistVisuals.map(\.checklistItemID)) ==
                Set(checklistItems.map(\.id))
        )
    }

    @Test
    func quantityAndDailyRecurrenceMaterializeACompleteGraphAndReplayOnce()
        throws {
        let context = try makeTestContext()
        let now = try singaporeDate(day: 22)
        let fixture = makePlanFixture(
            quantityGoal: TaskQuantityGoalDraft(
                targetAmount: 50,
                unitLabel: " push-ups "
            ),
            dailyRecurrence: TaskDailyRecurrenceDraft(
                startDayKey: "2026-07-22",
                timeZoneIdentifier: "Asia/Singapore"
            )
        )
        var checkpoints: [AITaskPlanMutationCheckpoint] = []
        let command = coordinator(
            container: context.container,
            checkpoint: { checkpoints.append($0) }
        )

        let first = try command.apply(fixture.draft, now: now)
        let checkpointCountAfterFirstApply = checkpoints.count
        let replay = try command.apply(fixture.draft, now: now)

        #expect(first.didCreate)
        #expect(replay.didCreate == false)
        #expect(checkpoints.count == checkpointCountAfterFirstApply)

        let freshContext = ModelContext(context.container)
        let tasks = try freshContext.fetch(FetchDescriptor<TaskNode>())
            .visibleDeduplicatedByID()
        let rules = try freshContext.fetch(
            FetchDescriptor<TaskRecurrenceRule>()
        ).visibleDeduplicatedByID()
        let occurrences = try freshContext.fetch(
            FetchDescriptor<TaskRecurrenceOccurrence>()
        ).visibleDeduplicatedByID()
        let goals = try freshContext.fetch(
            FetchDescriptor<TaskQuantityGoal>()
        ).visibleDeduplicatedByID()
        let ruleID = TaskProgressIdentity.recurrenceRuleID(
            templateTaskID: fixture.rootTaskID
        )
        let generatedTaskID = TaskProgressIdentity.generatedTaskID(
            ruleID: ruleID,
            dayKey: "2026-07-22"
        )
        let occurrenceID = TaskProgressIdentity.recurrenceOccurrenceID(
            ruleID: ruleID,
            dayKey: "2026-07-22"
        )
        let templateGoalID = TaskProgressIdentity.quantityGoalID(
            taskID: fixture.rootTaskID
        )
        let generatedGoalID = TaskProgressIdentity.quantityGoalID(
            taskID: generatedTaskID
        )
        let generatedTask = try #require(
            tasks.first { $0.id == generatedTaskID }
        )
        let templateGoal = try #require(
            goals.first { $0.id == templateGoalID }
        )
        let generatedGoal = try #require(
            goals.first { $0.id == generatedGoalID }
        )

        #expect(tasks.count == 3)
        #expect(rules.count == 1)
        #expect(rules.first?.id == ruleID)
        #expect(occurrences.count == 1)
        #expect(occurrences.first?.id == occurrenceID)
        #expect(occurrences.first?.generatedTaskID == generatedTaskID)
        #expect(generatedTask.parentID == fixture.rootTaskID)
        #expect(goals.count == 2)
        #expect(templateGoal.targetAmount == 50)
        #expect(templateGoal.unitLabel == "push-ups")
        #expect(generatedGoal.targetAmount == 50)
        #expect(generatedGoal.unitLabel == "push-ups")
        #expect(
            checkpoints.contains(
                .progress(
                    taskID: fixture.rootTaskID,
                    checkpoint: .quantityGoalChanged(templateGoalID)
                )
            )
        )
        #expect(
            checkpoints.contains(
                .progress(
                    taskID: fixture.rootTaskID,
                    checkpoint: .recurrence(.ruleCreated(ruleID))
                )
            )
        )
        #expect(
            checkpoints.contains(
                .progress(
                    taskID: fixture.rootTaskID,
                    checkpoint: .recurrence(
                        .generatedTaskCreated(generatedTaskID)
                    )
                )
            )
        )
        #expect(
            checkpoints.contains(
                .progress(
                    taskID: fixture.rootTaskID,
                    checkpoint: .recurrence(
                        .quantityGoalCreated(generatedGoalID)
                    )
                )
            )
        )
        #expect(
            checkpoints.contains(
                .progress(
                    taskID: fixture.rootTaskID,
                    checkpoint: .recurrence(
                        .occurrenceCreated(occurrenceID)
                    )
                )
            )
        )
    }

    @Test
    func thrownStepRollsBackEveryCreatedFact() throws {
        enum InjectedFailure: Error {
            case stop
        }

        let context = try makeTestContext()
        let fixture = makePlanFixture()
        let coordinator = StoreScopedAITaskPlanCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "ai-test",
            didReachCheckpoint: { checkpoint in
                guard case .taskCreated = checkpoint else { return }
                throw InjectedFailure.stop
            }
        )

        #expect(throws: InjectedFailure.self) {
            try coordinator.apply(fixture.draft)
        }

        let freshContext = ModelContext(context.container)
        #expect(try freshContext.fetch(FetchDescriptor<TaskCategory>()).isEmpty)
        #expect(try freshContext.fetch(FetchDescriptor<TaskNode>()).isEmpty)
        #expect(
            try freshContext.fetch(FetchDescriptor<TaskCategoryAssignment>()).isEmpty
        )
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
        #expect(
            try freshContext.fetch(FetchDescriptor<ChecklistItemVisual>()).isEmpty
        )
    }

    @Test
    func everyProgressCheckpointRollsBackTheWholePlan() throws {
        let now = try singaporeDate(day: 22)

        for stage in AIPlanProgressFailureStage.allCases {
            let context = try makeTestContext()
            let fixture = makePlanFixture(
                quantityGoal: TaskQuantityGoalDraft(
                    targetAmount: 50,
                    unitLabel: "push-ups"
                ),
                dailyRecurrence: TaskDailyRecurrenceDraft(
                    startDayKey: "2026-07-22",
                    timeZoneIdentifier: "Asia/Singapore"
                )
            )
            let command = coordinator(
                container: context.container,
                checkpoint: { checkpoint in
                    if stage.matches(
                        checkpoint,
                        taskID: fixture.rootTaskID
                    ) {
                        throw InjectedAIPlanFailure.stop
                    }
                }
            )

            #expect(throws: InjectedAIPlanFailure.self) {
                try command.apply(fixture.draft, now: now)
            }

            let freshContext = ModelContext(context.container)
            #expect(
                try freshContext.fetch(
                    FetchDescriptor<TaskCategory>()
                ).isEmpty
            )
            #expect(
                try freshContext.fetch(FetchDescriptor<TaskNode>()).isEmpty
            )
            #expect(
                try freshContext.fetch(
                    FetchDescriptor<TaskCategoryAssignment>()
                ).isEmpty
            )
            #expect(
                try freshContext.fetch(
                    FetchDescriptor<ChecklistItem>()
                ).isEmpty
            )
            #expect(
                try freshContext.fetch(
                    FetchDescriptor<ChecklistItemVisual>()
                ).isEmpty
            )
            #expect(
                try freshContext.fetch(
                    FetchDescriptor<TaskQuantityGoal>()
                ).isEmpty
            )
            #expect(
                try freshContext.fetch(
                    FetchDescriptor<TaskRecurrenceRule>()
                ).isEmpty
            )
            #expect(
                try freshContext.fetch(
                    FetchDescriptor<TaskRecurrenceOccurrence>()
                ).isEmpty
            )
        }
    }

    @Test
    func appleHealthManagedCategoryAndTaskIdentitiesRejectTheWholePlan()
        throws {
        let healthPlan = AppleHealthTaskCatalog.plan(
            for: AppleHealthTaskCatalog.allRoles
        )
        let managedCategoryID = try #require(
            healthPlan.categories.first?.id
        )
        let managedTaskID = try #require(
            AppleHealthTaskCatalog.syncOnlyTaskIDs.first
        )
        let fixtures = [
            makePlanFixture(categoryID: managedCategoryID),
            makePlanFixture(rootTaskID: managedTaskID),
        ]

        for fixture in fixtures {
            let context = try makeTestContext()

            #expect(
                throws:
                    StoreScopedAITaskPlanMutationError.identityConflict
            ) {
                try coordinator(container: context.container)
                    .apply(fixture.draft)
            }

            let freshContext = ModelContext(context.container)
            #expect(
                try freshContext.fetch(
                    FetchDescriptor<TaskCategory>()
                ).isEmpty
            )
            #expect(
                try freshContext.fetch(FetchDescriptor<TaskNode>()).isEmpty
            )
            #expect(
                try freshContext.fetch(
                    FetchDescriptor<TaskCategoryAssignment>()
                ).isEmpty
            )
            #expect(
                try freshContext.fetch(
                    FetchDescriptor<ChecklistItem>()
                ).isEmpty
            )
            #expect(
                try freshContext.fetch(
                    FetchDescriptor<TaskQuantityGoal>()
                ).isEmpty
            )
            #expect(
                try freshContext.fetch(
                    FetchDescriptor<TaskRecurrenceRule>()
                ).isEmpty
            )
            #expect(
                try freshContext.fetch(
                    FetchDescriptor<TaskRecurrenceOccurrence>()
                ).isEmpty
            )
        }
    }

    @Test
    func replayOfTheSameDraftIsAnIdempotentSuccess() throws {
        let context = try makeTestContext()
        let fixture = makePlanFixture()
        let coordinator = coordinator(container: context.container)

        let first = try coordinator.apply(fixture.draft)
        let second = try coordinator.apply(fixture.draft)

        #expect(first.didCreate)
        #expect(second.didCreate == false)
        #expect(second.createdCategoryIDs.isEmpty)
        #expect(second.createdTaskIDs.isEmpty)
        #expect(second.firstRootTaskID == fixture.rootTaskID)
        #expect(second.events.isEmpty)

        let freshContext = ModelContext(context.container)
        #expect(try freshContext.fetch(FetchDescriptor<TaskCategory>()).count == 1)
        #expect(try freshContext.fetch(FetchDescriptor<TaskNode>()).count == 2)
        #expect(
            try freshContext.fetch(FetchDescriptor<TaskCategoryAssignment>()).count == 1
        )
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItem>()).count == 2)
        #expect(
            try freshContext.fetch(FetchDescriptor<ChecklistItemVisual>()).count == 2
        )
    }

    @Test
    func mixedPersistedIdentitiesRejectWithoutCompletingThePlan() throws {
        let context = try makeTestContext()
        let fixture = makePlanFixture()
        _ = try SwiftDataTaskRepository(
            context: context,
            deviceID: "preexisting"
        ).createCategory(
            proposedID: fixture.categoryID,
            title: "Preexisting",
            colorHex: nil,
            iconName: nil,
            includesInForecast: true
        )

        #expect(throws: StoreScopedAITaskPlanMutationError.identityConflict) {
            try coordinator(container: context.container).apply(fixture.draft)
        }

        let freshContext = ModelContext(context.container)
        let categories = try freshContext.fetch(FetchDescriptor<TaskCategory>())
        #expect(categories.count == 1)
        #expect(categories.first?.title == "Preexisting")
        #expect(try freshContext.fetch(FetchDescriptor<TaskNode>()).isEmpty)
        #expect(
            try freshContext.fetch(FetchDescriptor<TaskCategoryAssignment>()).isEmpty
        )
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
    }

    @Test
    func applicationWriteGateRejectsBeforeCreatingAContextMutation() throws {
        let defaults = UserDefaults.standard
        let previousMode = defaults.object(forKey: AppCloudSync.modeKey)
        defaults.set(AppCloudSync.modeInMemoryFallback, forKey: AppCloudSync.modeKey)
        defer {
            if let previousMode {
                defaults.set(previousMode, forKey: AppCloudSync.modeKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.modeKey)
            }
        }

        let context = try makeTestContext()
        let fixture = makePlanFixture()
        #expect(throws: PersistenceWriteError.self) {
            try StoreScopedAITaskPlanCommandCoordinator(
                container: context.container,
                writeAuthorization: .applicationState,
                deviceID: "ai-test"
            ).apply(fixture.draft)
        }
        #expect(try context.fetch(FetchDescriptor<TaskCategory>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).isEmpty)
    }

    @Test
    func storeFacadeRefreshesSelectsFirstRootAndRoutesToTasks() throws {
        let context = try makeTestContext()
        let fixture = makePlanFixture()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.desktopDestination = .today

        let result = store.saveAITaskPlan(fixture.draft)

        #expect(
            result == .saved(
                firstRootTaskID: fixture.rootTaskID,
                didCreate: true
            )
        )
        #expect(store.task(for: fixture.rootTaskID) != nil)
        #expect(store.task(for: fixture.childTaskID) != nil)
        #expect(store.selectedTaskID == fixture.rootTaskID)
        #expect(store.desktopDestination == .tasks)
        #expect(store.tasksRoute == nil)
        #expect(store.checklistItems(for: fixture.childTaskID).count == 2)
    }

    private struct PlanFixture {
        let draft: AITaskPlanDraft
        let categoryID: UUID
        let rootTaskID: UUID
        let childTaskID: UUID
    }

    private func makePlanFixture(
        categoryID: UUID = UUID(),
        rootTaskID: UUID = UUID(),
        childTaskID: UUID = UUID(),
        quantityGoal: TaskQuantityGoalDraft? = nil,
        dailyRecurrence: TaskDailyRecurrenceDraft? = nil
    ) -> PlanFixture {
        return PlanFixture(
            draft: AITaskPlanDraft(
                categories: [
                    AITaskPlanCategoryDraft(
                        id: categoryID,
                        title: " Work ",
                        iconName: "briefcase.fill",
                        colorHex: "1677FF"
                    ),
                ],
                tasks: [
                    AITaskPlanTaskDraft(
                        id: childTaskID,
                        parentID: rootTaskID,
                        title: "Prepare release",
                        iconName: "hammer.fill",
                        colorHex: "6B5CFF",
                        checklistItems: [
                            AITaskPlanChecklistDraft(
                                title: "Draft",
                                iconName: "doc.text",
                                colorHex: "1677FF"
                            ),
                            AITaskPlanChecklistDraft(
                                title: "Review",
                                iconName: "eye.fill",
                                colorHex: "00A870"
                            ),
                        ]
                    ),
                    AITaskPlanTaskDraft(
                        id: rootTaskID,
                        categoryID: categoryID,
                        title: "Ship update",
                        notes: "Deliver this week",
                        estimatedMinutes: 45,
                        iconName: "shippingbox.fill",
                        colorHex: "FF8A00",
                        quantityGoal: quantityGoal,
                        dailyRecurrence: dailyRecurrence
                    ),
                ],
                modelID: "test-model"
            ),
            categoryID: categoryID,
            rootTaskID: rootTaskID,
            childTaskID: childTaskID
        )
    }

    private func coordinator(
        container: ModelContainer,
        checkpoint: @escaping
            (AITaskPlanMutationCheckpoint) throws -> Void = { _ in }
    ) -> StoreScopedAITaskPlanCommandCoordinator {
        StoreScopedAITaskPlanCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "ai-test",
            didReachCheckpoint: checkpoint
        )
    }

    private func singaporeDate(
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

private enum InjectedAIPlanFailure: Error {
    case stop
}

private enum AIPlanProgressFailureStage: CaseIterable {
    case templateGoal
    case rule
    case generatedTask
    case generatedGoal
    case occurrence

    func matches(
        _ checkpoint: AITaskPlanMutationCheckpoint,
        taskID: UUID
    ) -> Bool {
        guard case let .progress(checkpointTaskID, progressCheckpoint) =
                checkpoint,
              checkpointTaskID == taskID else {
            return false
        }
        return switch (self, progressCheckpoint) {
        case (.templateGoal, .quantityGoalChanged),
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
