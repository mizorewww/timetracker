import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct TaskRecurrenceWorkEligibilityTests {
    @Test
    func orphanQuantityEntryClaimPreventsGeneratedOccurrence() throws {
        let context = try makeTestContext()
        let template = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: "Imported template",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let now = try date(year: 2026, month: 8, day: 2, hour: 12)
        let dayKey = "2026-08-02"
        let ruleID = TaskProgressIdentity.recurrenceRuleID(
            templateTaskID: template.id
        )
        let generatedTaskID = TaskProgressIdentity.generatedTaskID(
            ruleID: ruleID,
            dayKey: dayKey
        )
        context.insert(
            TaskQuantityEntry(
                id: UUID(),
                taskID: generatedTaskID,
                amount: 1,
                recordedAt: now,
                createdAt: now,
                deviceID: "staged-import"
            )
        )
        try context.save()

        let outcome = try recurrenceCoordinator(container: context.container)
            .createDailyRule(
                templateTaskID: template.id,
                startDayKey: dayKey,
                timeZoneIdentifier: "Asia/Singapore",
                now: now
            )

        #expect(outcome.materializations.isEmpty)
        let fresh = ModelContext(context.container)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .contains { $0.id == generatedTaskID } == false
        )
        #expect(try fresh.fetch(FetchDescriptor<TaskRecurrenceOccurrence>()).isEmpty)
    }

    @Test
    func activePomodoroBlocksRecurrenceTemplateCreation() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: "Active focus",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let run = PomodoroRun(taskID: task.id, deviceID: "pomodoro")
        run.state = .focusing
        context.insert(run)
        try context.save()

        #expect(throws: TaskRecurrenceMutationError.templateHasActiveWork) {
            _ = try recurrenceCoordinator(container: context.container)
                .createDailyRule(
                    templateTaskID: task.id,
                    startDayKey: "2026-08-02",
                    timeZoneIdentifier: "Asia/Singapore",
                    now: date(year: 2026, month: 8, day: 2, hour: 12)
                )
        }
    }

    @Test
    func completedPomodoroHistoryDoesNotBlockRecurrenceTemplateCreation() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: "Past focus",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let now = try date(year: 2026, month: 8, day: 2, hour: 12)
        let run = PomodoroRun(taskID: task.id, deviceID: "pomodoro")
        run.state = .completed
        run.endedAt = now
        context.insert(run)
        try context.save()

        let outcome = try recurrenceCoordinator(container: context.container)
            .createDailyRule(
                templateTaskID: task.id,
                startDayKey: "2026-08-02",
                timeZoneIdentifier: "Asia/Singapore",
                now: now
            )

        #expect(outcome.materializations.count == 1)
    }

    @Test
    func templateRemainsAParentButOnlyOccurrenceAcceptsDirectWork()
        throws
    {
        let fixture = try makeFixture()
        let fresh = ModelContext(fixture.container)
        let repository = SwiftDataTaskRepository(
            context: fresh,
            deviceID: "eligibility"
        )
        let tasks = try repository.allNodes()
        let rules = try repository.taskRecurrenceRules()
        let service = TaskTrackingAvailabilityService()

        let hierarchyEligibleIDs = service.trackableTaskIDs(tasks: tasks)
        let directWorkIDs = try service.directWorkTaskIDs(
            tasks: tasks,
            recurrenceRules: rules,
            recurrenceOccurrences:
            repository.taskRecurrenceOccurrences()
        )

        #expect(hierarchyEligibleIDs.contains(fixture.templateTaskID))
        #expect(hierarchyEligibleIDs.contains(fixture.generatedTaskID))
        #expect(directWorkIDs.contains(fixture.templateTaskID) == false)
        #expect(directWorkIDs.contains(fixture.generatedTaskID))

        let generatedChild = try repository.createTask(
            title: "Nested work",
            parentID: fixture.templateTaskID,
            colorHex: nil,
            iconName: nil
        )
        #expect(generatedChild.parentID == fixture.templateTaskID)
    }

    @Test
    func pausedRuleStillProtectsTemplateUntilRuleIsDeleted() throws {
        let fixture = try makeFixture()
        let context = ModelContext(fixture.container)
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "eligibility"
        )
        let tasks = try repository.allNodes()
        let rule = try #require(
            try repository.taskRecurrenceRules().first
        )
        rule.isEnabled = false

        let service = TaskTrackingAvailabilityService()
        #expect(
            service.directWorkTaskIDs(
                tasks: tasks,
                recurrenceRules: [rule],
                recurrenceOccurrences: []
            ).contains(fixture.templateTaskID) == false
        )

        rule.deletedAt = fixture.now
        #expect(
            service.directWorkTaskIDs(
                tasks: tasks,
                recurrenceRules: [rule],
                recurrenceOccurrences: []
            ).contains(fixture.templateTaskID)
        )
        #expect(try repository.directWorkTask(id: fixture.templateTaskID) == nil)
    }

    @Test
    func scopedAdmissionPreservesAncestorHealthAndStagedOccurrenceRules() throws {
        let context = try makeTestContext()
        let archivedParent = TaskNode(
            title: "Archived parent",
            parentID: nil,
            deviceID: "eligibility"
        )
        archivedParent.archivedAt = Date(timeIntervalSinceReferenceDate: 1000)
        let archivedChild = TaskNode(
            title: "Archived descendant",
            parentID: archivedParent.id,
            deviceID: "eligibility"
        )
        let healthChild = TaskNode(
            title: "Staged Health descendant",
            parentID: AppleHealthTaskCatalog.taskDefinition(for: .sleep).id,
            deviceID: "eligibility"
        )
        let stagedTemplate = TaskNode(
            title: "Staged recurrence template",
            parentID: nil,
            deviceID: "eligibility"
        )
        let ordinaryTask = TaskNode(
            title: "Ordinary work",
            parentID: nil,
            deviceID: "eligibility"
        )
        context.insert(archivedParent)
        context.insert(archivedChild)
        context.insert(healthChild)
        context.insert(stagedTemplate)
        context.insert(ordinaryTask)
        context.insert(TaskRecurrenceOccurrence(
            ruleID: UUID(),
            templateTaskID: stagedTemplate.id,
            occurrenceDayKey: "2026-07-29",
            timeZoneIdentifier: "Asia/Singapore",
            deviceID: "eligibility"
        ))
        try context.save()

        let repository = SwiftDataTaskRepository(
            context: ModelContext(context.container),
            deviceID: "eligibility"
        )
        #expect(try repository.directWorkTask(id: archivedChild.id) == nil)
        #expect(try repository.directWorkTask(id: healthChild.id) == nil)
        #expect(try repository.directWorkTask(id: stagedTemplate.id) == nil)
        #expect(try repository.directWorkTask(id: ordinaryTask.id)?.id == ordinaryTask.id)
    }

    @Test
    func timerPomodoroAndManualTimeRejectTemplateBeforeMutating()
        throws
    {
        let fixture = try makeFixture()
        let timer = StoreScopedTimerCommandCoordinator(
            container: fixture.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "timer",
            nowProvider: { fixture.now }
        )

        #expect(throws: SystemActionCommandError.taskNotFound) {
            _ = try timer.start(taskID: fixture.templateTaskID)
        }
        let timerOutcome = try timer.start(
            taskID: fixture.generatedTaskID
        )
        #expect(
            timerOutcome.subjectSegment?.taskID ==
                fixture.generatedTaskID
        )
        _ = try timer.stop(
            segmentID: #require(
                timerOutcome.subjectSegment?.segmentID
            )
        )

        let pomodoro = StoreScopedPomodoroCommandCoordinator(
            container: fixture.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "pomodoro",
            nowProvider: { fixture.now }
        )
        #expect(throws: SystemActionCommandError.taskNotFound) {
            _ = try pomodoro.start(
                taskID: fixture.templateTaskID,
                focusSeconds: 1500,
                breakSeconds: 300,
                longBreakSeconds: nil,
                targetRounds: 2
            )
        }
        let focus = try pomodoro.start(
            taskID: fixture.generatedTaskID,
            focusSeconds: 1500,
            breakSeconds: 300,
            longBreakSeconds: nil,
            targetRounds: 2
        )
        #expect(
            focus.startedFocus.taskID ==
                fixture.generatedTaskID
        )

        let timeRepository = SwiftDataTimeTrackingRepository(
            context: ModelContext(fixture.container),
            deviceID: "manual",
            nowProvider: { fixture.now }
        )
        #expect(throws: TimeTrackingRepositoryError.taskUnavailable) {
            _ = try timeRepository.addManualSegment(
                taskID: fixture.templateTaskID,
                startedAt: fixture.now.addingTimeInterval(-120),
                endedAt: fixture.now.addingTimeInterval(-60),
                note: nil
            )
        }
        let manual = try timeRepository.addManualSegment(
            taskID: fixture.generatedTaskID,
            startedAt: fixture.now.addingTimeInterval(-120),
            endedAt: fixture.now.addingTimeInterval(-60),
            note: nil
        )
        #expect(manual.taskID == fixture.generatedTaskID)
    }

    @Test
    func facadeAndSharedPickerKeepTemplateAsExpandableContainer()
        throws
    {
        let fixture = try makeFixture()
        let store = makeTestStore()
        store.configureIfNeeded(
            context: ModelContext(fixture.container)
        )
        let template = try #require(
            store.task(for: fixture.templateTaskID)
        )
        let occurrence = try #require(
            store.task(for: fixture.generatedTaskID)
        )

        #expect(store.isTaskEligibleAsParent(template))
        #expect(store.isTaskAvailableForTracking(template) == false)
        #expect(store.isTaskAvailableForTracking(occurrence))
        #expect(
            store.nextDailyTaskRecurrenceBoundary(
                after: fixture.now
            ) != nil
        )

        let timerIDs = TaskHierarchyPickerMode.timer
            .selectionEligibleTaskIDs(in: store)
        let pomodoroIDs = TaskHierarchyPickerMode.singleSelection(
            selectedTaskID: nil,
            context: .pomodoro
        ).selectionEligibleTaskIDs(in: store)
        let inboxIDs = TaskHierarchyPickerMode.singleSelection(
            selectedTaskID: nil,
            context: .inboxChildTaskParent
        ).selectionEligibleTaskIDs(in: store)
        let inboxChecklistIDs = TaskHierarchyPickerMode.singleSelection(
            selectedTaskID: nil,
            context: .inboxChecklistTarget
        ).selectionEligibleTaskIDs(in: store)
        let heatmapIDs = TaskHierarchyPickerMode.multipleSelection(
            selectedTaskIDs: [],
            context: .todayHeatmap
        ).selectionEligibleTaskIDs(in: store)

        #expect(timerIDs.contains(template.id) == false)
        #expect(pomodoroIDs.contains(template.id) == false)
        #expect(inboxIDs.contains(template.id))
        #expect(inboxChecklistIDs.contains(template.id))
        #expect(heatmapIDs.contains(template.id))

        let collapsed = TaskHierarchyProjection(
            store: store,
            expandedTaskIDs: [],
            searchText: "",
            availableTaskIDs: timerIDs
        )
        let templateSection = try #require(
            collapsed.sections.first {
                $0.items.contains { $0.id == template.id }
            }
        )
        let templateItem = try #require(
            templateSection.items.first { $0.id == template.id }
        )
        let timerPicker = TaskHierarchyPicker(
            store: store,
            mode: .timer,
            onDismiss: {}
        )
        #expect(templateItem.isAvailable == false)
        #expect(templateItem.hasAvailableDescendant)
        #expect(
            timerPicker.displayedItems(in: templateSection)
                .contains { $0.id == template.id }
        )

        let expanded = TaskHierarchyProjection(
            store: store,
            expandedTaskIDs: [template.id],
            searchText: "",
            availableTaskIDs: timerIDs
        )
        let occurrenceItem = try #require(
            expanded.sections.flatMap(\.items)
                .first { $0.id == occurrence.id }
        )
        #expect(occurrenceItem.isAvailable)
    }
}

private extension TaskRecurrenceWorkEligibilityTests {
    struct Fixture {
        let container: ModelContainer
        let templateTaskID: UUID
        let generatedTaskID: UUID
        let now: Date
    }

    func makeFixture() throws -> Fixture {
        let context = try makeTestContext()
        let template = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: "Daily push-ups",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let now = try date(
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )
        let outcome = try StoreScopedTaskRecurrenceCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "recurrence"
        ).createDailyRule(
            templateTaskID: template.id,
            startDayKey: "2026-07-20",
            timeZoneIdentifier: "Asia/Singapore",
            now: now
        )
        return try Fixture(
            container: context.container,
            templateTaskID: template.id,
            generatedTaskID: #require(
                outcome.materializations.first?.generatedTaskID
            ),
            now: now
        )
    }

    func date(
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

    func recurrenceCoordinator(
        container: ModelContainer
    ) -> StoreScopedTaskRecurrenceCommandCoordinator {
        StoreScopedTaskRecurrenceCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "recurrence"
        )
    }
}
