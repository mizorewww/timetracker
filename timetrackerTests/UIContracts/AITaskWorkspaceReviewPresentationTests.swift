import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct AITaskWorkspaceReviewPresentationTests {
    @Test
    func categoryUpdateProjectsEveryEditableFieldChange() throws {
        let categoryID = Self.id(1)
        let before = Self.category(
            id: categoryID,
            title: "Work",
            iconName: "briefcase",
            colorHex: "1677FF",
            includesInForecast: true
        )
        let after = Self.category(
            id: categoryID,
            title: "Personal",
            iconName: "person",
            colorHex: "34C759",
            includesInForecast: false
        )

        let operation = try #require(
            Self.presentation(
                operations: [.updateCategory(before: before, after: after)],
                original: Self.snapshot(categories: [before]),
                resulting: Self.snapshot(categories: [after])
            ).operations.first
        )

        #expect(
            operation.fieldChanges.map(\.field) == [
                .title,
                .icon,
                .color,
                .forecast,
            ]
        )
        #expect(operation.fieldChanges[0].before == .text("Work"))
        #expect(operation.fieldChanges[0].after == .text("Personal"))
        #expect(operation.fieldChanges[1].before == .icon("briefcase"))
        #expect(operation.fieldChanges[1].after == .icon("person"))
        #expect(operation.fieldChanges[2].before == .color("1677FF"))
        #expect(operation.fieldChanges[2].after == .color("34C759"))
        #expect(operation.fieldChanges[3].before == .boolean(true))
        #expect(operation.fieldChanges[3].after == .boolean(false))
    }

    @Test
    func taskUpdateProjectsEveryEditableFieldWithoutExposingRelationshipIDs()
        throws
    {
        let taskID = Self.id(10)
        let oldParentID = Self.id(11)
        let newParentID = Self.id(12)
        let workID = Self.id(20)
        let personalID = Self.id(21)
        let oldDueDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let oldRecurrence = TaskDailyRecurrenceDraft(
            isEnabled: true,
            startDayKey: "2026-07-20",
            timeZoneIdentifier: "Asia/Singapore"
        )
        let newRecurrence = TaskDailyRecurrenceDraft(
            isEnabled: false,
            startDayKey: "2026-07-21",
            timeZoneIdentifier: "Europe/London"
        )
        let before = Self.task(
            id: taskID,
            title: "Draft",
            parentID: oldParentID,
            categoryID: workID,
            path: "Old Parent / Draft",
            notes: "Short note",
            estimatedMinutes: 25,
            dueAt: oldDueDate,
            iconName: "doc",
            colorHex: "1677FF",
            quantityGoal: TaskQuantityGoalDraft(
                targetAmount: 10,
                unitLabel: "pages"
            ),
            dailyRecurrence: oldRecurrence
        )
        let after = Self.task(
            id: taskID,
            title: "Final",
            parentID: newParentID,
            categoryID: personalID,
            path: "New Parent / Final",
            notes: "A much longer note that must remain fully reviewable.",
            estimatedMinutes: 90,
            dueAt: newDueDate,
            iconName: "checkmark.circle",
            colorHex: "34C759",
            quantityGoal: TaskQuantityGoalDraft(
                targetAmount: 50,
                unitLabel: "pages"
            ),
            dailyRecurrence: newRecurrence
        )
        let original = Self.snapshot(
            categories: [Self.category(id: workID, title: "Work")],
            tasks: [before]
        )
        let resulting = Self.snapshot(
            categories: [Self.category(id: personalID, title: "Personal")],
            tasks: [after]
        )

        let operation = try #require(
            Self.presentation(
                operations: [.updateTask(before: before, after: after)],
                original: original,
                resulting: resulting
            ).operations.first
        )

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
        #expect(operation.fieldChanges[1].before == .text(before.path))
        #expect(operation.fieldChanges[1].after == .text(after.path))
        #expect(operation.fieldChanges[2].before == .optionalText("Work"))
        #expect(operation.fieldChanges[2].after == .optionalText("Personal"))
        #expect(operation.fieldChanges[4].before == .minutes(25))
        #expect(operation.fieldChanges[4].after == .minutes(90))
        #expect(operation.fieldChanges[5].before == .date(oldDueDate))
        #expect(operation.fieldChanges[5].after == .date(newDueDate))
        #expect(
            operation.fieldChanges[8].before ==
                .quantityGoal(before.quantityGoal)
        )
        #expect(
            operation.fieldChanges[8].after ==
                .quantityGoal(after.quantityGoal)
        )
        #expect(
            operation.fieldChanges[9].before ==
                .recurrence(oldRecurrence)
        )
        #expect(
            operation.fieldChanges[9].after ==
                .recurrence(newRecurrence)
        )

        let visibleText = ([operation.title, operation.context] +
            operation.fieldChanges.flatMap {
                [$0.before.localizedText, $0.after.localizedText]
            }).joined(separator: "\n")
        #expect(visibleText.contains(taskID.uuidString) == false)
        #expect(visibleText.contains(oldParentID.uuidString) == false)
        #expect(visibleText.contains(newParentID.uuidString) == false)
        #expect(visibleText.contains(workID.uuidString) == false)
        #expect(visibleText.contains(personalID.uuidString) == false)
        #expect(visibleText.contains(before.path))
        #expect(visibleText.contains(after.path))
        #expect(operation.accessibilityLabel.contains("Final"))
        #expect(operation.accessibilityLabel.contains("Before"))
        #expect(operation.accessibilityLabel.contains("After"))
        #expect(operation.accessibilityLabel.contains(before.path))
        #expect(operation.accessibilityLabel.contains(after.path))
        #expect(operation.accessibilityLabel.contains(taskID.uuidString) == false)
    }

    @Test
    func checklistUpdateProjectsCompletionAndVisualChangesWithTaskTitlePath()
        throws
    {
        let parentID = Self.id(29)
        let taskID = Self.id(30)
        let checklistID = Self.id(31)
        let parent = Self.task(id: parentID, title: "Study")
        let task = Self.task(
            id: taskID,
            title: "Read",
            parentID: parentID,
            path: "Study / Read"
        )
        let before = Self.checklist(
            id: checklistID,
            taskID: taskID,
            title: "Chapter one",
            isCompleted: false,
            iconName: "book",
            colorHex: "1677FF"
        )
        let after = Self.checklist(
            id: checklistID,
            taskID: taskID,
            title: "Chapter two",
            isCompleted: true,
            iconName: "book.pages",
            colorHex: "34C759"
        )
        let snapshot = Self.snapshot(
            tasks: [parent, task],
            checklistItems: [after]
        )

        let operation = try #require(
            Self.presentation(
                operations: [
                    .updateChecklistItem(before: before, after: after),
                ],
                original: snapshot,
                resulting: snapshot
            ).operations.first
        )

        #expect(
            operation.fieldChanges.map(\.field) == [
                .title,
                .completion,
                .icon,
                .color,
            ]
        )
        #expect(operation.fieldChanges[1].before == .boolean(false))
        #expect(operation.fieldChanges[1].after == .boolean(true))
        #expect(operation.context.contains(task.path))
        #expect(operation.context.contains(taskID.uuidString) == false)
        #expect(operation.context.contains(checklistID.uuidString) == false)
    }

    @Test
    func operationIdentityIsStableAndUniqueForRepeatedReuse() {
        let categoryID = Self.id(40)
        let category = Self.category(id: categoryID, title: "Study")
        let snapshot = Self.snapshot(categories: [category])
        let operations: [AITaskWorkspaceOperation] = [
            .useExistingCategory(categoryID: categoryID),
            .useExistingCategory(categoryID: categoryID),
        ]

        let first = Self.presentation(
            operations: operations,
            original: snapshot,
            resulting: snapshot
        )
        let second = Self.presentation(
            operations: operations,
            original: snapshot,
            resulting: snapshot
        )

        #expect(first.operations.map(\.id) == second.operations.map(\.id))
        #expect(Set(first.operations.map(\.id)).count == 2)
        #expect(first.operations.allSatisfy { $0.title == "Study" })
        #expect(
            first.operations.allSatisfy {
                $0.title.contains(categoryID.uuidString) == false &&
                    $0.context.contains(categoryID.uuidString) == false
            }
        )
    }
}

private extension AITaskWorkspaceReviewPresentationTests {
    static func presentation(
        operations: [AITaskWorkspaceOperation],
        original: AITaskWorkspaceSnapshot,
        resulting: AITaskWorkspaceSnapshot
    ) -> AITaskWorkspaceReviewPresentation {
        AITaskWorkspaceReviewPresentation(
            operations: operations,
            original: original,
            resulting: resulting
        )
    }

    static func snapshot(
        categories: [AITaskWorkspaceCategory] = [],
        tasks: [AITaskWorkspaceTask] = [],
        checklistItems: [AITaskWorkspaceChecklistItem] = []
    ) -> AITaskWorkspaceSnapshot {
        AITaskWorkspaceSnapshot(
            categories: categories,
            tasks: tasks,
            checklistItems: checklistItems
        )
    }

    static func category(
        id: UUID,
        title: String,
        iconName: String = "square.grid.2x2",
        colorHex: String = "1677FF",
        includesInForecast: Bool = true
    ) -> AITaskWorkspaceCategory {
        AITaskWorkspaceCategory(
            id: id,
            title: title,
            iconName: iconName,
            colorHex: colorHex,
            includesInForecast: includesInForecast,
            sortOrder: 10
        )
    }

    static func task(
        id: UUID,
        title: String,
        parentID: UUID? = nil,
        categoryID: UUID? = nil,
        path: String? = nil,
        notes: String = "",
        estimatedMinutes: Int? = nil,
        dueAt: Date? = nil,
        iconName: String = "checkmark.circle",
        colorHex: String = "1677FF",
        quantityGoal: TaskQuantityGoalDraft? = nil,
        dailyRecurrence: TaskDailyRecurrenceDraft? = nil
    ) -> AITaskWorkspaceTask {
        AITaskWorkspaceTask(
            id: id,
            title: title,
            parentID: parentID,
            categoryID: categoryID,
            path: path ?? title,
            notes: notes,
            estimatedMinutes: estimatedMinutes,
            dueAt: dueAt,
            iconName: iconName,
            colorHex: colorHex,
            sortOrder: 10,
            isArchived: false,
            quantityGoal: quantityGoal,
            dailyRecurrence: dailyRecurrence
        )
    }

    static func checklist(
        id: UUID,
        taskID: UUID,
        title: String,
        isCompleted: Bool,
        iconName: String,
        colorHex: String
    ) -> AITaskWorkspaceChecklistItem {
        AITaskWorkspaceChecklistItem(
            id: id,
            taskID: taskID,
            title: title,
            isCompleted: isCompleted,
            iconName: iconName,
            colorHex: colorHex,
            sortOrder: 10
        )
    }

    static func id(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )!
    }
}
