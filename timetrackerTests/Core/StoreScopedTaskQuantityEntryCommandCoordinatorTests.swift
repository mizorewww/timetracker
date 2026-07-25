import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedTaskQuantityEntryCommandCoordinatorTests {
    @Test
    func storeRecordsSimpleQuantityProgressAndRefreshesImmediately() throws {
        let context = try makeTestContext()
        let fixture = try makeQuantityTask(
            in: context,
            title: "Push-ups",
            target: 50,
            unit: "reps"
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let entryID = UUID()

        #expect(
            store.recordTaskQuantity(
                taskID: fixture.task.id,
                amount: 20,
                entryID: entryID,
                recordedAt: referenceDate(100)
            )
        )

        let progress = try #require(
            store.taskQuantityProgress(for: fixture.task.id)
        )
        #expect(progress.totalAmount == 20)
        #expect(progress.remainingAmount == 30)
        #expect(progress.fractionCompleted == 0.4)
        #expect(progress.isComplete == false)
        #expect(progress.entryCount == 1)
        #expect(
            store.taskQuantityProgressReadState(for: fixture.task.id) ==
                .available(progress)
        )
        #expect(
            store.taskQuantityProgressReadState(
                for: fixture.task.id,
                expectedGoalMutationID: UUID()
            ) == .incomplete
        )
        let persisted = try #require(
            try quantityEntries(in: context.container).first
        )
        #expect(persisted.id == entryID)
        #expect(persisted.clientMutationID == entryID)
        #expect(persisted.taskID == fixture.task.id)
        #expect(persisted.quantityGoalID == fixture.goal.id)
        #expect(persisted.amount == 20)
    }

    @Test
    func storeReadStateDistinguishesNoGoalFromIncompleteBaseline()
        throws
    {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: "Plain task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        #expect(
            store.taskQuantityProgressReadState(for: task.id) == .none
        )
        #expect(
            store.taskQuantityProgressReadState(
                for: task.id,
                expectedGoalMutationID: UUID()
            ) == .incomplete
        )
    }

    @Test
    func exactRecordReplayIsANoOpAndIdentityCollisionsFailClosed() throws {
        let context = try makeTestContext()
        let first = try makeQuantityTask(
            in: context,
            title: "First",
            target: 10,
            unit: "pages"
        )
        let second = try makeQuantityTask(
            in: context,
            title: "Second",
            target: 10,
            unit: "pages"
        )
        let entryID = UUID()
        let recordedAt = referenceDate(100)
        let command = recordCommand(
            fixture: first,
            amount: 3,
            entryID: entryID,
            recordedAt: recordedAt
        )
        let writer = coordinator(context.container)

        let created = try writer.record(command: command)
        let replay = try writer.record(command: command)

        #expect(created.didMutate)
        #expect(replay.didMutate == false)
        #expect(replay.events.isEmpty)
        #expect(try quantityEntries(in: context.container).count == 1)
        var changedPayload = command
        changedPayload = TaskQuantityEntryRecordCommand(
            taskID: command.taskID,
            goalBaseline: command.goalBaseline,
            amount: 4,
            recordedAt: command.recordedAt,
            proposedEntryID: command.proposedEntryID
        )
        #expect(throws: TaskQuantityEntryMutationError.entryChanged) {
            try writer.record(command: changedPayload)
        }
        #expect(throws: TaskQuantityEntryMutationError.entryChanged) {
            try writer.record(
                command: recordCommand(
                    fixture: second,
                    amount: 3,
                    entryID: entryID,
                    recordedAt: recordedAt
                )
            )
        }
        #expect(try quantityEntries(in: context.container).count == 1)
    }

    @Test
    func amountAndDateValidationWritesNothing() throws {
        let context = try makeTestContext()
        let fixture = try makeQuantityTask(
            in: context,
            title: "Validated",
            target: 50,
            unit: "reps"
        )
        let writer = coordinator(context.container)

        for invalidAmount in [0, 1_000_001] {
            #expect(throws: TaskQuantityEntryMutationError.invalidAmount) {
                try writer.record(
                    command: recordCommand(
                        fixture: fixture,
                        amount: invalidAmount,
                        entryID: UUID()
                    )
                )
            }
        }
        for invalidDate in [
            PersistentDatePolicy.minimumDate.addingTimeInterval(-0.001),
            PersistentDatePolicy.maximumDateExclusive,
            Date(timeIntervalSinceReferenceDate: .infinity),
        ] {
            #expect(throws: TaskQuantityEntryMutationError.invalidRecordedAt) {
                try writer.record(
                    command: recordCommand(
                        fixture: fixture,
                        amount: 1,
                        entryID: UUID(),
                        recordedAt: invalidDate
                    )
                )
            }
        }
        #expect(try quantityEntries(in: context.container).isEmpty)
    }

    @Test
    func persistenceDateBoundsMatchSyncRestoreContract() throws {
        let context = try makeTestContext()
        let fixture = try makeQuantityTask(
            in: context,
            title: "Date bounds",
            target: 10,
            unit: "pages"
        )
        let writer = coordinator(context.container)
        _ = try writer.record(
            command: recordCommand(
                fixture: fixture,
                amount: 1,
                entryID: UUID(),
                recordedAt: PersistentDatePolicy.minimumDate
            )
        )
        _ = try writer.record(
            command: recordCommand(
                fixture: fixture,
                amount: 1,
                entryID: UUID(),
                recordedAt: PersistentDatePolicy.maximumDateExclusive
                    .addingTimeInterval(-0.001)
            )
        )
        #expect(try quantityEntries(in: context.container).count == 2)

        let sibling = ModelContext(context.container)
        let nearMaximum = try #require(
            try sibling.fetch(FetchDescriptor<TaskQuantityEntry>())
                .visibleDeduplicatedByID()
                .first
        )
        nearMaximum.updatedAt = PersistentDatePolicy.maximumDateExclusive
            .addingTimeInterval(-0.001)
        nearMaximum.clientMutationID = UUID()
        try sibling.save()
        let baseline = TaskQuantityEntryMutationBaseline(
            entry: nearMaximum
        )

        #expect(throws: TaskQuantityEntryMutationError.invalidRecordedAt) {
            try coordinator(
                context.container,
                now: { referenceDate(1000) }
            ).update(
                command: TaskQuantityEntryUpdateCommand(
                    entryBaseline: baseline,
                    goalBaseline: TaskQuantityGoalMutationBaseline(
                        goal: fixture.goal
                    ),
                    amount: 2,
                    recordedAt: PersistentDatePolicy.minimumDate,
                    operationID: UUID()
                )
            )
        }
        let unchanged = try #require(
            try ModelContext(context.container)
                .fetch(FetchDescriptor<TaskQuantityEntry>())
                .latestByID()[nearMaximum.id]
        )
        #expect(unchanged.amount == 1)
        #expect(
            unchanged.updatedAt == PersistentDatePolicy
                .maximumDateExclusive.addingTimeInterval(-0.001)
        )
    }

    @Test
    func dailyTemplateRejectsProgressWhileGeneratedChildAcceptsIt()
        throws
    {
        let context = try makeTestContext()
        let root = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: "Fitness",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let template = try makeQuantityTask(
            in: context,
            title: "Daily push-ups",
            target: 50,
            unit: "reps",
            parentID: root.id
        )
        let now = referenceDate(1000)
        let recurrence = StoreScopedTaskRecurrenceCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "recurrence"
        )
        let recurrenceOutcome = try recurrence.createDailyRule(
            templateTaskID: template.task.id,
            startDayKey: TaskRecurrenceDayKey.value(
                for: now,
                timeZone: .gmt
            ),
            timeZoneIdentifier: "GMT",
            now: now
        )
        let generatedTaskID = try #require(
            recurrenceOutcome.materializations.first?.generatedTaskID
        )
        let fresh = ModelContext(context.container)
        let generatedTask = try #require(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .visibleDeduplicatedByID()
                .first { $0.id == generatedTaskID }
        )
        let generatedGoal = try #require(
            try fresh.fetch(FetchDescriptor<TaskQuantityGoal>())
                .visibleDeduplicatedByID()
                .first { $0.taskID == generatedTaskID }
        )
        let generated = QuantityFixture(
            task: generatedTask,
            goal: generatedGoal
        )
        let writer = coordinator(context.container)

        #expect(
            throws: TaskQuantityEntryMutationError
                .recurrenceTemplateRequiresGeneratedTask
        ) {
            try writer.record(
                command: recordCommand(
                    fixture: template,
                    amount: 20,
                    entryID: UUID()
                )
            )
        }
        let childOutcome = try writer.record(
            command: recordCommand(
                fixture: generated,
                amount: 20,
                entryID: UUID()
            )
        )
        #expect(childOutcome.didMutate)
        #expect(
            childOutcome.affectedAncestorTaskIDs == [
                root.id,
                template.task.id,
            ]
        )
        #expect(childOutcome.progressSnapshot?.totalAmount == 20)

        let rule = try #require(
            try ModelContext(context.container)
                .fetch(FetchDescriptor<TaskRecurrenceRule>())
                .visibleDeduplicatedByID()
                .first
        )
        _ = try recurrence.setEnabled(
            baseline: TaskRecurrenceRuleMutationBaseline(rule: rule),
            isEnabled: false,
            now: now.addingTimeInterval(60)
        )
        #expect(
            throws: TaskQuantityEntryMutationError
                .recurrenceTemplateRequiresGeneratedTask
        ) {
            try writer.record(
                command: recordCommand(
                    fixture: template,
                    amount: 1,
                    entryID: UUID()
                )
            )
        }
    }

    @Test
    func occurrenceOnlyClaimStillProtectsARecurringTemplate() throws {
        let context = try makeTestContext()
        let template = try makeQuantityTask(
            in: context,
            title: "Staged recurrence",
            target: 5,
            unit: "sets"
        )
        let ruleID = TaskProgressIdentity.recurrenceRuleID(
            templateTaskID: template.task.id
        )
        context.insert(
            TaskRecurrenceOccurrence(
                ruleID: ruleID,
                templateTaskID: template.task.id,
                occurrenceDayKey: "2026-07-21",
                timeZoneIdentifier: "Asia/Singapore",
                deviceID: "cloud-stage"
            )
        )
        try context.save()

        #expect(
            throws: TaskQuantityEntryMutationError
                .recurrenceTemplateRequiresGeneratedTask
        ) {
            try coordinator(context.container).record(
                command: recordCommand(
                    fixture: template,
                    amount: 1,
                    entryID: UUID()
                )
            )
        }
    }

    @Test
    func unavailableTaskBranchesCannotReceiveQuantityProgress() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        )
        let archivedParent = try repository.createTask(
            title: "Archived parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let archivedChild = try makeQuantityTask(
            in: context,
            title: "Archived child",
            target: 5,
            unit: "sets",
            parentID: archivedParent.id
        )
        archivedParent.archivedAt = referenceDate(200)
        archivedParent.updatedAt = referenceDate(200)
        archivedParent.clientMutationID = UUID()

        let deletedParent = try repository.createTask(
            title: "Deleted parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let deletedChild = try makeQuantityTask(
            in: context,
            title: "Deleted child",
            target: 5,
            unit: "sets",
            parentID: deletedParent.id
        )
        deletedParent.deletedAt = referenceDate(300)
        deletedParent.updatedAt = referenceDate(300)
        deletedParent.clientMutationID = UUID()

        let healthTask = TaskNode(
            title: "Health running",
            parentID: nil,
            deviceID: "health"
        )
        healthTask.id = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.running)
        ).id
        context.insert(healthTask)
        let healthGoal = TaskQuantityGoal(
            taskID: healthTask.id,
            targetAmount: 5,
            unitLabel: "km",
            deviceID: "seed"
        )
        context.insert(healthGoal)
        try context.save()
        let health = QuantityFixture(task: healthTask, goal: healthGoal)

        for fixture in [archivedChild, deletedChild, health] {
            #expect(throws: TaskQuantityEntryMutationError.taskUnavailable) {
                try coordinator(context.container).record(
                    command: recordCommand(
                        fixture: fixture,
                        amount: 1,
                        entryID: UUID()
                    )
                )
            }
        }
        #expect(try quantityEntries(in: context.container).isEmpty)
    }

    @Test
    func missingAndIncompleteGoalGraphsFailWithoutRepairingData() throws {
        let missingContext = try makeTestContext()
        let missingTask = try SwiftDataTaskRepository(
            context: missingContext,
            deviceID: "seed"
        ).createTask(
            title: "No goal",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let expectedGoalID = TaskProgressIdentity.quantityGoalID(
            taskID: missingTask.id
        )
        #expect(
            throws: TaskQuantityEntryMutationError
                .quantityGoalUnavailable
        ) {
            try coordinator(missingContext.container).record(
                command: TaskQuantityEntryRecordCommand(
                    taskID: missingTask.id,
                    goalBaseline: TaskQuantityGoalMutationBaseline(
                        goalID: expectedGoalID,
                        taskID: missingTask.id,
                        clientMutationID: UUID()
                    ),
                    amount: 1,
                    recordedAt: referenceDate(100),
                    proposedEntryID: UUID()
                )
            )
        }

        let tombstoneContext = try makeTestContext()
        let tombstoned = try makeQuantityTask(
            in: tombstoneContext,
            title: "Removed goal",
            target: 5,
            unit: "sets"
        )
        let staleTombstoneCommand = recordCommand(
            fixture: tombstoned,
            amount: 1,
            entryID: UUID()
        )
        tombstoned.goal.deletedAt = referenceDate(200)
        tombstoned.goal.updatedAt = referenceDate(200)
        tombstoned.goal.clientMutationID = UUID()
        try tombstoneContext.save()
        #expect(
            throws: TaskQuantityEntryMutationError.quantityGoalChanged
        ) {
            try coordinator(tombstoneContext.container).record(
                command: staleTombstoneCommand
            )
        }
        #expect(
            throws: TaskQuantityEntryMutationError
                .quantityGoalUnavailable
        ) {
            try coordinator(tombstoneContext.container).record(
                command: recordCommand(
                    fixture: tombstoned,
                    amount: 1,
                    entryID: UUID()
                )
            )
        }

        let conflictContext = try makeTestContext()
        let conflicted = try makeQuantityTask(
            in: conflictContext,
            title: "Conflicted goal",
            target: 5,
            unit: "sets"
        )
        let malformed = TaskQuantityEntry(
            id: UUID(),
            taskID: conflicted.task.id,
            amount: 1,
            deviceID: "cloud-stage"
        )
        malformed.quantityGoalID = UUID()
        conflictContext.insert(malformed)
        try conflictContext.save()
        let conflictStore = makeTestStore()
        conflictStore.configureIfNeeded(context: conflictContext)
        #expect(
            conflictStore.taskIDsWithIncompleteQuantityProgress.contains(
                conflicted.task.id
            )
        )
        #expect(
            conflictStore.taskQuantityProgress(for: conflicted.task.id) == nil
        )
        #expect(
            conflictStore.taskQuantityProgressReadState(
                for: conflicted.task.id
            ) == .incomplete
        )
        #expect(
            throws: TaskQuantityEntryMutationError
                .incompleteQuantityGraph
        ) {
            try coordinator(conflictContext.container).record(
                command: recordCommand(
                    fixture: conflicted,
                    amount: 1,
                    entryID: UUID()
                )
            )
        }
        #expect(try quantityEntries(in: missingContext.container).isEmpty)
        #expect(try quantityEntries(in: tombstoneContext.container).isEmpty)
        #expect(try quantityEntries(in: conflictContext.container).count == 1)
    }

    @Test
    func malformedExistingEntryBlocksFurtherProgress() throws {
        let context = try makeTestContext()
        let fixture = try makeQuantityTask(
            in: context,
            title: "Malformed progress",
            target: 5,
            unit: "sets"
        )
        let malformed = TaskQuantityEntry(
            id: UUID(),
            taskID: fixture.task.id,
            amount: 1,
            deviceID: "cloud-stage"
        )
        malformed.amount = 0
        context.insert(malformed)
        try context.save()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        #expect(
            store.taskQuantityProgress(for: fixture.task.id) == nil
        )
        #expect(
            store.recordTaskQuantity(
                taskID: fixture.task.id,
                amount: 1,
                entryID: UUID()
            ) == false
        )
        #expect(
            store.errorMessage == TaskQuantityEntryMutationError
                .incompleteQuantityGraph.localizedDescription
        )

        #expect(
            throws: TaskQuantityEntryMutationError
                .incompleteQuantityGraph
        ) {
            try coordinator(context.container).record(
                command: recordCommand(
                    fixture: fixture,
                    amount: 1,
                    entryID: UUID()
                )
            )
        }
        #expect(
            try ModelContext(context.container)
                .fetch(FetchDescriptor<TaskQuantityEntry>())
                .count == 1
        )
    }

    @Test
    func scopedRefreshRetainsIncompleteSignalAfterMalformedGoalRemoval()
        throws
    {
        let context = try makeTestContext()
        let first = try makeQuantityTask(
            in: context,
            title: "First participant",
            target: 5,
            unit: "sets"
        )
        let secondTask = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: "Second participant",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let malformedGoal = TaskQuantityGoal(
            taskID: secondTask.id,
            targetAmount: 10,
            unitLabel: "pages",
            deviceID: "cloud-stage"
        )
        malformedGoal.id = UUID()
        context.insert(malformedGoal)
        let crossLinkedEntry = TaskQuantityEntry(
            id: UUID(),
            taskID: first.task.id,
            amount: 1,
            deviceID: "cloud-stage"
        )
        crossLinkedEntry.quantityGoalID = malformedGoal.id
        context.insert(crossLinkedEntry)
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(
            store.taskIDsWithIncompleteQuantityProgress
                .isSuperset(of: [first.task.id, secondTask.id])
        )

        let sibling = ModelContext(context.container)
        let persistedGoal = try #require(
            try sibling.fetch(FetchDescriptor<TaskQuantityGoal>())
                .latestByID()[malformedGoal.id]
        )
        persistedGoal.deletedAt = referenceDate(500)
        persistedGoal.updatedAt = referenceDate(500)
        persistedGoal.clientMutationID = UUID()
        try sibling.save()
        try store.refresh(
            plan: StoreRefreshPlan(
                scopes: [.tasks],
                affectedTaskIDs: [secondTask.id],
                directlyAffectedTaskIDs: [secondTask.id]
            )
        )

        #expect(
            store.taskIDsWithIncompleteQuantityProgress.contains(
                first.task.id
            )
        )
        #expect(store.taskQuantityProgress(for: first.task.id) == nil)
        #expect(
            store.recordTaskQuantity(
                taskID: first.task.id,
                amount: 1,
                entryID: UUID()
            ) == false
        )
        #expect(
            store.errorMessage == TaskQuantityEntryMutationError
                .incompleteQuantityGraph.localizedDescription
        )
        #expect(try quantityEntries(in: context.container).count == 1)
    }

    @Test
    func exactReplayRefreshesAStaleFacadeWithoutDuplicatingEntry()
        throws
    {
        let context = try makeTestContext()
        let fixture = try makeQuantityTask(
            in: context,
            title: "Cross-scene progress",
            target: 10,
            unit: "pages"
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let analyticsRevision = store.analyticsRevision
        let entryID = UUID()
        let recordedAt = referenceDate(100)
        _ = try coordinator(context.container).record(
            command: recordCommand(
                fixture: fixture,
                amount: 4,
                entryID: entryID,
                recordedAt: recordedAt
            )
        )
        #expect(
            store.taskQuantityProgress(for: fixture.task.id)?.totalAmount == 0
        )

        #expect(
            store.recordTaskQuantity(
                taskID: fixture.task.id,
                amount: 4,
                entryID: entryID,
                recordedAt: recordedAt
            )
        )

        #expect(
            store.taskQuantityProgress(for: fixture.task.id)?.totalAmount == 4
        )
        #expect(store.analyticsRevision > analyticsRevision)
        #expect(try quantityEntries(in: context.container).count == 1)
    }

    @Test
    func staleGoalBaselineCannotRecordAgainstANewerTarget() throws {
        let context = try makeTestContext()
        let fixture = try makeQuantityTask(
            in: context,
            title: "Changing goal",
            target: 10,
            unit: "pages"
        )
        let staleCommand = recordCommand(
            fixture: fixture,
            amount: 2,
            entryID: UUID()
        )
        let sibling = ModelContext(context.container)
        let goal = try #require(
            try sibling.fetch(FetchDescriptor<TaskQuantityGoal>())
                .latestByID()[fixture.goal.id]
        )
        goal.targetAmount = 20
        goal.updatedAt = referenceDate(500)
        goal.clientMutationID = UUID()
        try sibling.save()

        #expect(
            throws: TaskQuantityEntryMutationError.quantityGoalChanged
        ) {
            try coordinator(context.container).record(command: staleCommand)
        }
        #expect(try quantityEntries(in: context.container).isEmpty)
    }

    @Test
    func staleFacadeFailureConvergesGoalAndAnalyticsReadModels() throws {
        let context = try makeTestContext()
        let fixture = try makeQuantityTask(
            in: context,
            title: "Changing facade goal",
            target: 10,
            unit: "pages"
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let analyticsRevision = store.analyticsRevision
        let sibling = ModelContext(context.container)
        let goal = try #require(
            try sibling.fetch(FetchDescriptor<TaskQuantityGoal>())
                .latestByID()[fixture.goal.id]
        )
        goal.targetAmount = 20
        goal.updatedAt = referenceDate(500)
        goal.clientMutationID = UUID()
        try sibling.save()

        #expect(
            store.recordTaskQuantity(
                taskID: fixture.task.id,
                amount: 2,
                entryID: UUID(),
                recordedAt: referenceDate(100)
            ) == false
        )

        #expect(
            store.errorMessage == TaskQuantityEntryMutationError
                .quantityGoalChanged.localizedDescription
        )
        #expect(
            store.taskQuantityProgress(for: fixture.task.id)?.targetAmount == 20
        )
        #expect(store.analyticsRevision > analyticsRevision)
        #expect(try quantityEntries(in: context.container).isEmpty)
    }

    @Test
    func capturedGoalBaselineRejectsRecordAfterFacadeRefresh() throws {
        let context = try makeTestContext()
        let fixture = try makeQuantityTask(
            in: context,
            title: "Open record sheet",
            target: 10,
            unit: "pages"
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let capturedGoalBaseline = try #require(
            store.taskQuantityProgress(for: fixture.task.id)?.goalBaseline
        )
        let sibling = ModelContext(context.container)
        let goal = try #require(
            try sibling.fetch(FetchDescriptor<TaskQuantityGoal>())
                .latestByID()[fixture.goal.id]
        )
        goal.targetAmount = 20
        goal.updatedAt = referenceDate(500)
        goal.clientMutationID = UUID()
        try sibling.save()
        try store.refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
        #expect(
            store.taskQuantityProgress(for: fixture.task.id)?.targetAmount ==
                20
        )

        #expect(
            store.recordTaskQuantity(
                taskID: fixture.task.id,
                goalBaseline: capturedGoalBaseline,
                amount: 2,
                entryID: UUID(),
                recordedAt: referenceDate(100)
            ) == false
        )

        #expect(
            store.errorMessage == TaskQuantityEntryMutationError
                .quantityGoalChanged.localizedDescription
        )
        #expect(try quantityEntries(in: context.container).isEmpty)
    }

    @Test
    func capturedGoalBaselineRejectsUpdateAfterFacadeRefresh() throws {
        let context = try makeTestContext()
        let fixture = try makeQuantityTask(
            in: context,
            title: "Open update sheet",
            target: 10,
            unit: "pages"
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let capturedGoalBaseline = try #require(
            store.taskQuantityProgress(for: fixture.task.id)?.goalBaseline
        )
        #expect(
            store.recordTaskQuantity(
                taskID: fixture.task.id,
                goalBaseline: capturedGoalBaseline,
                amount: 2,
                entryID: UUID(),
                recordedAt: referenceDate(100)
            )
        )
        let entryBaseline = try TaskQuantityEntryMutationBaseline(
            entry: #require(
                try quantityEntries(in: context.container).first
            )
        )
        let sibling = ModelContext(context.container)
        let goal = try #require(
            try sibling.fetch(FetchDescriptor<TaskQuantityGoal>())
                .latestByID()[fixture.goal.id]
        )
        goal.targetAmount = 20
        goal.updatedAt = referenceDate(500)
        goal.clientMutationID = UUID()
        try sibling.save()
        try store.refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
        #expect(
            store.taskQuantityProgress(for: fixture.task.id)?.targetAmount ==
                20
        )

        #expect(
            store.updateTaskQuantityEntry(
                baseline: entryBaseline,
                goalBaseline: capturedGoalBaseline,
                amount: 8,
                recordedAt: referenceDate(200),
                operationID: UUID()
            ) == false
        )

        #expect(
            store.errorMessage == TaskQuantityEntryMutationError
                .quantityGoalChanged.localizedDescription
        )
        #expect(
            try quantityEntries(in: context.container).first?.amount == 2
        )
    }

    @Test
    func staleFacadeFailureConvergesArchivedAncestorAvailability() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        )
        let parent = try repository.createTask(
            title: "Active parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try makeQuantityTask(
            in: context,
            title: "Child quantity",
            target: 10,
            unit: "sets",
            parentID: parent.id
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(
            store.taskQuantityProgress(for: child.task.id)?
                .isRecordingAllowed == true
        )

        let sibling = ModelContext(context.container)
        let persistedParent = try #require(
            try sibling.fetch(FetchDescriptor<TaskNode>())
                .latestByID()[parent.id]
        )
        persistedParent.archivedAt = referenceDate(500)
        persistedParent.updatedAt = referenceDate(500)
        persistedParent.clientMutationID = UUID()
        try sibling.save()

        #expect(
            store.recordTaskQuantity(
                taskID: child.task.id,
                amount: 1,
                entryID: UUID()
            ) == false
        )
        #expect(
            store.errorMessage == TaskQuantityEntryMutationError
                .taskUnavailable.localizedDescription
        )
        #expect(
            store.taskQuantityProgress(for: child.task.id)?
                .isRecordingAllowed == false
        )
        #expect(try quantityEntries(in: context.container).isEmpty)
    }

    @Test
    func updateAndHistoricalDeleteAreIdempotentAndRejectStaleBaselines()
        throws
    {
        let context = try makeTestContext()
        let fixture = try makeQuantityTask(
            in: context,
            title: "Correctable progress",
            target: 50,
            unit: "reps"
        )
        let writer = coordinator(
            context.container,
            now: { referenceDate(100) }
        )
        let created = try writer.record(
            command: recordCommand(
                fixture: fixture,
                amount: 10,
                entryID: UUID(),
                recordedAt: referenceDate(10)
            )
        )
        let initialEntry = try #require(
            try quantityEntries(in: context.container).first
        )
        let initialBaseline = TaskQuantityEntryMutationBaseline(
            entry: initialEntry
        )
        let updateOperationID = UUID()
        let update = TaskQuantityEntryUpdateCommand(
            entryBaseline: initialBaseline,
            goalBaseline: TaskQuantityGoalMutationBaseline(
                goal: fixture.goal
            ),
            amount: 30,
            recordedAt: referenceDate(20),
            operationID: updateOperationID
        )

        let updated = try writer.update(command: update)
        let updateReplay = try writer.update(command: update)
        #expect(updated.didMutate)
        #expect(updateReplay.didMutate == false)
        #expect(updated.progressSnapshot?.totalAmount == 30)
        #expect(throws: TaskQuantityEntryMutationError.entryChanged) {
            try writer.update(
                command: TaskQuantityEntryUpdateCommand(
                    entryBaseline: initialBaseline,
                    goalBaseline: update.goalBaseline,
                    amount: 40,
                    recordedAt: referenceDate(20),
                    operationID: UUID()
                )
            )
        }

        let freshEntry = try #require(
            try quantityEntries(in: context.container).first
        )
        let deleteBaseline = TaskQuantityEntryMutationBaseline(
            entry: freshEntry
        )
        let sibling = ModelContext(context.container)
        let task = try #require(
            try sibling.fetch(FetchDescriptor<TaskNode>())
                .latestByID()[fixture.task.id]
        )
        task.archivedAt = referenceDate(200)
        task.updatedAt = referenceDate(200)
        task.clientMutationID = UUID()
        try sibling.save()

        let delete = TaskQuantityEntryDeleteCommand(
            entryBaseline: deleteBaseline,
            operationID: UUID()
        )
        let deleted = try writer.delete(command: delete)
        let deleteReplay = try writer.delete(command: delete)
        #expect(created.didMutate)
        #expect(deleted.didMutate)
        #expect(deleteReplay.didMutate == false)
        #expect(try quantityEntries(in: context.container).isEmpty)
        #expect(throws: TaskQuantityEntryMutationError.entryUnavailable) {
            try writer.update(
                command: TaskQuantityEntryUpdateCommand(
                    entryBaseline: deleteBaseline,
                    goalBaseline: update.goalBaseline,
                    amount: 40,
                    recordedAt: referenceDate(20),
                    operationID: UUID()
                )
            )
        }
    }

    @Test
    func injectedFailureRollsBackInsertedEntry() throws {
        let context = try makeTestContext()
        let fixture = try makeQuantityTask(
            in: context,
            title: "Atomic progress",
            target: 50,
            unit: "reps"
        )
        let writer = StoreScopedTaskQuantityEntryCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "writer",
            didReachCheckpoint: { checkpoint in
                guard case .entryInserted = checkpoint else { return }
                throw QuantityInjectedFailure.stop
            }
        )

        #expect(throws: QuantityInjectedFailure.stop) {
            try writer.record(
                command: recordCommand(
                    fixture: fixture,
                    amount: 20,
                    entryID: UUID()
                )
            )
        }
        #expect(try quantityEntries(in: context.container).isEmpty)
    }

    @Test
    func updateAndDeleteRollbackAndDominateFutureWinnerTimestamps()
        throws
    {
        let context = try makeTestContext()
        let fixture = try makeQuantityTask(
            in: context,
            title: "Future-safe progress",
            target: 50,
            unit: "reps"
        )
        let seedWriter = coordinator(
            context.container,
            now: { referenceDate(100) }
        )
        _ = try seedWriter.record(
            command: recordCommand(
                fixture: fixture,
                amount: 10,
                entryID: UUID()
            )
        )
        let sibling = ModelContext(context.container)
        let futureEntry = try #require(
            try sibling.fetch(FetchDescriptor<TaskQuantityEntry>())
                .visibleDeduplicatedByID()
                .first
        )
        futureEntry.updatedAt = referenceDate(10000)
        futureEntry.clientMutationID = UUID()
        try sibling.save()
        let futureBaseline = TaskQuantityEntryMutationBaseline(
            entry: futureEntry
        )
        let goalBaseline = TaskQuantityGoalMutationBaseline(
            goal: fixture.goal
        )

        let updateFailure = StoreScopedTaskQuantityEntryCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "rollback-update",
            nowProvider: { referenceDate(200) },
            didReachCheckpoint: { checkpoint in
                guard case .entryUpdated = checkpoint else { return }
                throw QuantityInjectedFailure.stop
            }
        )
        #expect(throws: QuantityInjectedFailure.stop) {
            try updateFailure.update(
                command: TaskQuantityEntryUpdateCommand(
                    entryBaseline: futureBaseline,
                    goalBaseline: goalBaseline,
                    amount: 20,
                    recordedAt: referenceDate(300),
                    operationID: UUID()
                )
            )
        }
        var current = try #require(
            try quantityEntries(in: context.container).first
        )
        #expect(current.amount == 10)
        #expect(current.updatedAt == referenceDate(10000))

        let updateOperationID = UUID()
        _ = try coordinator(
            context.container,
            now: { referenceDate(200) }
        ).update(
            command: TaskQuantityEntryUpdateCommand(
                entryBaseline: TaskQuantityEntryMutationBaseline(
                    entry: current
                ),
                goalBaseline: goalBaseline,
                amount: 20,
                recordedAt: referenceDate(300),
                operationID: updateOperationID
            )
        )
        current = try #require(
            try quantityEntries(in: context.container).first
        )
        #expect(current.amount == 20)
        #expect(current.updatedAt > referenceDate(10000))

        let deleteBaseline = TaskQuantityEntryMutationBaseline(
            entry: current
        )
        let deleteFailure = StoreScopedTaskQuantityEntryCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "rollback-delete",
            nowProvider: { referenceDate(200) },
            didReachCheckpoint: { checkpoint in
                guard case .entryDeleted = checkpoint else { return }
                throw QuantityInjectedFailure.stop
            }
        )
        #expect(throws: QuantityInjectedFailure.stop) {
            try deleteFailure.delete(
                command: TaskQuantityEntryDeleteCommand(
                    entryBaseline: deleteBaseline,
                    operationID: UUID()
                )
            )
        }
        current = try #require(
            try quantityEntries(in: context.container).first
        )
        #expect(current.deletedAt == nil)
        #expect(current.clientMutationID == updateOperationID)
        let updateTimestamp = current.updatedAt

        _ = try coordinator(
            context.container,
            now: { referenceDate(200) }
        ).delete(
            command: TaskQuantityEntryDeleteCommand(
                entryBaseline: TaskQuantityEntryMutationBaseline(
                    entry: current
                ),
                operationID: UUID()
            )
        )
        let tombstone = try #require(
            try ModelContext(context.container)
                .fetch(FetchDescriptor<TaskQuantityEntry>())
                .latestByID()[current.id]
        )
        #expect(tombstone.deletedAt != nil)
        #expect(tombstone.updatedAt > updateTimestamp)
    }

    @Test
    func progressSnapshotDeduplicatesPreservesOverageAndFailsClosed()
        throws
    {
        let context = try makeTestContext()
        let fixture = try makeQuantityTask(
            in: context,
            title: "Snapshot",
            target: 50,
            unit: "reps"
        )
        let first = TaskQuantityEntry(
            id: UUID(),
            taskID: fixture.task.id,
            amount: 20,
            deviceID: "first"
        )
        let second = TaskQuantityEntry(
            id: UUID(),
            taskID: fixture.task.id,
            amount: 40,
            deviceID: "second"
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let complete = try #require(
            TaskQuantityProgressService().snapshot(
                taskID: fixture.task.id,
                goals: [fixture.goal],
                entries: [first, second],
                isRecordingAllowed: false
            )
        )
        #expect(complete.totalAmount == 60)
        #expect(complete.remainingAmount == 0)
        #expect(complete.fractionCompleted == 1)
        #expect(complete.isComplete)
        #expect(complete.isRecordingAllowed == false)

        let conflicting = TaskQuantityEntry(
            id: UUID(),
            taskID: fixture.task.id,
            amount: 1,
            deviceID: "cloud-stage"
        )
        conflicting.quantityGoalID = UUID()
        #expect(
            TaskQuantityProgressService().snapshot(
                taskID: fixture.task.id,
                goals: [fixture.goal],
                entries: [first, second, conflicting],
                isRecordingAllowed: true
            ) == nil
        )
    }

    private func makeQuantityTask(
        in context: ModelContext,
        title: String,
        target: Int,
        unit: String,
        parentID: UUID? = nil
    ) throws -> QuantityFixture {
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: title,
            parentID: parentID,
            colorHex: nil,
            iconName: nil
        )
        let goal = TaskQuantityGoal(
            taskID: task.id,
            targetAmount: target,
            unitLabel: unit,
            deviceID: "seed"
        )
        context.insert(goal)
        try context.save()
        return QuantityFixture(task: task, goal: goal)
    }

    private func recordCommand(
        fixture: QuantityFixture,
        amount: Int,
        entryID: UUID,
        recordedAt: Date = Date(timeIntervalSinceReferenceDate: 100)
    ) -> TaskQuantityEntryRecordCommand {
        TaskQuantityEntryRecordCommand(
            taskID: fixture.task.id,
            goalBaseline: TaskQuantityGoalMutationBaseline(
                goal: fixture.goal
            ),
            amount: amount,
            recordedAt: recordedAt,
            proposedEntryID: entryID
        )
    }

    private func coordinator(
        _ container: ModelContainer,
        now: @escaping () -> Date = {
            Date(timeIntervalSinceReferenceDate: 1000)
        }
    ) -> StoreScopedTaskQuantityEntryCommandCoordinator {
        StoreScopedTaskQuantityEntryCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "writer",
            nowProvider: now
        )
    }

    private func quantityEntries(
        in container: ModelContainer
    ) throws -> [TaskQuantityEntry] {
        try ModelContext(container)
            .fetch(FetchDescriptor<TaskQuantityEntry>())
            .visibleDeduplicatedByID()
    }

    private func referenceDate(_ value: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: value)
    }
}

@MainActor
private struct QuantityFixture {
    let task: TaskNode
    let goal: TaskQuantityGoal
}

private enum QuantityInjectedFailure: Error {
    case stop
}
