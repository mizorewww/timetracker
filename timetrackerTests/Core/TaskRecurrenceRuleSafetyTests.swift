import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct TaskRecurrenceRuleSafetyTests {
    @Test
    func futureStartWaitsForTheConfiguredStartDay() throws {
        let context = try makeTestContext()
        let template = try makeTemplate(
            in: context,
            title: "Future daily task"
        )
        let beforeStart = try singaporeDate(
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )
        let startDay = try singaporeDate(
            year: 2026,
            month: 7,
            day: 22,
            hour: 12
        )
        let command = coordinator(context.container)

        let created = try command.createDailyRule(
            templateTaskID: template.id,
            startDayKey: "2026-07-22",
            timeZoneIdentifier: "Asia/Singapore",
            now: beforeStart
        )

        #expect(created.changedRuleTemplateTaskIDs == [template.id])
        #expect(created.materializations.isEmpty)
        #expect(
            try occurrenceDayKeys(in: context.container).isEmpty
        )
        #expect(
            try visibleTaskIDs(in: context.container) == [template.id]
        )

        let materialized = try command.materializeCurrentDay(now: startDay)

        #expect(
            materialized.materializations.map(\.generatedTaskID) == [
                TaskProgressIdentity.generatedTaskID(
                    ruleID: TaskProgressIdentity.recurrenceRuleID(
                        templateTaskID: template.id
                    ),
                    dayKey: "2026-07-22"
                ),
            ]
        )
        #expect(
            try occurrenceDayKeys(in: context.container) == ["2026-07-22"]
        )
    }

    @Test
    func createReplayCannotResumeOrReconfigureAPausedRule() throws {
        let context = try makeTestContext()
        let template = try makeTemplate(in: context, title: "Paused rule")
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
        let command = coordinator(context.container)
        _ = try command.createDailyRule(
            templateTaskID: template.id,
            startDayKey: "2026-07-20",
            timeZoneIdentifier: "Asia/Singapore",
            now: dayOne
        )
        let activeRule = try requiredRule(in: context.container)
        _ = try command.setEnabled(
            baseline: TaskRecurrenceRuleMutationBaseline(rule: activeRule),
            isEnabled: false,
            now: dayOne.addingTimeInterval(60)
        )
        let pausedSnapshot = try recurrenceSnapshot(
            in: context.container
        )

        let replay = try command.createDailyRule(
            templateTaskID: template.id,
            startDayKey: "2026-07-20",
            timeZoneIdentifier: "Asia/Singapore",
            now: dayTwo
        )

        #expect(replay == .noChanges)
        #expect(try requiredRule(in: context.container).isEnabled == false)
        #expect(
            try recurrenceSnapshot(in: context.container) == pausedSnapshot
        )

        #expect(
            throws:
                TaskRecurrenceMutationError.immutableRuleConfiguration
        ) {
            try command.createDailyRule(
                templateTaskID: template.id,
                startDayKey: "2026-07-19",
                timeZoneIdentifier: "Asia/Singapore",
                now: dayTwo
            )
        }
        #expect(
            try recurrenceSnapshot(in: context.container) == pausedSnapshot
        )

        #expect(
            throws:
                TaskRecurrenceMutationError.immutableRuleConfiguration
        ) {
            try command.createDailyRule(
                templateTaskID: template.id,
                startDayKey: "2026-07-20",
                timeZoneIdentifier: "UTC",
                now: dayTwo
            )
        }
        #expect(
            try recurrenceSnapshot(in: context.container) == pausedSnapshot
        )
    }

    @Test
    func staleBaselineRejectsAndToggleDominatesFutureClockSkew() throws {
        let context = try makeTestContext()
        let template = try makeTemplate(
            in: context,
            title: "Clock skew"
        )
        let now = try singaporeDate(
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )
        let futureSkew = try singaporeDate(
            year: 2027,
            month: 7,
            day: 20,
            hour: 12
        )
        let command = coordinator(context.container)
        _ = try command.createDailyRule(
            templateTaskID: template.id,
            startDayKey: "2026-07-20",
            timeZoneIdentifier: "Asia/Singapore",
            now: now
        )
        let initiallyActive = try requiredRule(in: context.container)
        let staleBaseline = TaskRecurrenceRuleMutationBaseline(
            rule: initiallyActive
        )
        _ = try command.setEnabled(
            baseline: staleBaseline,
            isEnabled: false,
            now: now.addingTimeInterval(60)
        )
        let pausedSnapshot = try recurrenceSnapshot(
            in: context.container
        )

        #expect(throws: TaskRecurrenceMutationError.ruleChanged) {
            try command.setEnabled(
                baseline: staleBaseline,
                isEnabled: true,
                now: now.addingTimeInterval(120)
            )
        }
        #expect(
            try recurrenceSnapshot(in: context.container) == pausedSnapshot
        )

        let skewContext = ModelContext(context.container)
        let skewedRule = try #require(
            try skewContext.fetch(FetchDescriptor<TaskRecurrenceRule>())
                .visibleDeduplicatedByID()
                .first
        )
        skewedRule.updatedAt = futureSkew
        skewedRule.clientMutationID = fixedUUID(
            "10000000-0000-0000-0000-000000000001"
        )
        try skewContext.save()
        let skewedBaseline = TaskRecurrenceRuleMutationBaseline(
            rule: skewedRule
        )

        _ = try command.setEnabled(
            baseline: skewedBaseline,
            isEnabled: true,
            now: now.addingTimeInterval(180)
        )

        let resumed = try requiredRule(in: context.container)
        #expect(resumed.isEnabled)
        #expect(resumed.updatedAt > futureSkew)
        #expect(
            resumed.clientMutationID != skewedBaseline.clientMutationID
        )
    }

    @Test
    func noncanonicalRuleIdentityRejectsToggleWithoutWrites() throws {
        let context = try makeTestContext()
        let template = try makeTemplate(
            in: context,
            title: "Invalid identity"
        )
        let now = try singaporeDate(
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )
        let rule = TaskRecurrenceRule(
            templateTaskID: template.id,
            startDayKey: "2026-07-20",
            timeZoneIdentifier: "Asia/Singapore",
            deviceID: "cloud-stage"
        )
        rule.id = fixedUUID(
            "20000000-0000-0000-0000-000000000002"
        )
        rule.createdAt = now
        rule.updatedAt = now
        rule.clientMutationID = fixedUUID(
            "20000000-0000-0000-0000-000000000003"
        )
        context.insert(rule)
        try context.save()
        let before = try recurrenceSnapshot(in: context.container)

        #expect(throws: TaskRecurrenceMutationError.ruleUnavailable) {
            try coordinator(context.container).setEnabled(
                baseline: TaskRecurrenceRuleMutationBaseline(rule: rule),
                isEnabled: false,
                now: now.addingTimeInterval(60)
            )
        }

        #expect(try recurrenceSnapshot(in: context.container) == before)
    }

    @Test
    func activeTimerPreventsRuleCreationWithoutPartialGraph() throws {
        let context = try makeTestContext()
        let template = try makeTemplate(
            in: context,
            title: "Running template"
        )
        let now = try singaporeDate(
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )
        _ = try SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "timer",
            nowProvider: { now }
        ).startTask(
            taskID: template.id,
            source: .timer
        )
        let before = try recurrenceSnapshot(in: context.container)

        #expect(
            throws: TaskRecurrenceMutationError.templateHasActiveWork
        ) {
            try coordinator(context.container).createDailyRule(
                templateTaskID: template.id,
                startDayKey: "2026-07-20",
                timeZoneIdentifier: "Asia/Singapore",
                now: now
            )
        }

        #expect(try recurrenceSnapshot(in: context.container) == before)
        #expect(
            try ModelContext(context.container)
                .fetch(FetchDescriptor<TaskRecurrenceRule>())
                .isEmpty
        )
    }

    @Test
    func archivedTemplateSkipsDaysAndUnarchiveCreatesOnlyToday()
        throws {
        let context = try makeTestContext()
        let template = try makeTemplate(
            in: context,
            title: "Archive gap"
        )
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

        try setArchived(
            true,
            taskID: template.id,
            at: dayOne.addingTimeInterval(60),
            in: context.container
        )
        let whileArchived = try command.materializeCurrentDay(now: dayTwo)

        #expect(whileArchived == .noChanges)
        #expect(
            try occurrenceDayKeys(in: context.container) == ["2026-07-20"]
        )

        try setArchived(
            false,
            taskID: template.id,
            at: dayThree.addingTimeInterval(-60),
            in: context.container
        )
        let afterUnarchive = try command.materializeCurrentDay(now: dayThree)

        #expect(
            afterUnarchive.materializations.map(\.occurrenceID) == [
                TaskProgressIdentity.recurrenceOccurrenceID(
                    ruleID: TaskProgressIdentity.recurrenceRuleID(
                        templateTaskID: template.id
                    ),
                    dayKey: "2026-07-22"
                ),
            ]
        )
        #expect(
            try occurrenceDayKeys(in: context.container) == [
                "2026-07-20",
                "2026-07-22",
            ]
        )
    }

    @Test
    func occurrenceArrivingBeforeRuleStillProtectsTemplate()
        throws {
        let context = try makeTestContext()
        let template = try makeTemplate(
            in: context,
            title: "Partial Cloud graph"
        )
        let ruleID = TaskProgressIdentity.recurrenceRuleID(
            templateTaskID: template.id
        )
        let occurrence = TaskRecurrenceOccurrence(
            ruleID: ruleID,
            templateTaskID: template.id,
            occurrenceDayKey: "2026-07-20",
            timeZoneIdentifier: "Asia/Singapore",
            deviceID: "cloud-stage"
        )
        context.insert(occurrence)
        try context.save()
        let repository = SwiftDataTaskRepository(
            context: ModelContext(context.container),
            deviceID: "reader"
        )
        let tasks = try repository.allNodes()
        let service = TaskTrackingAvailabilityService()

        #expect(service.trackableTaskIDs(tasks: tasks).contains(template.id))
        #expect(
            service.directWorkTaskIDs(
                tasks: tasks,
                recurrenceRules: [],
                recurrenceOccurrences:
                    try repository.taskRecurrenceOccurrences()
            ).contains(template.id) == false
        )
    }
}

private extension TaskRecurrenceRuleSafetyTests {
    struct RuleRevision: Equatable {
        let id: UUID
        let templateTaskID: UUID
        let startDayKey: String
        let timeZoneIdentifier: String
        let isEnabled: Bool
        let updatedAt: Date
        let deletedAt: Date?
        let deviceID: String
        let clientMutationID: UUID
    }

    struct ModelRevision: Equatable {
        let id: UUID
        let updatedAt: Date
        let deletedAt: Date?
        let clientMutationID: UUID
    }

    struct RecurrenceSnapshot: Equatable {
        let rules: [RuleRevision]
        let occurrences: [ModelRevision]
        let tasks: [ModelRevision]
    }

    func coordinator(
        _ container: ModelContainer
    ) -> StoreScopedTaskRecurrenceCommandCoordinator {
        StoreScopedTaskRecurrenceCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "recurrence-safety"
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

    func setArchived(
        _ isArchived: Bool,
        taskID: UUID,
        at mutationDate: Date,
        in container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        let task = try #require(
            try context.fetch(FetchDescriptor<TaskNode>())
                .latestByID()[taskID]
        )
        task.statusRaw = isArchived
            ? LegacyTaskStatusRaw.archived
            : LegacyTaskStatusRaw.active
        task.archivedAt = isArchived ? mutationDate : nil
        task.updatedAt = mutationDate
        task.deviceID = "archive-safety"
        task.clientMutationID = UUID()
        try context.save()
    }

    func occurrenceDayKeys(
        in container: ModelContainer
    ) throws -> [String] {
        try ModelContext(container)
            .fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
            .visibleDeduplicatedByID()
            .map(\.occurrenceDayKey)
            .sorted()
    }

    func visibleTaskIDs(
        in container: ModelContainer
    ) throws -> [UUID] {
        try ModelContext(container)
            .fetch(FetchDescriptor<TaskNode>())
            .visibleDeduplicatedByID()
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    func recurrenceSnapshot(
        in container: ModelContainer
    ) throws -> RecurrenceSnapshot {
        let context = ModelContext(container)
        let rules = try context.fetch(FetchDescriptor<TaskRecurrenceRule>())
            .map {
                RuleRevision(
                    id: $0.id,
                    templateTaskID: $0.templateTaskID,
                    startDayKey: $0.startDayKey,
                    timeZoneIdentifier: $0.timeZoneIdentifier,
                    isEnabled: $0.isEnabled,
                    updatedAt: $0.updatedAt,
                    deletedAt: $0.deletedAt,
                    deviceID: $0.deviceID,
                    clientMutationID: $0.clientMutationID
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let occurrences = try context.fetch(
            FetchDescriptor<TaskRecurrenceOccurrence>()
        )
        .map {
            ModelRevision(
                id: $0.id,
                updatedAt: $0.updatedAt,
                deletedAt: $0.deletedAt,
                clientMutationID: $0.clientMutationID
            )
        }
        .sorted { $0.id.uuidString < $1.id.uuidString }
        let tasks = try context.fetch(FetchDescriptor<TaskNode>())
            .map {
                ModelRevision(
                    id: $0.id,
                    updatedAt: $0.updatedAt,
                    deletedAt: $0.deletedAt,
                    clientMutationID: $0.clientMutationID
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        return RecurrenceSnapshot(
            rules: rules,
            occurrences: occurrences,
            tasks: tasks
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

    func fixedUUID(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
