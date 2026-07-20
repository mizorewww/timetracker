import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskPlanningSchemaCompatibilityTests {
    @Test @MainActor
    func versionTwelveStoreMigratesToTaskProgressSchema() throws {
        let fixture = try LegacyV12TaskPlanningStoreFixture.create()
        defer { fixture.remove() }

        try fixture.withCurrentContext { context in
            let tasks = try context.fetch(FetchDescriptor<TaskNode>())
            let task = try #require(
                tasks.first { $0.id == fixture.taskID }
            )

            #expect(task.title == "V12 preserved task")
            #expect(try context.fetch(FetchDescriptor<TaskRecurrenceRule>()).isEmpty)
            #expect(try context.fetch(FetchDescriptor<TaskRecurrenceOccurrence>()).isEmpty)
            #expect(try context.fetch(FetchDescriptor<TaskQuantityGoal>()).isEmpty)
            #expect(try context.fetch(FetchDescriptor<TaskQuantityEntry>()).isEmpty)
            #expect(
                TimeTrackerMigrationPlan.schemas.last?.versionIdentifier
                    == TimeTrackerSchemaV13.versionIdentifier
            )

            let rule = TaskRecurrenceRule(
                templateTaskID: task.id,
                startDayKey: "2026-07-20",
                timeZoneIdentifier: "Asia/Singapore",
                deviceID: "test"
            )
            let occurrence = TaskRecurrenceOccurrence(
                ruleID: rule.id,
                templateTaskID: task.id,
                occurrenceDayKey: "2026-07-20",
                timeZoneIdentifier: rule.timeZoneIdentifier,
                deviceID: "test"
            )
            let goal = TaskQuantityGoal(
                taskID: task.id,
                targetAmount: 50,
                unitLabel: "push-ups",
                deviceID: "test"
            )
            let entry = TaskQuantityEntry(
                id: UUID(),
                taskID: task.id,
                amount: 20,
                deviceID: "test"
            )
            context.insert(rule)
            context.insert(occurrence)
            context.insert(goal)
            context.insert(entry)
            try context.save()

            #expect(
                try context.fetch(FetchDescriptor<TaskRecurrenceRule>())
                    .map(\.id) == [rule.id]
            )
            #expect(
                try context.fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
                    .map(\.generatedTaskID) == [occurrence.generatedTaskID]
            )
            #expect(
                try context.fetch(FetchDescriptor<TaskQuantityGoal>())
                    .map(\.id) == [goal.id]
            )
            #expect(
                try context.fetch(FetchDescriptor<TaskQuantityEntry>())
                    .map(\.quantityGoalID) == [goal.id]
            )
        }
    }
}
