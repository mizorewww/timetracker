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
    func activePomodoroBlocksRecurrenceTemplateCreationWhileCompletedHistoryAllowsIt() throws {
        let context = try makeTestContext()
        let activeTask = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(title: "Active focus", parentID: nil)
        let completedTask = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(title: "Past focus", parentID: nil)
        let now = try date(year: 2026, month: 8, day: 2, hour: 12)

        let activeRun = PomodoroRun(taskID: activeTask.id, deviceID: "pomodoro")
        activeRun.state = .focusing
        let completedRun = PomodoroRun(taskID: completedTask.id, deviceID: "pomodoro")
        completedRun.state = .completed
        completedRun.endedAt = now
        context.insert(activeRun)
        context.insert(completedRun)
        try context.save()

        let coordinator = recurrenceCoordinator(container: context.container)
        #expect(throws: TaskRecurrenceMutationError.templateHasActiveWork) {
            _ = try coordinator.createDailyRule(
                templateTaskID: activeTask.id,
                startDayKey: "2026-08-02",
                timeZoneIdentifier: "Asia/Singapore",
                now: now
            )
        }
        let outcome = try coordinator.createDailyRule(
            templateTaskID: completedTask.id,
            startDayKey: "2026-08-02",
            timeZoneIdentifier: "Asia/Singapore",
            now: now
        )
        #expect(outcome.materializations.count == 1)
    }

    @Test
    func pausedRuleAndStagedOccurrenceStillProtectTemplateFromDirectWork() throws {
        let fixture = try makeFixture()
        let context = ModelContext(fixture.container)
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "eligibility"
        )
        let rule = try #require(try repository.taskRecurrenceRules().first)
        rule.isEnabled = false
        try context.save()

        #expect(try repository.directWorkTask(id: fixture.templateTaskID) == nil)
        rule.deletedAt = fixture.now
        try context.save()
        // Occurrence still claims the template even after the rule is tombstoned.
        #expect(try repository.directWorkTask(id: fixture.templateTaskID) == nil)
        #expect(try repository.directWorkTask(id: fixture.generatedTaskID)?.id == fixture.generatedTaskID)
    }

    @Test
    func timerPomodoroAndManualTimeRejectTemplateAndAcceptGeneratedOccurrence() throws {
        let fixture = try makeFixture()
        let timer = StoreScopedTimerCommandCoordinator(
            session: .testHarness(fixture.container),
            deviceID: "timer",
            nowProvider: { fixture.now }
        )

        #expect(throws: SystemActionCommandError.taskNotFound) {
            _ = try timer.start(taskID: fixture.templateTaskID)
        }
        let timerOutcome = try timer.start(taskID: fixture.generatedTaskID)
        #expect(timerOutcome.subjectSegment?.taskID == fixture.generatedTaskID)
        _ = try timer.stop(segmentID: #require(timerOutcome.subjectSegment?.segmentID))

        let pomodoro = StoreScopedPomodoroCommandCoordinator(
            session: .testHarness(fixture.container),
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
        #expect(focus.startedFocus.taskID == fixture.generatedTaskID)

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
    func setEnabledTogglesRuleValidatesBaselineAndCopiesQuantityBlueprint() throws {
        let context = try makeTestContext()
        let template = try SwiftDataTaskRepository(context: context, deviceID: "seed")
            .createTask(title: "Read daily", parentID: nil)
        let templateGoal = TaskQuantityGoal(
            taskID: template.id,
            targetAmount: 30,
            unitLabel: "pages",
            deviceID: "seed"
        )
        context.insert(templateGoal)
        try context.save()

        let coordinator = recurrenceCoordinator(container: context.container)
        let beforeStart = try date(year: 2026, month: 8, day: 1, hour: 12)
        let activeDay = try date(year: 2026, month: 8, day: 2, hour: 12)

        // Start on 2026-08-02; materializing on 2026-08-01 must skip occurrence creation.
        let initialOutcome = try coordinator.createDailyRule(
            templateTaskID: template.id,
            startDayKey: "2026-08-02",
            timeZoneIdentifier: "Asia/Singapore",
            now: beforeStart
        )
        #expect(initialOutcome.materializations.isEmpty)

        let ruleBeforeToggle = try #require(
            try ModelContext(context.container).fetch(FetchDescriptor<TaskRecurrenceRule>()).first
        )
        let initialBaseline = TaskRecurrenceRuleMutationBaseline(rule: ruleBeforeToggle)

        // Pause the rule: materializing on 2026-08-02 while paused does nothing.
        _ = try coordinator.setEnabled(
            baseline: initialBaseline,
            isEnabled: false,
            now: activeDay
        )
        #expect(try coordinator.materializeCurrentDay(now: activeDay).materializations.isEmpty)

        // Stale baseline is rejected.
        #expect(throws: TaskRecurrenceMutationError.ruleChanged) {
            _ = try coordinator.setEnabled(
                baseline: initialBaseline,
                isEnabled: true,
                now: activeDay.addingTimeInterval(10)
            )
        }

        // Re-enabling with fresh baseline materializes today's occurrence and copies the quantity goal blueprint.
        let pausedRule = try #require(
            try ModelContext(context.container).fetch(FetchDescriptor<TaskRecurrenceRule>()).first
        )
        let resumeOutcome = try coordinator.setEnabled(
            baseline: TaskRecurrenceRuleMutationBaseline(rule: pausedRule),
            isEnabled: true,
            now: activeDay.addingTimeInterval(20)
        )
        let materialization = try #require(resumeOutcome.materializations.first)
        let copiedGoalID = try #require(materialization.generatedQuantityGoalID)
        let copiedGoal = try #require(
            try ModelContext(context.container)
                .fetch(FetchDescriptor<TaskQuantityGoal>())
                .first { $0.id == copiedGoalID }
        )
        #expect(copiedGoal.taskID == materialization.generatedTaskID)
        #expect(copiedGoal.targetAmount == 30)
        #expect(copiedGoal.unitLabel == "pages")
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
        let now = try date(year: 2026, month: 7, day: 20, hour: 12)
        let outcome = try recurrenceCoordinator(container: context.container)
            .createDailyRule(
                templateTaskID: template.id,
                startDayKey: "2026-07-20",
                timeZoneIdentifier: "Asia/Singapore",
                now: now
            )
        return try Fixture(
            container: context.container,
            templateTaskID: template.id,
            generatedTaskID: #require(outcome.materializations.first?.generatedTaskID),
            now: now
        )
    }

    func date(year: Int, month: Int, day: Int, hour: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Singapore"))
        return try #require(
            calendar.date(
                from: DateComponents(year: year, month: month, day: day, hour: hour)
            )
        )
    }

    func recurrenceCoordinator(
        container: ModelContainer
    ) -> StoreScopedTaskRecurrenceCommandCoordinator {
        StoreScopedTaskRecurrenceCommandCoordinator(
            session: .testHarness(container),
            deviceID: "recurrence"
        )
    }
}
