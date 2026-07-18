import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskHierarchyPickerTests {
    @Test @MainActor
    func projectionPreservesHierarchyAndMakesCompletedBranchesUnavailable() throws {
        let store = makeTestStore()
        let category = TaskCategory(
            title: "Work",
            deviceID: "test",
            colorHex: "1677FF",
            iconName: "briefcase"
        )
        let completedParent = TaskNode(
            title: "Shipped project",
            parentID: nil,
            deviceID: "test"
        )
        completedParent.status = .completed
        let child = TaskNode(
            title: "Follow-up",
            parentID: completedParent.id,
            deviceID: "test"
        )
        let availableTask = TaskNode(
            title: "Available",
            parentID: nil,
            deviceID: "test",
            sortOrder: 10
        )

        store.taskCategories = [category]
        store.taskCategoryAssignments = [
            TaskCategoryAssignment(
                taskID: completedParent.id,
                categoryID: category.id,
                deviceID: "test"
            )
        ]
        store.tasks = [completedParent, child, availableTask]

        let projection = TaskHierarchyProjection(
            store: store,
            expandedTaskIDs: [completedParent.id],
            searchText: ""
        )
        let workSection = try #require(
            projection.sections.first { $0.categoryID == category.id }
        )
        let completedItem = try #require(
            workSection.items.first { $0.id == completedParent.id }
        )
        let childItem = try #require(
            workSection.items.first { $0.id == child.id }
        )
        let availableItem = try #require(
            projection.sections
                .flatMap(\.items)
                .first { $0.id == availableTask.id }
        )

        #expect(projection.hasVisibleTasks)
        #expect(workSection.items.map(\.id) == [completedParent.id, child.id])
        #expect(completedItem.depth == 0)
        #expect(completedItem.isCompleted)
        #expect(completedItem.isAvailable == false)
        #expect(childItem.depth == 1)
        #expect(childItem.isCompleted == false)
        #expect(childItem.isAvailable == false)
        #expect(childItem.unavailableReason?.contains(completedParent.title) == true)
        #expect(availableItem.isAvailable)
        #expect(availableItem.timerCommand == .start)
    }

    @Test @MainActor
    func searchUsesTheIndexedNotesAndKeepsStandaloneParentIdentity() throws {
        let store = makeTestStore()
        let parent = TaskNode(
            title: "Client",
            parentID: nil,
            deviceID: "test"
        )
        let child = TaskNode(
            title: "Review",
            parentID: parent.id,
            deviceID: "test"
        )
        child.notes = "Needle in the project notes"
        store.tasks = [parent, child]

        let projection = TaskHierarchyProjection(
            store: store,
            expandedTaskIDs: [],
            searchText: "NEEDLE"
        )
        let section = try #require(projection.sections.first)
        let item = try #require(section.items.first)

        #expect(projection.isSearching)
        #expect(projection.sections.count == 1)
        #expect(section.kind == .searchResults)
        #expect(section.items.map(\.id) == [child.id])
        #expect(item.depth == 0)
        #expect(item.identity.parentPath == parent.title)
        #expect(item.identity.fullPath == "\(parent.title) / \(child.title)")
    }

    @Test @MainActor
    func runningProjectionKeepsAHiddenTaskAvailableForStopping() throws {
        let store = makeTestStore()
        let archivedTask = TaskNode(
            title: "Archived but running",
            parentID: nil,
            deviceID: "test"
        )
        archivedTask.status = .archived
        let segment = TimeSegment(
            sessionID: UUID(),
            taskID: archivedTask.id,
            source: .timer,
            deviceID: "test"
        )
        store.tasks = [archivedTask]
        store.activeSegments = [segment]

        let projection = TaskHierarchyProjection(
            store: store,
            expandedTaskIDs: [],
            searchText: ""
        )
        let runningItem = try #require(projection.runningItems.first)

        #expect(projection.hasVisibleTasks == false)
        #expect(projection.sections.isEmpty)
        #expect(projection.runningItems.map(\.id) == [archivedTask.id])
        #expect(runningItem.isRunning)
        #expect(runningItem.isAvailable == false)
        #expect(runningItem.timerCommand == .alreadyRunning)
    }

    @Test
    func todayAndPomodoroUseTheSameHierarchyPickerSurface() throws {
        let home = try sourceText(
            "timetracker/Features/Home/Controls/HomeActionsViews.swift"
        )
        let pomodoro = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroTaskPickerViews.swift"
        )
        let picker = try [
            "timetracker/SharedUI/Components/TaskHierarchyPicker.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerRows.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerBehavior.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
        let projection = try sourceText(
            "timetracker/SharedUI/Components/TaskHierarchyProjection.swift"
        )
        let root = try projectRootURL()

        #expect(home.contains("TaskHierarchyPicker("))
        #expect(home.contains("mode: .timer"))
        #expect(pomodoro.contains("TaskHierarchyPicker("))
        #expect(pomodoro.contains(".singleSelection(selectedTaskID: selectedTaskID)"))
        #expect(home.contains(".searchable(") == false)
        #expect(pomodoro.contains(".searchable(") == false)
        #expect(picker.contains("TaskIdentityRow("))
        #expect(picker.contains("TaskCategorySectionHeader("))
        #expect(picker.contains("store.performTimerPickerSelection(task)"))
        #expect(picker.contains("store.stop(segment: activeSegment)"))
        #expect(projection.contains("store.taskTreeSections(expandedTaskIDs: expandedTaskIDs)"))
        #expect(projection.contains("store.taskSearchResults(matching: query)"))
        #expect(
            FileManager.default.fileExists(
                atPath: root.appending(
                    path: "timetracker/Features/Home/Controls/TaskStartPickerRows.swift"
                ).path
            ) == false
        )
    }
}
