import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct CoreAITaskWorkspaceTests {
    @Test
    func captureIsCompleteDeterministicAndKeepsMutationBaselinesLocal() throws {
        let category = TaskCategory(
            title: "Reading",
            deviceID: "private-device",
            colorHex: "5E5CE6",
            iconName: "book",
            sortOrder: 10
        )
        category.id = Self.id(1)
        category.clientMutationID = Self.id(10001)

        var tasks: [TaskNode] = []
        var checklistItems: [ChecklistItem] = []
        var checklistVisuals: [ChecklistItemVisual] = []
        var parentID: UUID?
        for index in 1 ... 80 {
            let task = TaskNode(
                title: "Level \(index)",
                parentID: parentID,
                deviceID: "private-device",
                colorHex: "1677FF",
                iconName: "checkmark.circle",
                sortOrder: Double(index * 10)
            )
            task.id = Self.id(100 + index)
            task.clientMutationID = Self.id(20000 + index)
            task.notes = index == 1 ? "Root notes" : ""
            tasks.append(task)
            parentID = task.id

            let item = ChecklistItem(
                taskID: task.id,
                title: "Check \(index)",
                sortOrder: Double(index * 10),
                deviceID: "private-device"
            )
            item.id = Self.id(1000 + index)
            item.clientMutationID = Self.id(30000 + index)
            checklistItems.append(item)

            let visual = ChecklistItemVisual(
                checklistItemID: item.id,
                iconName: "checkmark.circle",
                colorHex: "1677FF",
                deviceID: "private-device"
            )
            visual.id = Self.id(2000 + index)
            visual.clientMutationID = Self.id(40000 + index)
            checklistVisuals.append(visual)
        }
        let assignment = TaskCategoryAssignment(
            taskID: tasks[0].id,
            categoryID: category.id,
            deviceID: "private-device"
        )
        assignment.id = Self.id(3000)
        assignment.clientMutationID = Self.id(50000)

        let forward = AITaskWorkspaceCapture(
            taskCategories: [category],
            tasks: tasks,
            taskCategoryAssignments: [assignment],
            checklistItems: checklistItems,
            checklistVisuals: checklistVisuals
        )
        let reversed = AITaskWorkspaceCapture(
            taskCategories: [category],
            tasks: Array(tasks.reversed()),
            taskCategoryAssignments: [assignment],
            checklistItems: Array(checklistItems.reversed()),
            checklistVisuals: Array(checklistVisuals.reversed())
        )

        #expect(forward.snapshot == reversed.snapshot)
        #expect(
            forward.snapshot.contextFingerprint ==
                reversed.snapshot.contextFingerprint
        )
        #expect(forward.snapshot.contextFingerprint.count == 64)
        #expect(forward.snapshot.tasks.count == 80)
        #expect(forward.snapshot.checklistItems.count == 80)
        #expect(forward.snapshot.tasks.first?.categoryID == category.id)
        let deepest = try #require(
            forward.snapshot.tasks.first { $0.id == tasks.last?.id }
        )
        #expect(deepest.path.components(separatedBy: " / ").count == 80)
        #expect(deepest.path.hasPrefix("Level 1 / Level 2"))
        #expect(deepest.path.hasSuffix("Level 79 / Level 80"))
        #expect(deepest.path.contains("…") == false)

        #expect(
            forward.baselines.categoryMutationIDs[category.id] ==
                category.clientMutationID
        )
        #expect(
            forward.baselines.taskMutationIDs[tasks[79].id] ==
                tasks[79].clientMutationID
        )
        #expect(
            forward.baselines.checklistItemMutationIDs[checklistItems[79].id] ==
                checklistItems[79].clientMutationID
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(forward.snapshot)
        let reversedEncoded = try encoder.encode(reversed.snapshot)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(encoded == reversedEncoded)
        #expect(
            json.contains(
                #""contextFingerprint":"\#(forward.snapshot.contextFingerprint)""#
            )
        )
        #expect(json.contains("private-device") == false)
        #expect(json.contains(category.clientMutationID.uuidString) == false)
        #expect(json.contains(tasks[79].clientMutationID.uuidString) == false)

        var changedTasks = forward.snapshot.tasks
        changedTasks[0].notes += " changed"
        let changedSnapshot = AITaskWorkspaceSnapshot(
            categories: forward.snapshot.categories,
            tasks: changedTasks,
            checklistItems: forward.snapshot.checklistItems
        )
        #expect(
            changedSnapshot.contextFingerprint !=
                forward.snapshot.contextFingerprint
        )
    }

    @Test
    func categoryResolutionReusesOneStableIdentityAndRejectsAmbiguity() throws {
        let existingID = Self.id(1)
        var overlay = AITaskWorkspaceOverlay(
            snapshot: AITaskWorkspaceSnapshot(
                categories: [
                    Self.category(id: existingID, title: "a"),
                ],
                tasks: [],
                checklistItems: []
            )
        )

        let reused = try overlay.useExistingCategory(named: " A ")

        #expect(reused.id == existingID)
        #expect(overlay.snapshot.categories.count == 1)
        #expect(overlay.operations == [.useExistingCategory(categoryID: existingID)])
        #expect(throws: AITaskWorkspaceOverlayError.categoryAlreadyExists(existingID)) {
            try overlay.createCategory(
                id: Self.id(2),
                title: "Ａ",
                iconName: "square.grid.2x2",
                colorHex: "1677FF"
            )
        }

        let duplicateIDs = [Self.id(11), Self.id(12)]
        let renamedID = Self.id(13)
        var ambiguous = AITaskWorkspaceOverlay(
            snapshot: AITaskWorkspaceSnapshot(
                categories: [
                    Self.category(id: duplicateIDs[1], title: "a"),
                    Self.category(id: duplicateIDs[0], title: "A"),
                    Self.category(id: renamedID, title: "Work"),
                ],
                tasks: [],
                checklistItems: []
            )
        )
        #expect(
            throws: AITaskWorkspaceOverlayError.ambiguousCategoryName(
                categoryIDs: duplicateIDs
            )
        ) {
            try ambiguous.useExistingCategory(named: "a")
        }

        let updated = try ambiguous.updateCategory(
            id: duplicateIDs[0],
            title: "A",
            iconName: "briefcase",
            colorHex: "FF9500",
            includesInForecast: false
        )
        #expect(updated.title == "A")
        #expect(updated.colorHex == "FF9500")
        #expect(updated.includesInForecast == false)

        #expect(
            throws: AITaskWorkspaceOverlayError.ambiguousCategoryName(
                categoryIDs: duplicateIDs
            )
        ) {
            try ambiguous.updateCategory(
                id: renamedID,
                title: "Ａ",
                iconName: "square.grid.2x2",
                colorHex: "1677FF",
                includesInForecast: true
            )
        }
    }

    @Test
    func captureIncludesQuantityGoalAndDailyRecurrenceWithoutLocalRevisions() throws {
        let task = TaskNode(
            title: "Daily reading",
            parentID: nil,
            deviceID: "private-device",
            colorHex: "16A34A",
            iconName: "book",
            sortOrder: 10
        )
        task.id = Self.id(90)
        let goal = TaskQuantityGoal(
            taskID: task.id,
            targetAmount: 50,
            unitLabel: "pages",
            deviceID: "private-device"
        )
        goal.clientMutationID = Self.id(9001)
        let recurrence = TaskRecurrenceRule(
            templateTaskID: task.id,
            startDayKey: "2026-07-26",
            timeZoneIdentifier: "Asia/Singapore",
            deviceID: "private-device"
        )
        recurrence.clientMutationID = Self.id(9002)

        let capture = AITaskWorkspaceCapture(
            taskCategories: [],
            tasks: [task],
            taskCategoryAssignments: [],
            checklistItems: [],
            checklistVisuals: [],
            quantityGoals: [goal],
            recurrenceRules: [recurrence]
        )

        let capturedTask = try #require(capture.snapshot.tasks.first)
        #expect(capturedTask.quantityGoal?.targetAmount == 50)
        #expect(capturedTask.quantityGoal?.unitLabel == "pages")
        #expect(capturedTask.dailyRecurrence?.isEnabled == true)
        #expect(
            capturedTask.dailyRecurrence?.timeZoneIdentifier ==
                "Asia/Singapore"
        )

        let data = try JSONEncoder().encode(capture.snapshot)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""quantityGoal""#))
        #expect(json.contains(#""dailyRecurrence""#))
        #expect(json.contains(goal.clientMutationID.uuidString) == false)
        #expect(json.contains(recurrence.clientMutationID.uuidString) == false)
        #expect(json.contains("private-device") == false)
    }

    @Test
    func overlayCRUDIsImmediatelyReadableAndTaskDeleteArchives() throws {
        let categoryID = Self.id(1)
        let rootID = Self.id(10)
        let childID = Self.id(11)
        let checklistID = Self.id(20)
        var overlay = AITaskWorkspaceOverlay(
            snapshot: AITaskWorkspaceSnapshot(
                categories: [
                    Self.category(id: categoryID, title: "Work"),
                ],
                tasks: [
                    Self.task(
                        id: rootID,
                        title: "Root",
                        categoryID: categoryID
                    ),
                    Self.task(
                        id: childID,
                        title: "Child",
                        parentID: rootID
                    ),
                ],
                checklistItems: [
                    Self.checklist(
                        id: checklistID,
                        taskID: childID,
                        title: "First"
                    ),
                ]
            )
        )

        let newCategoryID = Self.id(2)
        _ = try overlay.createCategory(
            id: newCategoryID,
            title: "Personal",
            iconName: "person",
            colorHex: "34C759"
        )
        _ = try overlay.updateCategory(
            id: newCategoryID,
            title: "Personal Admin",
            iconName: "person",
            colorHex: "34C759",
            includesInForecast: false
        )
        #expect(overlay.category(id: newCategoryID)?.title == "Personal Admin")

        _ = try overlay.updateTask(
            id: rootID,
            title: "Renamed Root",
            parentID: nil,
            categoryID: categoryID,
            notes: "Updated",
            estimatedMinutes: 25,
            dueAt: nil,
            iconName: "target",
            colorHex: "FF9500"
        )
        #expect(overlay.task(id: childID)?.path == "Renamed Root / Child")

        let newTaskID = Self.id(12)
        _ = try overlay.createTask(
            id: newTaskID,
            title: "New Child",
            parentID: rootID,
            categoryID: nil,
            notes: "",
            estimatedMinutes: nil,
            dueAt: nil,
            iconName: "checkmark.circle",
            colorHex: "1677FF"
        )
        #expect(overlay.task(id: newTaskID)?.path == "Renamed Root / New Child")

        let newChecklistID = Self.id(21)
        _ = try overlay.createChecklistItem(
            id: newChecklistID,
            taskID: newTaskID,
            title: "Draft",
            isCompleted: false,
            iconName: "pencil",
            colorHex: "5E5CE6"
        )
        _ = try overlay.updateChecklistItem(
            id: newChecklistID,
            title: "Review",
            isCompleted: true,
            iconName: "checkmark.circle",
            colorHex: "34C759"
        )
        #expect(overlay.checklistItem(id: newChecklistID)?.title == "Review")
        #expect(overlay.checklistItem(id: newChecklistID)?.isCompleted == true)
        _ = try overlay.deleteChecklistItem(id: newChecklistID)
        #expect(overlay.checklistItem(id: newChecklistID) == nil)

        _ = try overlay.deleteCategory(id: categoryID)
        #expect(overlay.category(id: categoryID) == nil)
        #expect(overlay.task(id: rootID)?.categoryID == nil)

        let archived = try overlay.deleteTask(id: rootID)
        #expect(archived.isArchived)
        #expect(overlay.task(id: rootID)?.isArchived == true)
        #expect(overlay.task(id: childID) != nil)
        #expect(
            overlay.operations.contains {
                guard case let .archiveTask(before, after, affectedDescendantIDs) = $0
                else { return false }
                return before.id == rootID &&
                    after.isArchived &&
                    affectedDescendantIDs == [childID, newTaskID]
            }
        )
    }

    @Test
    func overlayRejectsOrphansCyclesAndCategoriesOnChildTasks() throws {
        let rootID = Self.id(1)
        let childID = Self.id(2)
        let categoryID = Self.id(3)
        var overlay = AITaskWorkspaceOverlay(
            snapshot: AITaskWorkspaceSnapshot(
                categories: [Self.category(id: categoryID, title: "Work")],
                tasks: [
                    Self.task(id: rootID, title: "Root", categoryID: categoryID),
                    Self.task(id: childID, title: "Child", parentID: rootID),
                ],
                checklistItems: []
            )
        )

        #expect(
            throws: AITaskWorkspaceOverlayError.taskUnavailable(Self.id(99))
        ) {
            try overlay.createTask(
                id: Self.id(4),
                title: "Orphan",
                parentID: Self.id(99),
                categoryID: nil,
                notes: "",
                estimatedMinutes: nil,
                dueAt: nil,
                iconName: "checkmark.circle",
                colorHex: "1677FF"
            )
        }
        #expect(
            throws: AITaskWorkspaceOverlayError.childTaskCannotHaveCategory
        ) {
            try overlay.updateTask(
                id: childID,
                title: "Child",
                parentID: rootID,
                categoryID: categoryID,
                notes: "",
                estimatedMinutes: nil,
                dueAt: nil,
                iconName: "checkmark.circle",
                colorHex: "1677FF"
            )
        }
        #expect(throws: AITaskWorkspaceOverlayError.hierarchyCycle) {
            try overlay.updateTask(
                id: rootID,
                title: "Root",
                parentID: childID,
                categoryID: nil,
                notes: "",
                estimatedMinutes: nil,
                dueAt: nil,
                iconName: "checkmark.circle",
                colorHex: "1677FF"
            )
        }
    }

    @Test
    func overlayAcceptsDepthSixAndRejectsDepthSeven() throws {
        var overlay = AITaskWorkspaceOverlay(
            snapshot: AITaskWorkspaceSnapshot(
                categories: [],
                tasks: [],
                checklistItems: []
            )
        )
        var parentID: UUID?

        for depth in 0 ... 6 {
            let taskID = Self.id(100 + depth)
            _ = try overlay.createTask(
                id: taskID,
                title: "Depth \(depth)",
                parentID: parentID,
                categoryID: nil,
                notes: "",
                estimatedMinutes: nil,
                dueAt: nil,
                iconName: "checkmark.circle",
                colorHex: "1677FF"
            )
            parentID = taskID
        }

        #expect(
            overlay.task(id: Self.id(106))?.path.components(
                separatedBy: " / "
            ).count == 7
        )
        #expect(throws: AITaskWorkspaceOverlayError.depthExceeded) {
            try overlay.createTask(
                id: Self.id(107),
                title: "Depth 7",
                parentID: parentID,
                categoryID: nil,
                notes: "",
                estimatedMinutes: nil,
                dueAt: nil,
                iconName: "checkmark.circle",
                colorHex: "1677FF"
            )
        }
        #expect(overlay.task(id: Self.id(107)) == nil)
    }

    @Test
    func overlaySupportsOneHundredFiftyChecklistItemsOnOneRootTask() throws {
        let categoryID = Self.id(1)
        let taskID = Self.id(1000)
        var overlay = AITaskWorkspaceOverlay(
            snapshot: AITaskWorkspaceSnapshot(
                categories: [Self.category(id: categoryID, title: "Study")],
                tasks: [],
                checklistItems: []
            )
        )

        _ = try overlay.useExistingCategory(named: "Study")
        _ = try overlay.createTask(
            id: taskID,
            title: "Read 150 Chapters",
            parentID: nil,
            categoryID: categoryID,
            notes: "",
            estimatedMinutes: 600,
            dueAt: nil,
            iconName: "book",
            colorHex: "16A34A"
        )
        for index in 1 ... 150 {
            _ = try overlay.createChecklistItem(
                id: Self.id(10000 + index),
                taskID: taskID,
                title: "Chapter \(index)",
                isCompleted: false,
                iconName: "book.pages",
                colorHex: "16A34A"
            )
        }

        #expect(overlay.snapshot.checklistItems.count == 150)
        #expect(overlay.operations.count == 152)
        #expect(overlay.checklistItem(id: Self.id(10150))?.title == "Chapter 150")
    }

    @Test
    func invalidModelToolArgumentsReturnARecoverableToolResult() throws {
        var overlay = AITaskWorkspaceOverlay(
            snapshot: AITaskWorkspaceSnapshot(
                categories: [],
                tasks: [],
                checklistItems: []
            )
        )
        let call = OpenAIChatToolCall(
            id: "create-task-invalid-visual",
            type: "function",
            function: .init(
                name: AITaskWorkspaceToolName.createTask.rawValue,
                arguments: """
                {
                  "title": "Draft release notes",
                  "parentID": null,
                  "categoryID": null,
                  "notes": "",
                  "estimatedMinutes": 90,
                  "dueAt": null,
                  "iconName": "invented.invalid.symbol",
                  "colorHex": "1677FF",
                  "quantityGoal": null,
                  "dailyRecurrence": null
                }
                """
            )
        )

        let result = try LLMTaskWorkspacePlanningService.execute(
            call,
            overlay: &overlay,
            makeID: { Self.id(5000) }
        )
        let data = try #require(result.data(using: .utf8))
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object["ok"] as? Bool == false)
        #expect((object["error"] as? String)?.isEmpty == false)
        #expect(overlay.snapshot.tasks.isEmpty)
        #expect(overlay.operations.isEmpty)
    }
}

private extension CoreAITaskWorkspaceTests {
    static func id(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )!
    }

    static func category(
        id: UUID,
        title: String
    ) -> AITaskWorkspaceCategory {
        AITaskWorkspaceCategory(
            id: id,
            title: title,
            iconName: "square.grid.2x2",
            colorHex: "1677FF",
            includesInForecast: true,
            sortOrder: 10
        )
    }

    static func task(
        id: UUID,
        title: String,
        parentID: UUID? = nil,
        categoryID: UUID? = nil
    ) -> AITaskWorkspaceTask {
        AITaskWorkspaceTask(
            id: id,
            title: title,
            parentID: parentID,
            categoryID: categoryID,
            path: title,
            notes: "",
            estimatedMinutes: nil,
            dueAt: nil,
            iconName: "checkmark.circle",
            colorHex: "1677FF",
            sortOrder: 10,
            isArchived: false
        )
    }

    static func checklist(
        id: UUID,
        taskID: UUID,
        title: String
    ) -> AITaskWorkspaceChecklistItem {
        AITaskWorkspaceChecklistItem(
            id: id,
            taskID: taskID,
            title: title,
            isCompleted: false,
            iconName: "checkmark.circle",
            colorHex: "1677FF",
            sortOrder: 10
        )
    }
}
