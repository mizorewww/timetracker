import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedAITaskAtomicMutationCoordinatorTests {
    @Test
    func mixedCategoryTaskAndChecklistCRUDCommitsOnceAndTaskDeleteArchives() throws {
        let context = try makeTestContext()
        let fixture = try seedWorkspace(in: context)
        let command = coordinator(container: context.container)
        let baseline = try command.captureBaseline()
        var overlay = AITaskWorkspaceOverlay(snapshot: baseline.snapshot)
        let createdCategoryID = UUID()
        let createdTaskID = UUID()
        let createdChecklistID = UUID()

        _ = try overlay.createCategory(
            id: createdCategoryID,
            title: "Personal",
            iconName: "person",
            colorHex: "34C759"
        )
        _ = try overlay.updateCategory(
            id: fixture.workCategoryID,
            title: "Focused Work",
            iconName: "briefcase",
            colorHex: "FF9500",
            includesInForecast: false
        )
        _ = try overlay.createTask(
            id: createdTaskID,
            title: "New root",
            parentID: nil,
            categoryID: createdCategoryID,
            notes: "Created by the reviewed plan",
            estimatedMinutes: 25,
            dueAt: nil,
            iconName: "target",
            colorHex: "34C759",
            quantityGoal: TaskQuantityGoalDraft(
                targetAmount: 50,
                unitLabel: "pages"
            ),
            dailyRecurrence: TaskDailyRecurrenceDraft(
                isEnabled: true,
                startDayKey: "2026-07-26",
                timeZoneIdentifier: "Asia/Singapore"
            )
        )
        _ = try overlay.updateTask(
            id: fixture.rootTaskID,
            title: "Renamed root",
            parentID: nil,
            categoryID: fixture.workCategoryID,
            notes: "Updated notes",
            estimatedMinutes: 45,
            dueAt: nil,
            iconName: "briefcase",
            colorHex: "FF9500"
        )
        _ = try overlay.createChecklistItem(
            id: createdChecklistID,
            taskID: createdTaskID,
            title: "Created checklist",
            isCompleted: false,
            iconName: "pencil",
            colorHex: "5E5CE6"
        )
        _ = try overlay.updateChecklistItem(
            id: fixture.updatedChecklistID,
            title: "Updated checklist",
            isCompleted: true,
            iconName: "checkmark.circle",
            colorHex: "34C759"
        )
        _ = try overlay.deleteChecklistItem(id: fixture.deletedChecklistID)
        _ = try overlay.deleteCategory(id: fixture.obsoleteCategoryID)
        _ = try overlay.deleteTask(id: fixture.archivedTaskID)

        let outcome = try command.apply(
            AITaskAtomicMutationPlan(
                baseline: baseline,
                operations: overlay.operations
            )
        )

        #expect(outcome.didMutate)
        #expect(
            outcome.events.contains(
                .taskChanged(taskID: nil, affectedAncestorIDs: [])
            )
        )
        #expect(
            outcome.events.contains(
                .checklistChanged(taskID: nil, affectedAncestorIDs: [])
            )
        )

        let fresh = ModelContext(context.container)
        let categories = try fresh.fetch(FetchDescriptor<TaskCategory>())
            .visibleDeduplicatedByID()
        #expect(categories.first { $0.id == createdCategoryID }?.title == "Personal")
        let work = try #require(categories.first { $0.id == fixture.workCategoryID })
        #expect(work.title == "Focused Work")
        #expect(work.includesInForecast == false)
        #expect(categories.contains { $0.id == fixture.obsoleteCategoryID } == false)

        let tasks = try fresh.fetch(FetchDescriptor<TaskNode>())
            .visibleDeduplicatedByID()
        let createdTask = try #require(tasks.first { $0.id == createdTaskID })
        #expect(createdTask.notes == "Created by the reviewed plan")
        #expect(createdTask.estimatedSeconds == 25 * 60)
        let quantityGoal = try #require(
            try fresh.fetch(FetchDescriptor<TaskQuantityGoal>())
                .visibleDeduplicatedByID()
                .first { $0.taskID == createdTaskID }
        )
        #expect(quantityGoal.targetAmount == 50)
        #expect(quantityGoal.unitLabel == "pages")
        let recurrenceRule = try #require(
            try fresh.fetch(FetchDescriptor<TaskRecurrenceRule>())
                .visibleDeduplicatedByID()
                .first { $0.templateTaskID == createdTaskID }
        )
        #expect(recurrenceRule.isEnabled)
        #expect(recurrenceRule.startDayKey == "2026-07-26")
        #expect(recurrenceRule.timeZoneIdentifier == "Asia/Singapore")
        let updatedTask = try #require(tasks.first { $0.id == fixture.rootTaskID })
        #expect(updatedTask.title == "Renamed root")
        #expect(updatedTask.notes == "Updated notes")
        let archivedTask = try #require(tasks.first { $0.id == fixture.archivedTaskID })
        #expect(archivedTask.isArchivedForLifecycle)
        #expect(archivedTask.deletedAt == nil)

        let assignments = try fresh.fetch(
            FetchDescriptor<TaskCategoryAssignment>()
        ).visibleDeduplicatedByID().logicalWinnersByTaskID()
        #expect(assignments[createdTaskID]?.categoryID == createdCategoryID)
        #expect(assignments[fixture.archivedTaskID] == nil)

        let checklistItems = try fresh.fetch(FetchDescriptor<ChecklistItem>())
            .visibleDeduplicatedByID()
        #expect(
            checklistItems.first { $0.id == createdChecklistID }?.taskID ==
                createdTaskID
        )
        let updatedChecklist = try #require(
            checklistItems.first { $0.id == fixture.updatedChecklistID }
        )
        #expect(updatedChecklist.title == "Updated checklist")
        #expect(updatedChecklist.isCompleted)
        #expect(
            checklistItems.contains { $0.id == fixture.deletedChecklistID } ==
                false
        )
    }

    @Test
    func fullWorkspaceStaleBaselineRejectsWithoutWritesOrCheckpoints() throws {
        let context = try makeTestContext()
        let fixture = try seedWorkspace(in: context)
        var checkpoints: [AITaskAtomicMutationCheckpoint] = []
        let command = coordinator(
            container: context.container,
            checkpoint: { checkpoints.append($0) }
        )
        let baseline = try command.captureBaseline()
        var overlay = AITaskWorkspaceOverlay(snapshot: baseline.snapshot)
        _ = try overlay.updateTask(
            id: fixture.rootTaskID,
            title: "Must not apply",
            parentID: nil,
            categoryID: fixture.workCategoryID,
            notes: "Must not apply",
            estimatedMinutes: 15,
            dueAt: nil,
            iconName: "target",
            colorHex: "FF9500"
        )

        let sibling = ModelContext(context.container)
        let siblingCategory = try #require(
            try sibling.fetch(FetchDescriptor<TaskCategory>())
                .visibleDeduplicatedByID()
                .first { $0.id == fixture.obsoleteCategoryID }
        )
        siblingCategory.title = "Changed elsewhere"
        siblingCategory.updatedAt = Date()
        siblingCategory.clientMutationID = UUID()
        try sibling.save()

        #expect(throws: AITaskAtomicMutationError.workspaceChanged) {
            try command.apply(
                AITaskAtomicMutationPlan(
                    baseline: baseline,
                    operations: overlay.operations
                )
            )
        }
        #expect(checkpoints.isEmpty)

        let fresh = ModelContext(context.container)
        let root = try #require(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .visibleDeduplicatedByID()
                .first { $0.id == fixture.rootTaskID }
        )
        #expect(root.title == "Root")
        #expect(root.notes == nil)
    }

    @Test
    func injectedFailureRollsBackTheWholeMixedMutation() throws {
        let context = try makeTestContext()
        _ = try seedWorkspace(in: context)
        let baseline = try coordinator(container: context.container)
            .captureBaseline()
        var overlay = AITaskWorkspaceOverlay(snapshot: baseline.snapshot)
        let categoryID = UUID()
        let taskID = UUID()
        let checklistID = UUID()
        _ = try overlay.createCategory(
            id: categoryID,
            title: "Rolled back",
            iconName: "folder",
            colorHex: "1677FF"
        )
        _ = try overlay.createTask(
            id: taskID,
            title: "Rolled back",
            parentID: nil,
            categoryID: categoryID,
            notes: "",
            estimatedMinutes: nil,
            dueAt: nil,
            iconName: "checkmark.circle",
            colorHex: "1677FF"
        )
        _ = try overlay.createChecklistItem(
            id: checklistID,
            taskID: taskID,
            title: "Rolled back",
            isCompleted: false,
            iconName: "checkmark.circle",
            colorHex: "1677FF"
        )
        let failing = coordinator(
            container: context.container,
            checkpoint: { checkpoint in
                if checkpoint == .operationApplied(index: 1) {
                    throw InjectedFailure.expected
                }
            }
        )

        #expect(throws: InjectedFailure.expected) {
            try failing.apply(
                AITaskAtomicMutationPlan(
                    baseline: baseline,
                    operations: overlay.operations
                )
            )
        }

        let fresh = ModelContext(context.container)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskCategory>())
                .contains { $0.id == categoryID } == false
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .contains { $0.id == taskID } == false
        )
        #expect(
            try fresh.fetch(FetchDescriptor<ChecklistItem>())
                .contains { $0.id == checklistID } == false
        )
        #expect(
            try fresh.fetch(FetchDescriptor<ChecklistItemVisual>())
                .contains { $0.checklistItemID == checklistID } == false
        )
    }

    @Test
    func targetedChecklistUpdateAndDeleteDoNotRotateUnrelatedRevisions() throws {
        let context = try makeTestContext()
        let fixture = try seedWorkspace(in: context)
        let command = coordinator(container: context.container)
        let baseline = try command.captureBaseline()
        let untouchedItemRevision = try #require(
            baseline.workspace.checklistItemMutationIDs[
                fixture.untouchedChecklistID
            ]
        )
        let untouchedVisualRevision = try #require(
            baseline.workspace.checklistVisualMutationIDsByItemID[
                fixture.untouchedChecklistID
            ]
        )
        var overlay = AITaskWorkspaceOverlay(snapshot: baseline.snapshot)
        _ = try overlay.updateChecklistItem(
            id: fixture.updatedChecklistID,
            title: "Only this item changes",
            isCompleted: true,
            iconName: "star",
            colorHex: "FF9500"
        )
        _ = try overlay.deleteChecklistItem(id: fixture.deletedChecklistID)

        _ = try command.apply(
            AITaskAtomicMutationPlan(
                baseline: baseline,
                operations: overlay.operations
            )
        )

        let after = try command.captureBaseline()
        #expect(
            after.workspace.checklistItemMutationIDs[
                fixture.untouchedChecklistID
            ] == untouchedItemRevision
        )
        #expect(
            after.workspace.checklistVisualMutationIDsByItemID[
                fixture.untouchedChecklistID
            ] == untouchedVisualRevision
        )
        #expect(
            after.workspace.checklistItemMutationIDs[
                fixture.updatedChecklistID
            ] != baseline.workspace.checklistItemMutationIDs[
                fixture.updatedChecklistID
            ]
        )
        #expect(
            after.workspace.checklistVisualMutationIDsByItemID[
                fixture.updatedChecklistID
            ] != baseline.workspace.checklistVisualMutationIDsByItemID[
                fixture.updatedChecklistID
            ]
        )
        #expect(
            after.workspace.checklistItemMutationIDs[
                fixture.deletedChecklistID
            ] == nil
        )
        #expect(
            after.workspace.checklistVisualMutationIDsByItemID[
                fixture.deletedChecklistID
            ] == nil
        )
    }

    @Test
    func replayPreflightRejectsDepthSevenBeforeAnyWrite() throws {
        let context = try makeTestContext()
        let fixture = try seedWorkspace(in: context)
        var checkpoints: [AITaskAtomicMutationCheckpoint] = []
        let command = coordinator(
            container: context.container,
            checkpoint: { checkpoints.append($0) }
        )
        let baseline = try command.captureBaseline()
        var operations: [AITaskWorkspaceOperation] = []
        var parentID = fixture.rootTaskID
        var path = "Root"
        var proposedIDs: [UUID] = []

        for depth in 1 ... 7 {
            let taskID = UUID()
            proposedIDs.append(taskID)
            path += " / Depth \(depth)"
            operations.append(
                .createTask(
                    AITaskWorkspaceTask(
                        id: taskID,
                        title: "Depth \(depth)",
                        parentID: parentID,
                        categoryID: nil,
                        path: path,
                        notes: "",
                        estimatedMinutes: nil,
                        dueAt: nil,
                        iconName: "checkmark.circle",
                        colorHex: "1677FF",
                        sortOrder: 10,
                        isArchived: false
                    )
                )
            )
            parentID = taskID
        }

        #expect(throws: AITaskWorkspaceOverlayError.depthExceeded) {
            try command.apply(
                AITaskAtomicMutationPlan(
                    baseline: baseline,
                    operations: operations
                )
            )
        }
        #expect(checkpoints.isEmpty)

        let fresh = ModelContext(context.container)
        let persistedIDs = try Set(
            fresh.fetch(FetchDescriptor<TaskNode>()).map(\.id)
        )
        #expect(proposedIDs.allSatisfy { persistedIDs.contains($0) == false })
    }
}

private extension StoreScopedAITaskAtomicMutationCoordinatorTests {
    enum InjectedFailure: Error {
        case expected
    }

    struct Fixture {
        let workCategoryID: UUID
        let obsoleteCategoryID: UUID
        let rootTaskID: UUID
        let archivedTaskID: UUID
        let updatedChecklistID: UUID
        let deletedChecklistID: UUID
        let untouchedChecklistID: UUID
    }

    func seedWorkspace(in context: ModelContext) throws -> Fixture {
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        )
        let work = try repository.createCategory(
            title: "Work",
            colorHex: "1677FF",
            iconName: "briefcase",
            includesInForecast: true
        )
        let obsolete = try repository.createCategory(
            title: "Obsolete",
            colorHex: "8E8E93",
            iconName: "archivebox",
            includesInForecast: true
        )
        let root = try repository.createTask(
            title: "Root",
            parentID: nil,
            categoryID: work.id,
            colorHex: "1677FF",
            iconName: "briefcase"
        )
        let archiveTarget = try repository.createTask(
            title: "Archive target",
            parentID: nil,
            categoryID: obsolete.id,
            colorHex: "8E8E93",
            iconName: "archivebox"
        )
        try ChecklistDraftService().save(
            drafts: [
                ChecklistEditorDraft(
                    title: "Update me",
                    iconName: "pencil",
                    colorHex: "5E5CE6"
                ),
                ChecklistEditorDraft(
                    title: "Delete me",
                    iconName: "trash",
                    colorHex: "FF3B30"
                ),
                ChecklistEditorDraft(
                    title: "Untouched",
                    iconName: "lock",
                    colorHex: "8E8E93"
                ),
            ],
            taskID: root.id,
            context: context,
            deviceID: "seed"
        )
        let items = try context.fetch(FetchDescriptor<ChecklistItem>())
            .visibleDeduplicatedByID()
        let updated = try #require(items.first { $0.title == "Update me" })
        let deleted = try #require(items.first { $0.title == "Delete me" })
        let untouched = try #require(items.first { $0.title == "Untouched" })
        return Fixture(
            workCategoryID: work.id,
            obsoleteCategoryID: obsolete.id,
            rootTaskID: root.id,
            archivedTaskID: archiveTarget.id,
            updatedChecklistID: updated.id,
            deletedChecklistID: deleted.id,
            untouchedChecklistID: untouched.id
        )
    }

    func coordinator(
        container: ModelContainer,
        checkpoint: @escaping (AITaskAtomicMutationCheckpoint) throws -> Void = {
            _ in
        }
    ) -> StoreScopedAITaskAtomicMutationCoordinator {
        StoreScopedAITaskAtomicMutationCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "ai-test",
            nowProvider: { Date(timeIntervalSinceReferenceDate: 1000) },
            didReachCheckpoint: checkpoint
        )
    }
}
