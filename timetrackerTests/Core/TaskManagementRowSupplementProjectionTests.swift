import Foundation
import SwiftData
import Testing
@testable import timetracker

/// Tasks-page row supplement projection contracts.
///
/// `TaskManagementRowSupplementProjection` is cached per task-read-model
/// revision. These tests assert the observable semantics the cache must
/// preserve: a fresh store reports no supplement, a quantity goal + entry
/// mutation is reflected on the next read (cache invalidation), and the
/// projection is stable across repeated reads with unchanged data.
@Suite(.serialized)
@MainActor
struct TaskManagementRowSupplementProjectionTests {
    @Test
    func freshStoreReportsNoQuantitySupplement() throws {
        let context = try makeTestContext()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: "Plain task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )

        let supplement = store.taskManagementRowSupplementProjection()
            .supplement(for: task.id)

        #expect(supplement.quantityProgress == nil)
        #expect(supplement.recurrenceRole == nil)
    }

    @Test
    func quantityMutationIsReflectedAfterCachedRead() throws {
        let context = try makeTestContext()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: "Quantified task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )

        // Prime the cache while the task has no quantity goal.
        let before = store.taskManagementRowSupplementProjection()
            .supplement(for: task.id)
        #expect(before.quantityProgress == nil)

        // Durable write: attach a goal, then record one entry.
        var draft = TaskEditorDraft(task: task, checklistItems: [])
        draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 10,
            unitLabel: "cups"
        )
        let saveResult = store.saveTaskDraftResult(draft)
        guard case let .saved(savedTaskID) = saveResult else {
            Issue.record("Goal save failed: \(saveResult)")
            return
        }
        #expect(
            store.recordTaskQuantity(
                taskID: savedTaskID,
                amount: 3,
                entryID: UUID()
            )
        )

        let after = store.taskManagementRowSupplementProjection()
            .supplement(for: savedTaskID)

        let progress = try #require(after.quantityProgress)
        #expect(progress.targetAmount == 10)
        #expect(progress.totalAmount == 3)
        #expect(progress.unitLabel == "cups")
    }

    @Test
    func unchangedDataYieldsIdenticalProjectionAcrossReads() throws {
        let context = try makeTestContext()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: "Stable task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )

        let first = store.taskManagementRowSupplementProjection()
        let second = store.taskManagementRowSupplementProjection()

        #expect(first.supplement(for: task.id).quantityProgress == nil)
        #expect(
            first.supplement(for: task.id).quantityProgress ==
                second.supplement(for: task.id).quantityProgress
        )
    }
}
