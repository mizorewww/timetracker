import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct TaskQuantityDetailReadModelTests {
    @Test
    func generatedTaskDetailUsesCanonicalProgressAndStoredLocalDay()
        throws {
        let context = try makeTestContext()
        let fixture = try insertTaskProgressPersistenceFixture(
            into: context
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        let detail = try availableDetail(
            store.taskQuantityDetail(for: fixture.generatedTask.id)
        )

        #expect(detail.progress.totalAmount == 20)
        #expect(detail.progress.remainingAmount == 30)
        #expect(detail.entries.map(\.id) == [fixture.entry.id])
        guard case .generated(let occurrence) = detail.recurrenceRole else {
            Issue.record("Expected generated recurrence role")
            return
        }
        #expect(occurrence.dayKey == "2026-07-20")
        #expect(occurrence.timeZoneIdentifier == "Asia/Singapore")
        #expect(
            TaskRecurrenceDayKey.value(
                for: occurrence.localDate,
                timeZone: try #require(
                    TimeZone(identifier: occurrence.timeZoneIdentifier)
                )
            ) == occurrence.dayKey
        )
    }

    @Test
    func detailFiltersTombstonesAndSortsNewestThenStableID() throws {
        let context = try makeTestContext()
        let fixture = try makeQuantityTask(in: context)
        let sharedDate = Date(timeIntervalSinceReferenceDate: 1_000)
        let earlier = quantityEntry(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000000")!,
            taskID: fixture.task.id,
            amount: 10,
            date: sharedDate.addingTimeInterval(-10)
        )
        let firstAtSharedDate = quantityEntry(
            id: UUID(uuidString: "20000000-0000-4000-8000-000000000000")!,
            taskID: fixture.task.id,
            amount: 20,
            date: sharedDate
        )
        let secondAtSharedDate = quantityEntry(
            id: UUID(uuidString: "30000000-0000-4000-8000-000000000000")!,
            taskID: fixture.task.id,
            amount: 30,
            date: sharedDate
        )
        let tombstone = quantityEntry(
            id: UUID(),
            taskID: fixture.task.id,
            amount: 40,
            date: sharedDate.addingTimeInterval(10)
        )
        tombstone.deletedAt = sharedDate.addingTimeInterval(20)
        tombstone.updatedAt = tombstone.deletedAt!
        [earlier, firstAtSharedDate, secondAtSharedDate, tombstone]
            .forEach(context.insert)
        try context.save()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        let detail = try availableDetail(
            store.taskQuantityDetail(for: fixture.task.id)
        )

        #expect(detail.progress.totalAmount == 60)
        #expect(
            detail.entries.map(\.id) == [
                firstAtSharedDate.id,
                secondAtSharedDate.id,
                earlier.id
            ]
        )
        #expect(detail.recurrenceRole == .ordinary)
    }

    @Test
    func migratedRecurringTemplateKeepsHistoryReadOnly() throws {
        let context = try makeTestContext()
        let fixture = makeTaskProgressPersistenceFixture()
        context.insert(fixture.templateTask)
        context.insert(fixture.generatedTask)
        context.insert(fixture.rule)
        context.insert(fixture.occurrence)
        context.insert(
            TaskQuantityGoal(
                taskID: fixture.templateTask.id,
                targetAmount: 50,
                unitLabel: "push-ups",
                deviceID: "seed"
            )
        )
        let historicalEntry = quantityEntry(
            id: UUID(),
            taskID: fixture.templateTask.id,
            amount: 20,
            date: Date(timeIntervalSinceReferenceDate: 900)
        )
        context.insert(historicalEntry)
        try context.save()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        let detail = try availableDetail(
            store.taskQuantityDetail(for: fixture.templateTask.id)
        )

        #expect(detail.progress.isRecordingAllowed == false)
        #expect(detail.recurrenceRole == .template)
        #expect(detail.progress.totalAmount == 20)
        #expect(detail.entries.map(\.id) == [historicalEntry.id])
    }

    @Test
    func occurrenceOnlyCloudStageFailsQuantityDetailClosed() throws {
        let context = try makeTestContext()
        let fixture = try makeQuantityTask(
            in: context,
            title: "Staged recurrence"
        )
        context.insert(
            TaskRecurrenceOccurrence(
                ruleID: TaskProgressIdentity.recurrenceRuleID(
                    templateTaskID: fixture.task.id
                ),
                templateTaskID: fixture.task.id,
                occurrenceDayKey: "2026-07-21",
                timeZoneIdentifier: "Asia/Singapore",
                deviceID: "cloud-stage"
            )
        )
        try context.save()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        #expect(
            store.taskIDsWithIncompleteRecurrence == [fixture.task.id]
        )
        #expect(store.isTaskRecurrenceTemplate(fixture.task))
        #expect(store.isTaskAvailableForTracking(fixture.task) == false)
        #expect(
            store.taskQuantityDetail(for: fixture.task.id) == .incomplete
        )
    }

    @Test
    func missingAndMalformedQuantityDetailFailClosed() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        )
        let plain = try repository.createTask(
            title: "Plain",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let malformed = try makeQuantityTask(
            in: context,
            title: "Malformed"
        )
        let entry = quantityEntry(
            id: UUID(),
            taskID: malformed.task.id,
            amount: 1,
            date: Date(timeIntervalSinceReferenceDate: 2_000)
        )
        entry.quantityGoalID = UUID()
        context.insert(entry)
        try context.save()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        #expect(store.taskQuantityDetail(for: plain.id) == .none)
        #expect(
            store.taskQuantityDetail(for: malformed.task.id) ==
                .incomplete
        )
    }

    private func availableDetail(
        _ readModel: TaskQuantityDetailReadModel
    ) throws -> TaskQuantityDetailSnapshot {
        guard case .available(let detail) = readModel else {
            Issue.record("Expected available quantity detail")
            throw DetailTestError.unavailable
        }
        return detail
    }

    private func makeQuantityTask(
        in context: ModelContext,
        title: String = "Quantity"
    ) throws -> (task: TaskNode, goal: TaskQuantityGoal) {
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: title,
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let goal = TaskQuantityGoal(
            taskID: task.id,
            targetAmount: 100,
            unitLabel: "reps",
            deviceID: "seed"
        )
        context.insert(goal)
        try context.save()
        return (task, goal)
    }

    private func quantityEntry(
        id: UUID,
        taskID: UUID,
        amount: Int,
        date: Date
    ) -> TaskQuantityEntry {
        TaskQuantityEntry(
            id: id,
            taskID: taskID,
            amount: amount,
            recordedAt: date,
            createdAt: date,
            deviceID: "seed"
        )
    }
}

private enum DetailTestError: Error {
    case unavailable
}
