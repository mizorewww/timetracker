import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct AITaskAtomicMutationExecutorTests {
    private enum InjectedFailure: Error {
        case checkpoint
    }

    @Test
    func applyRunsPersistenceWorkOutsideMainThread() async throws {
        let context = try makeTestContext()
        let taskID = try seedTasks(count: 1, in: context)[0]
        let coordinator = try StoreScopedAITaskAtomicMutationCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "ai-executor-test",
            didReachCheckpoint: { checkpoint in
                guard case .operationApplied = checkpoint else { return }
                #expect(Thread.isMainThread == false)
            }
        )
        let baseline = try await coordinator.captureBaseline()
        let operation = try updateOperation(
            taskID: taskID,
            title: "Updated off main",
            baseline: baseline
        )

        let outcome = try await coordinator.apply(
            AITaskAtomicMutationPlan(
                baseline: baseline,
                operations: [operation]
            )
        )

        #expect(outcome.didMutateTasks)
        #expect(try persistedTask(taskID, container: context.container)?.title == "Updated off main")
    }

    @Test
    func applyRejectsAStaleCompleteBaselineWithoutMutation() async throws {
        let context = try makeTestContext()
        let taskID = try seedTasks(count: 1, in: context)[0]
        let coordinator = try StoreScopedAITaskAtomicMutationCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "ai-stale-test"
        )
        let baseline = try await coordinator.captureBaseline()
        let operation = try updateOperation(
            taskID: taskID,
            title: "AI proposal",
            baseline: baseline
        )

        let externalContext = ModelContext(context.container)
        let externallyChanged = try #require(
            try persistedTask(taskID, context: externalContext)
        )
        externallyChanged.title = "External edit"
        externallyChanged.updatedAt = Date()
        externallyChanged.clientMutationID = UUID()
        try externalContext.save()

        await #expect(throws: AITaskAtomicMutationError.workspaceChanged) {
            try await coordinator.apply(
                AITaskAtomicMutationPlan(
                    baseline: baseline,
                    operations: [operation]
                )
            )
        }
        #expect(try persistedTask(taskID, container: context.container)?.title == "External edit")
    }

    @Test
    func checkpointFailureRollsBackEveryReviewedOperation() async throws {
        let context = try makeTestContext()
        let taskIDs = try seedTasks(count: 2, in: context)
        let coordinator = try StoreScopedAITaskAtomicMutationCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "ai-rollback-test",
            didReachCheckpoint: { checkpoint in
                if checkpoint == .operationApplied(index: 0) {
                    throw InjectedFailure.checkpoint
                }
            }
        )
        let baseline = try await coordinator.captureBaseline()
        let operations = try taskIDs.enumerated().map { index, taskID in
            try updateOperation(
                taskID: taskID,
                title: "Proposed \(index)",
                baseline: baseline
            )
        }

        await #expect(throws: InjectedFailure.checkpoint) {
            try await coordinator.apply(
                AITaskAtomicMutationPlan(
                    baseline: baseline,
                    operations: operations
                )
            )
        }

        let persistedTitles = try taskIDs.map {
            let task = try persistedTask(
                $0,
                container: context.container
            )
            return try #require(task).title
        }
        #expect(persistedTitles == ["Task 0", "Task 1"])
    }

    @Test
    func applyRejectsArchivePlanWhoseRecordedDescendantsHideActiveWork() async throws {
        let context = try makeTestContext()
        let parent = TaskNode(
            title: "Parent",
            parentID: nil,
            deviceID: "ai-archive-test",
            sortOrder: 0
        )
        let child = TaskNode(
            title: "Child",
            parentID: parent.id,
            deviceID: "ai-archive-test",
            sortOrder: 0
        )
        context.insert(parent)
        context.insert(child)
        context.insert(
            TimeSegment(
                sessionID: UUID(),
                taskID: child.id,
                source: .timer,
                deviceID: "ai-archive-test",
                startedAt: Date(),
                endedAt: nil
            )
        )
        try context.save()

        let coordinator = try StoreScopedAITaskAtomicMutationCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "ai-archive-test"
        )
        let baseline = try await coordinator.captureBaseline()
        let before = try #require(
            baseline.snapshot.tasks.first { $0.id == parent.id }
        )
        var after = before
        after.isArchived = true
        // Forged payload: the plan records no descendants although the
        // replayed overlay recomputes the child under the archived branch.
        let forgedOperation = AITaskWorkspaceOperation.archiveTask(
            before: before,
            after: after,
            affectedDescendantIDs: []
        )

        await #expect(throws: AITaskAtomicMutationError.activeWorkMustStop) {
            try await coordinator.apply(
                AITaskAtomicMutationPlan(
                    baseline: baseline,
                    operations: [forgedOperation]
                )
            )
        }
        #expect(
            try persistedTask(parent.id, container: context.container)?
                .archivedAt == nil
        )
    }

    private func seedTasks(
        count: Int,
        in context: ModelContext
    ) throws -> [UUID] {
        let tasks = (0 ..< count).map { index in
            TaskNode(
                title: "Task \(index)",
                parentID: nil,
                deviceID: "ai-executor-seed",
                sortOrder: Double(index)
            )
        }
        tasks.forEach(context.insert)
        try context.save()
        return tasks.map(\.id)
    }

    private func updateOperation(
        taskID: UUID,
        title: String,
        baseline: AITaskAtomicMutationBaseline
    ) throws -> AITaskWorkspaceOperation {
        let before = try #require(
            baseline.snapshot.tasks.first { $0.id == taskID }
        )
        var after = before
        after.title = title
        after.path = title
        return .updateTask(before: before, after: after)
    }

    private func persistedTask(
        _ taskID: UUID,
        container: ModelContainer
    ) throws -> TaskNode? {
        try persistedTask(taskID, context: ModelContext(container))
    }

    private func persistedTask(
        _ taskID: UUID,
        context: ModelContext
    ) throws -> TaskNode? {
        let requestedID = taskID
        return try context.fetch(
            FetchDescriptor<TaskNode>(
                predicate: #Predicate { $0.id == requestedID }
            )
        ).visibleDeduplicatedByID().first
    }
}
