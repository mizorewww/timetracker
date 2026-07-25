import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskHierarchyPickerTests {
    @Test @MainActor
    func selectionContextsPreservePomodoroDefaultsAndSeparateInboxSemantics() {
        let selectedTaskID = UUID()

        #expect(
            TaskHierarchyPickerMode.singleSelection(
                selectedTaskID: selectedTaskID
            ) == .singleSelection(
                selectedTaskID: selectedTaskID,
                context: .pomodoro
            )
        )
        #expect(
            TaskHierarchyPickerMode.multipleSelection(
                selectedTaskIDs: [selectedTaskID]
            ) == .multipleSelection(
                selectedTaskIDs: [selectedTaskID],
                context: .todayHeatmap,
                maximumSelectionCount: nil
            )
        )
        #expect(
            TaskHierarchyPickerSelectionContext.pomodoro
                .accessibilityIdentifier == "pomodoro.taskPicker"
        )
        #expect(
            TaskHierarchyPickerSelectionContext.inboxChildTaskParent
                .accessibilityIdentifier == "inbox.childTask.parentPicker"
        )
        #expect(
            TaskHierarchyPickerSelectionContext.inboxChecklistTarget
                .accessibilityIdentifier == "inbox.checklistItem.taskPicker"
        )
        #expect(
            TaskHierarchyPickerSelectionContext.todayHeatmap
                .accessibilityIdentifier == "settings.todayHeatmap.taskPicker"
        )
        #expect(
            TaskHierarchyPickerSelectionContext.pomodoro.navigationTitle !=
                TaskHierarchyPickerSelectionContext.inboxChildTaskParent.navigationTitle
        )
        #expect(
            TaskHierarchyPickerSelectionContext.inboxChildTaskParent.navigationTitle !=
                TaskHierarchyPickerSelectionContext.inboxChecklistTarget.navigationTitle
        )
    }

    @Test @MainActor
    func projectionTreatsLegacyCompletedBranchesAsOrdinaryTasks() throws {
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
        completedParent.statusRaw = LegacyTaskStatusRaw.completed
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
            ),
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
        #expect(completedItem.isAvailable)
        #expect(completedItem.unavailableReason == nil)
        #expect(completedItem.timerCommand == .start)
        #expect(childItem.depth == 1)
        #expect(childItem.isAvailable)
        #expect(childItem.unavailableReason == nil)
        #expect(childItem.timerCommand == .start)
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
        archivedTask.statusRaw = LegacyTaskStatusRaw.archived
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

    @Test @MainActor
    func timerModeSeparatesRunningTasksWhileSingleSelectionKeepsThemSelectable() throws {
        let store = makeTestStore()
        let task = TaskNode(
            title: "Sample task",
            parentID: nil,
            deviceID: "test"
        )
        store.tasks = [task]
        store.checklistItems = [
            ChecklistItem(
                taskID: task.id,
                title: "First step",
                isCompleted: true,
                deviceID: "test"
            ),
            ChecklistItem(
                taskID: task.id,
                title: "Second step",
                deviceID: "test"
            ),
        ]
        store.activeSegments = [
            TimeSegment(
                sessionID: UUID(),
                taskID: task.id,
                source: .timer,
                deviceID: "test"
            ),
        ]
        let projection = TaskHierarchyProjection(
            store: store,
            expandedTaskIDs: [],
            searchText: ""
        )
        let section = try #require(projection.sections.first)
        let runningItem = try #require(projection.runningItems.first)
        let timerPicker = TaskHierarchyPicker(
            store: store,
            mode: .timer,
            onDismiss: {}
        )
        let selectionPicker = TaskHierarchyPicker(
            store: store,
            mode: .singleSelection(selectedTaskID: nil),
            onDismiss: {}
        )
        let multiSelectionPicker = TaskHierarchyPicker(
            store: store,
            mode: .multipleSelection(selectedTaskIDs: [task.id]),
            onDismiss: {}
        )

        #expect(timerPicker.displayedItems(in: section).isEmpty)
        #expect(selectionPicker.displayedItems(in: section).map(\.id) == [task.id])
        #expect(multiSelectionPicker.displayedItems(in: section).map(\.id) == [task.id])
        #expect(multiSelectionPicker.isSelected(runningItem))
        #expect(projection.runningItems.map(\.id) == [task.id])
        #expect(runningItem.checklistProgress?.completedCount == 1)
        #expect(runningItem.checklistProgress?.totalCount == 2)
        #expect(runningItem.workedSeconds == 0)
        #expect(
            selectionPicker.accessibilityValue(for: runningItem)
                .contains(AppStrings.running)
        )
        #expect(
            timerPicker.accessibilityValue(for: runningItem)
                .contains(AppStrings.running) == false
        )
    }

    @Test
    func heatmapSelectionTogglesMembershipWithoutReorderingOtherTasks() {
        let first = UUID()
        let second = UUID()
        let added = UUID()

        #expect(
            OrderedTaskIDSelectionMutation.toggling(
                added,
                in: [first, second]
            ) == [first, second, added]
        )
        #expect(
            OrderedTaskIDSelectionMutation.toggling(
                first,
                in: [first, second]
            ) == [second]
        )
    }

    @Test @MainActor
    func pickersOmitHealthSyncBranchesUnlessPreservingCurrentSelection() throws {
        let store = makeTestStore()
        let healthRoot = TaskNode(
            title: "Imported workout",
            parentID: nil,
            deviceID: "health"
        )
        healthRoot.id = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.running)
        ).id
        let healthChild = TaskNode(
            title: "Imported child",
            parentID: healthRoot.id,
            deviceID: "health"
        )
        let ordinary = TaskNode(
            title: "Ordinary",
            parentID: nil,
            deviceID: "user"
        )
        store.tasks = [healthRoot, healthChild, ordinary]

        let projection = TaskHierarchyProjection(
            store: store,
            expandedTaskIDs: [healthRoot.id],
            searchText: ""
        )
        let timerPicker = TaskHierarchyPicker(
            store: store,
            mode: .timer,
            onDismiss: {}
        )
        let selectionPicker = TaskHierarchyPicker(
            store: store,
            mode: .singleSelection(selectedTaskID: nil),
            onDismiss: {}
        )
        let preservingPicker = TaskHierarchyPicker(
            store: store,
            mode: .singleSelection(selectedTaskID: healthRoot.id),
            onDismiss: {}
        )
        let allProjectedItems = projection.sections.flatMap(\.items)
        let healthRootItem = try #require(
            allProjectedItems.first { $0.id == healthRoot.id }
        )
        let healthChildItem = try #require(
            allProjectedItems.first { $0.id == healthChild.id }
        )
        var multipleSelection: UUID?
        let multiplePreservingPicker = TaskHierarchyPicker(
            store: store,
            mode: .multipleSelection(selectedTaskIDs: [healthRoot.id]),
            onDismiss: {},
            onSelect: { multipleSelection = $0 }
        )

        #expect(Set(allProjectedItems.map(\.id)) == Set(store.tasks.map(\.id)))
        #expect(
            projection.sections.flatMap(timerPicker.displayedItems).map(\.id)
                == [ordinary.id]
        )
        #expect(
            projection.sections.flatMap(selectionPicker.displayedItems).map(\.id)
                == [ordinary.id]
        )
        #expect(
            Set(
                projection.sections
                    .flatMap(preservingPicker.displayedItems)
                    .map(\.id)
            ) == Set([healthRoot.id, ordinary.id])
        )
        #expect(
            Set(
                projection.sections
                    .flatMap(multiplePreservingPicker.displayedItems)
                    .map(\.id)
            ) == Set([healthRoot.id, ordinary.id])
        )
        #expect(multiplePreservingPicker.isSelectionDisabled(for: healthRootItem) == false)
        #expect(multiplePreservingPicker.isSelectionDisabled(for: healthChildItem))
        #expect(
            multiplePreservingPicker.accessibilityHint(for: healthRootItem) ==
                TaskHierarchyPickerSelectionContext.todayHeatmap.selectionHint
        )

        multiplePreservingPicker.select(healthRootItem)
        #expect(multipleSelection == healthRoot.id)
    }

    @Test @MainActor
    func selectionLimitDisablesOnlyNewRowsAndExplainsTheLimit() throws {
        let store = makeTestStore()
        let selected = TaskNode(
            title: "Selected",
            parentID: nil,
            deviceID: "user"
        )
        let available = TaskNode(
            title: "Available",
            parentID: nil,
            deviceID: "user"
        )
        store.tasks = [selected, available]

        let projection = TaskHierarchyProjection(
            store: store,
            expandedTaskIDs: [],
            searchText: ""
        )
        let items = projection.sections.flatMap(\.items)
        let selectedItem = try #require(items.first { $0.id == selected.id })
        let availableItem = try #require(items.first { $0.id == available.id })
        var selectedIDs: [UUID] = []
        let picker = TaskHierarchyPicker(
            store: store,
            mode: .multipleSelection(
                selectedTaskIDs: [selected.id],
                maximumSelectionCount: 1
            ),
            onDismiss: {},
            onSelect: { selectedIDs.append($0) }
        )

        #expect(picker.isSelectionDisabled(for: selectedItem) == false)
        #expect(picker.isSelectionDisabled(for: availableItem))
        #expect(
            picker.accessibilityHint(for: availableItem) ==
                String(
                    format: AppStrings.localized(
                        "taskPicker.selection.limitReachedFormat"
                    ),
                    1
                )
        )

        picker.select(selectedItem)
        picker.select(availableItem)
        #expect(selectedIDs == [selected.id])
    }
}
