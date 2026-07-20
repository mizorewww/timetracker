import Foundation
import SwiftData
@testable import timetracker

enum TaskProgressPersistenceTestIDs {
    static let templateTask = UUID(
        uuidString: "11111111-2222-3333-4444-555555555555"
    )!
    static let quantityEntry = UUID(
        uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
    )!
}

@MainActor
struct TaskProgressPersistenceFixture {
    let templateTask: TaskNode
    let generatedTask: TaskNode
    let rule: TaskRecurrenceRule
    let occurrence: TaskRecurrenceOccurrence
    let goal: TaskQuantityGoal
    let entry: TaskQuantityEntry
}

@MainActor
func makeTaskProgressPersistenceFixture(
    timestamp: Date = Date(timeIntervalSinceReferenceDate: 100_000),
    deviceID: String = "task-progress-test"
) -> TaskProgressPersistenceFixture {
    let templateTask = TaskNode(
        title: "Daily push-ups",
        parentID: nil,
        deviceID: deviceID
    )
    templateTask.id = TaskProgressPersistenceTestIDs.templateTask
    templateTask.createdAt = timestamp
    templateTask.updatedAt = timestamp

    let rule = TaskRecurrenceRule(
        templateTaskID: templateTask.id,
        startDayKey: "2026-07-20",
        timeZoneIdentifier: "Asia/Singapore",
        deviceID: deviceID
    )
    rule.createdAt = timestamp
    rule.updatedAt = timestamp

    let occurrence = TaskRecurrenceOccurrence(
        ruleID: rule.id,
        templateTaskID: templateTask.id,
        occurrenceDayKey: "2026-07-20",
        timeZoneIdentifier: rule.timeZoneIdentifier,
        deviceID: deviceID
    )
    occurrence.createdAt = timestamp
    occurrence.updatedAt = timestamp

    let generatedTask = TaskNode(
        title: "50 push-ups",
        parentID: templateTask.id,
        deviceID: deviceID
    )
    generatedTask.id = occurrence.generatedTaskID
    generatedTask.createdAt = timestamp
    generatedTask.updatedAt = timestamp

    let goal = TaskQuantityGoal(
        taskID: generatedTask.id,
        targetAmount: 50,
        unitLabel: "push-ups",
        deviceID: deviceID
    )
    goal.createdAt = timestamp
    goal.updatedAt = timestamp

    let entry = TaskQuantityEntry(
        id: TaskProgressPersistenceTestIDs.quantityEntry,
        taskID: generatedTask.id,
        amount: 20,
        recordedAt: timestamp.addingTimeInterval(30),
        createdAt: timestamp,
        deviceID: deviceID
    )

    return TaskProgressPersistenceFixture(
        templateTask: templateTask,
        generatedTask: generatedTask,
        rule: rule,
        occurrence: occurrence,
        goal: goal,
        entry: entry
    )
}

@MainActor
@discardableResult
func insertTaskProgressPersistenceFixture(
    into context: ModelContext,
    timestamp: Date = Date(timeIntervalSinceReferenceDate: 100_000)
) throws -> TaskProgressPersistenceFixture {
    let fixture = makeTaskProgressPersistenceFixture(timestamp: timestamp)
    context.insert(fixture.templateTask)
    context.insert(fixture.generatedTask)
    context.insert(fixture.rule)
    context.insert(fixture.occurrence)
    context.insert(fixture.goal)
    context.insert(fixture.entry)
    try context.save()
    return fixture
}
