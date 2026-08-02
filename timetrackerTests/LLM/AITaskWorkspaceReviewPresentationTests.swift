import Foundation
import Testing
@testable import timetracker

struct AITaskWorkspaceReviewPresentationTests {
    @Test
    func countsMutationsAndDestructiveChangesAcrossOperationKinds() {
        let category = makeCategory()
        let task = makeTask()
        let checklist = makeChecklist(taskID: task.id)
        let operations: [AITaskWorkspaceOperation] = [
            .useExistingCategory(categoryID: category.id),
            .createTask(task),
            .updateChecklistItem(
                before: checklist,
                after: changed(checklist, title: "After")
            ),
            .archiveTask(
                before: task,
                after: changed(task, isArchived: true),
                affectedDescendantIDs: []
            ),
            .deleteCategory(category: category, affectedRootTaskIDs: []),
        ]

        let presentation = AITaskWorkspaceReviewPresentation(
            operations: operations,
            original: snapshot(category: category, task: task, checklist: checklist),
            resulting: snapshot(category: category, task: task, checklist: checklist)
        )

        #expect(
            presentation.counts == AITaskWorkspaceOperationCounts(
                created: 1,
                updated: 1,
                archived: 1,
                deleted: 1,
                reused: 1
            )
        )
        #expect(presentation.mutationCount == 4)
        #expect(presentation.hasDestructiveOperations)
    }

    @Test
    func quantityGoalRemovalIsDestructiveButRetainingItIsNot() {
        let goal = TaskQuantityGoalDraft(targetAmount: 12, unitLabel: "pages")
        let before = makeTask(quantityGoal: goal)
        let removed = changed(before, quantityGoal: .some(nil))
        let retained = changed(before, title: "Renamed")

        #expect(
            AITaskWorkspaceReviewPresentation(
                operations: [.updateTask(before: before, after: removed)],
                original: snapshot(task: before),
                resulting: snapshot(task: removed)
            ).hasDestructiveOperations
        )
        #expect(
            AITaskWorkspaceReviewPresentation(
                operations: [.updateTask(before: before, after: retained)],
                original: snapshot(task: before),
                resulting: snapshot(task: retained)
            ).hasDestructiveOperations == false
        )
    }

    @Test
    func everyDestructiveOperationKindRequiresConfirmation() {
        let category = makeCategory()
        let task = makeTask()
        let checklist = makeChecklist(taskID: task.id)
        let cases: [(AITaskWorkspaceOperation, Bool)] = [
            (.useExistingCategory(categoryID: category.id), false),
            (.createCategory(category), false),
            (.updateCategory(before: category, after: category), false),
            (.deleteCategory(category: category, affectedRootTaskIDs: []), true),
            (.createTask(task), false),
            (.updateTask(before: task, after: changed(task, title: "After")), false),
            (
                .archiveTask(
                    before: task,
                    after: changed(task, isArchived: true),
                    affectedDescendantIDs: []
                ),
                true
            ),
            (.createChecklistItem(checklist), false),
            (.updateChecklistItem(before: checklist, after: checklist), false),
            (.deleteChecklistItem(checklist), true),
        ]

        for (operation, expected) in cases {
            #expect(operation.isDestructive == expected)
        }
    }

    @Test
    func taskPresentationDisclosesChangedFieldsAndOmitsUnchangedFields() throws {
        let originalCategory = makeCategory(title: "Original")
        let resultingCategory = makeCategory(title: "Result")
        let before = makeTask(
            categoryID: originalCategory.id,
            quantityGoal: TaskQuantityGoalDraft(targetAmount: 10, unitLabel: "pages")
        )
        var after = changed(before, title: "After")
        after.parentID = UUID()
        after.categoryID = resultingCategory.id
        after.path = "Parent / After"
        after.notes = "New notes"
        after.estimatedMinutes = 45
        after.dueAt = Date(timeIntervalSinceReferenceDate: 123_456)
        after.iconName = "star"
        after.colorHex = "FF9500"
        after.quantityGoal = nil
        after.dailyRecurrence = TaskDailyRecurrenceDraft(
            startDayKey: "2026-08-02",
            timeZoneIdentifier: "Asia/Singapore"
        )
        after.sortOrder = 999

        let presentation = AITaskWorkspaceReviewPresentation(
            operations: [.updateTask(before: before, after: after)],
            original: AITaskWorkspaceSnapshot(
                categories: [originalCategory],
                tasks: [before],
                checklistItems: []
            ),
            resulting: AITaskWorkspaceSnapshot(
                categories: [resultingCategory],
                tasks: [after],
                checklistItems: []
            )
        )
        let operation = try #require(presentation.operations.first)

        #expect(
            operation.fieldChanges.map(\.field) == [
                .title,
                .path,
                .category,
                .notes,
                .estimatedTime,
                .dueDate,
                .icon,
                .color,
                .quantityGoal,
                .recurrence,
            ]
        )
        #expect(operation.fieldChanges.contains { $0.field == .forecast } == false)
        #expect(operation.fieldChanges.contains { $0.field == .completion } == false)
    }

    @Test
    func categoryAndChecklistPresentationsDiscloseEveryChangedField() throws {
        let categoryBefore = makeCategory(title: "Before")
        var categoryAfter = categoryBefore
        categoryAfter.title = "After"
        categoryAfter.iconName = "star"
        categoryAfter.colorHex = "FF9500"
        categoryAfter.includesInForecast = false
        categoryAfter.sortOrder = 999

        let task = makeTask()
        let checklistBefore = makeChecklist(taskID: task.id)
        var checklistAfter = checklistBefore
        checklistAfter.title = "After"
        checklistAfter.isCompleted = true
        checklistAfter.iconName = "checkmark"
        checklistAfter.colorHex = "34C759"
        checklistAfter.sortOrder = 999

        let presentation = AITaskWorkspaceReviewPresentation(
            operations: [
                .updateCategory(before: categoryBefore, after: categoryAfter),
                .updateChecklistItem(before: checklistBefore, after: checklistAfter),
            ],
            original: snapshot(
                category: categoryBefore,
                task: task,
                checklist: checklistBefore
            ),
            resulting: snapshot(
                category: categoryAfter,
                task: task,
                checklist: checklistAfter
            )
        )

        #expect(
            try #require(presentation.operations.first).fieldChanges.map(\.field) == [
                .title,
                .icon,
                .color,
                .forecast,
            ]
        )
        #expect(
            try #require(presentation.operations.last).fieldChanges.map(\.field) == [
                .title,
                .completion,
                .icon,
                .color,
            ]
        )
    }

    @Test
    func duplicateOperationsReceiveDistinctStableOccurrences() {
        let task = makeTask()
        let operation = AITaskWorkspaceOperation.createTask(task)
        let presentation = AITaskWorkspaceReviewPresentation(
            operations: [operation, operation],
            original: snapshot(),
            resulting: snapshot(task: task)
        )

        #expect(presentation.operations.map(\.accessibilityIndex) == [0, 1])
        #expect(presentation.operations.map(\.id.occurrence) == [0, 1])
        #expect(presentation.operations[0].id.seed == presentation.operations[1].id.seed)
        #expect(presentation.operations[0].id != presentation.operations[1].id)
    }

    private func makeCategory(
        id: UUID = UUID(),
        title: String = "Category"
    ) -> AITaskWorkspaceCategory {
        AITaskWorkspaceCategory(
            id: id,
            title: title,
            iconName: "folder",
            colorHex: "007AFF",
            includesInForecast: true,
            sortOrder: 0
        )
    }

    private func makeTask(
        id: UUID = UUID(),
        categoryID: UUID? = nil,
        quantityGoal: TaskQuantityGoalDraft? = nil
    ) -> AITaskWorkspaceTask {
        AITaskWorkspaceTask(
            id: id,
            title: "Before",
            parentID: nil,
            categoryID: categoryID,
            path: "Before",
            notes: "",
            estimatedMinutes: nil,
            dueAt: nil,
            iconName: "circle",
            colorHex: "007AFF",
            sortOrder: 0,
            isArchived: false,
            quantityGoal: quantityGoal,
            dailyRecurrence: nil
        )
    }

    private func makeChecklist(
        id: UUID = UUID(),
        taskID: UUID
    ) -> AITaskWorkspaceChecklistItem {
        AITaskWorkspaceChecklistItem(
            id: id,
            taskID: taskID,
            title: "Before",
            isCompleted: false,
            iconName: "circle",
            colorHex: "007AFF",
            sortOrder: 0
        )
    }

    private func changed(
        _ task: AITaskWorkspaceTask,
        title: String? = nil,
        isArchived: Bool? = nil,
        quantityGoal: TaskQuantityGoalDraft?? = nil
    ) -> AITaskWorkspaceTask {
        var result = task
        if let title {
            result.title = title; result.path = title
        }
        if let isArchived {
            result.isArchived = isArchived
        }
        if let quantityGoal {
            result.quantityGoal = quantityGoal
        }
        return result
    }

    private func changed(
        _ item: AITaskWorkspaceChecklistItem,
        title: String
    ) -> AITaskWorkspaceChecklistItem {
        var result = item
        result.title = title
        return result
    }

    private func snapshot(
        category: AITaskWorkspaceCategory? = nil,
        task: AITaskWorkspaceTask? = nil,
        checklist: AITaskWorkspaceChecklistItem? = nil
    ) -> AITaskWorkspaceSnapshot {
        AITaskWorkspaceSnapshot(
            categories: category.map { [$0] } ?? [],
            tasks: task.map { [$0] } ?? [],
            checklistItems: checklist.map { [$0] } ?? []
        )
    }
}
