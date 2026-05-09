import Foundation
import Testing

@Suite(.serialized)
struct TaskUIContractTests {
    @Test
    func taskTreeUsesFlatVisibleRowsSoEachTaskOwnsItsListRow() throws {
        let source = try sourceText("timetracker/Features/Tasks/Management/TasksViews.swift")
        let serviceSource = try sourceText("timetracker/Services/Tasks/TaskTreeServices.swift")

        #expect(source.contains("ForEach(store.taskTreeSections(expandedTaskIDs: expansionState.expandedTaskIDs))"))
        #expect(source.contains("TaskCategorySectionHeader"))
        #expect(source.contains("didExpandInitialTree"))
        #expect(source.contains("TaskManagementTreeRow") == false)
        #expect(source.contains("DisclosureGroup(") == false)
        #expect(serviceSource.contains("struct TaskTreeFlattener"))
        #expect(serviceSource.contains("TaskTreeCategorySectionModel"))
        #expect(serviceSource.contains("TaskTreeRowModel"))
        #expect(source.contains("rotationEffect") == false)
        #expect(source.contains(".transaction { transaction in\n            transaction.animation = nil\n        }") == false)
    }

    @Test
    func longTaskAndAnalyticsPagesUseInlineTitlesToAvoidScrollJitter() throws {
        let tasksSource = try sourceText("timetracker/Features/Tasks/Management/TasksViews.swift")
        let analyticsSource = try sourceText("timetracker/Features/Analytics/AnalyticsViews.swift")
        let pomodoroSource = try sourceText("timetracker/Features/Pomodoro/PomodoroViews.swift")
        let settingsSource = try sourceText("timetracker/Features/Settings/SettingsViews.swift")

        #expect(tasksSource.contains(".navigationTitle(AppStrings.tasks)"))
        #expect(tasksSource.contains(".navigationBarTitleDisplayMode(.inline)"))
        #expect(tasksSource.contains("store.presentNewTask(preservingDestination: .tasks)"))
        #expect(analyticsSource.contains(".navigationTitle(AppStrings.analytics)"))
        #expect(analyticsSource.contains(".navigationBarTitleDisplayMode(.inline)"))
        #expect(pomodoroSource.contains(".navigationTitle(AppStrings.pomodoro)"))
        #expect(pomodoroSource.contains(".navigationBarTitleDisplayMode(.inline)"))
        #expect(settingsSource.contains(".navigationTitle(AppStrings.settings)"))
        #expect(settingsSource.contains(".navigationBarTitleDisplayMode(.inline)"))
    }

    @Test
    func sidebarSelectionSyncDoesNotRevealProgrammaticTaskSelection() throws {
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarInspectorViews.swift")

        #expect(sidebarSource.contains("@State private var isSyncingSelection = false"))
        #expect(sidebarSource.contains("guard !isSyncingSelection else { return }"))
        #expect(sidebarSource.contains("DispatchQueue.main.async"))
    }

    @Test
    func compactTaskRowsShowChecklistProgressBar() throws {
        let source = try sourceText("timetracker/Features/Tasks/Management/TaskManagementRowViews.swift")
        let sharedSource = try sourceText("timetracker/SharedUI/Components/TaskProgressViews.swift")

        #expect(source.contains("CompactChecklistProgressLine("))
        #expect(sharedSource.contains("ProgressView(value: progress.fraction)"))
        #expect(sharedSource.contains("checklist.progressFormat"))
        #expect(sharedSource.contains("struct TaskProgressLine"))
        #expect(source.contains("if progress.totalCount > 0 {\n                    CompactChecklistProgressLine"))
    }

    @Test
    func taskRowsUseLifetimeRollupDurationInsteadOfTodayOnlyDuration() throws {
        let tasksSource = try sourceText("timetracker/Features/Tasks/Management/TaskManagementRowViews.swift")
        let inspectorSource = try sourceText("timetracker/Features/Inspector/Sections/InspectorInfoViews.swift")
        let forecastSource = try sourceText("timetracker/Features/Inspector/Sections/InspectorForecastViews.swift")

        #expect(tasksSource.contains("rollup?.workedSeconds ?? store.secondsForTaskTotalRollup(task)"))
        #expect(tasksSource.contains("secondsForTaskTodayRollup(task)") == false)
        #expect(inspectorSource.contains("task.field.total"))
        #expect(forecastSource.contains("forecast.worked"))
    }

    @Test
    func taskEditorUsesInlineStatusPickerAndRemovesTaskKindClassification() throws {
        let editorSource = try taskEditorFeatureSource()
        let modelsSource = try sourceText("timetracker/Models/TaskModels.swift")
        let englishStrings = try sourceText("timetracker/en.lproj/Localizable.strings")

        #expect(editorSource.contains("TaskStatusPicker(selection: $draft.status)"))
        #expect(editorSource.contains(".pickerStyle(.inline)"))
        #expect(editorSource.contains("TaskStatusPickerOption(status: status)"))
        #expect(editorSource.contains("TaskKindPicker") == false)
        #expect(modelsSource.contains("enum TaskNodeKind") == false)
        #expect(englishStrings.contains("editor.task.kind") == false)
    }

    @Test
    func taskCategoryEditorReusesSharedSymbolColorPicker() throws {
        let categoryEditor = try sourceText("timetracker/Features/Tasks/Editor/TaskCategoryEditorViews.swift")
        let symbolPicker = try sourceText("timetracker/Features/Tasks/Editor/SymbolPickerViews.swift")

        #expect(categoryEditor.contains("SymbolColorPickerRow("))
        #expect(categoryEditor.contains("Picker(AppStrings.localized(\"taskCategory.symbol\")") == false)
        #expect(categoryEditor.contains("private let symbols") == false)
        #expect(categoryEditor.contains("private var colorGrid") == false)
        #expect(symbolPicker.contains("struct SymbolColorPickerRow"))
        #expect(symbolPicker.contains("SymbolAndColorPicker("))
    }

    @Test
    func taskListShowsStatusBadgesInsteadOfTaskKindBadges() throws {
        let tasksSource = try sourceText("timetracker/Features/Tasks/Management/TaskManagementRowViews.swift")
        let sharedSource = try [
            "timetracker/SharedUI/Components/ChecklistControls.swift",
            "timetracker/SharedUI/Components/StatusBadges.swift",
            "timetracker/SharedUI/Components/TaskVisuals.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")

        #expect(tasksSource.contains("TaskStatusBadge(status: task.status)"))
        #expect(tasksSource.contains("store.selectTask(task.id, revealInToday: false)"))
        #expect(tasksSource.contains("RunningStatusBadge()"))
        #expect(tasksSource.contains("TaskKindBadge") == false)
        #expect(sharedSource.contains("struct TaskKindBadge") == false)
        #expect(sharedSource.contains("struct TaskStatusBadge"))
        #expect(sharedSource.contains("struct RunningStatusBadge"))
    }

    @Test
    func checklistUsesTodoStyleAndKeepsCompletedHistoryHint() throws {
        let editorSource = try taskEditorFeatureSource()
        let inspectorSource = try sourceText("timetracker/Features/Inspector/Sections/InspectorChecklistViews.swift")
        let sharedSource = try sourceText("timetracker/SharedUI/Components/ChecklistControls.swift")
        let englishStrings = try sourceText("timetracker/en.lproj/Localizable.strings")

        #expect(sharedSource.contains("\"checkmark.circle.fill\""))
        #expect(sharedSource.contains("struct ChecklistDisplayRow"))
        #expect(sharedSource.contains("struct InlineChecklistAddRow"))
        #expect(editorSource.contains("ChecklistCompletionButton"))
        #expect(sharedSource.contains(".symbolEffect(.bounce, value: isCompleted)") == false)
        #expect(sharedSource.contains(".animation(.snappy") == false)
        #expect(editorSource.contains("withAnimation(.snappy") == false)
        #expect(editorSource.contains(".animation(.snappy") == false)
        #expect(sharedSource.contains(".lineLimit(nil)"))
        #expect(editorSource.contains("TextField(AppStrings.localized(\"editor.checklist.itemPlaceholder\"), text: $item.title, axis: .vertical)"))
        #expect(editorSource.contains("EditButton()") == false)
        #expect(editorSource.contains(".onMove(perform: moveChecklistItems)"))
        #expect(editorSource.contains("Image(systemName: \"trash\")"))
        #expect(editorSource.contains("Image(systemName: \"chevron.up\")"))
        #expect(editorSource.contains("Image(systemName: \"chevron.down\")"))
        #expect(editorSource.contains("#if os(macOS)"))
        #expect(editorSource.contains(".labelsHidden()"))
        #expect(editorSource.contains("arrow.up.arrow.down.circle") == false)
        #expect(editorSource.contains(".strikethrough(item.isCompleted)"))
        #expect(inspectorSource.contains("store.toggleChecklistItem(item)"))
        #expect(inspectorSource.contains("private struct ChecklistDisplayRow") == false)
        #expect(inspectorSource.contains("private struct InlineChecklistAddRow") == false)
        #expect(inspectorSource.contains("withAnimation(.snappy") == false)
        #expect(inspectorSource.contains("showsAllItems"))
        #expect(inspectorSource.contains("EditButton()") == false)
        #expect(inspectorSource.contains("List {") == false)
        #expect(inspectorSource.contains("maxHeight: 360") == false)
        #expect(englishStrings.contains("\"checklist.showLess\""))
        #expect(englishStrings.contains("\"checklist.keepCompletedHint\""))
    }

    @Test
    func sidebarAndTaskRowsShareSwipeActions() throws {
        let taskRowSource = try sourceText("timetracker/Features/Tasks/Management/TaskRowComponents.swift")
        let managementSource = try sourceText("timetracker/Features/Tasks/Management/TaskManagementRowViews.swift")
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarInspectorViews.swift")

        #expect(taskRowSource.contains("struct TaskRowSwipeActions"))
        #expect(taskRowSource.contains("enum TaskRowSwipeLabelStyle"))
        #expect(taskRowSource.contains("case iconOnly"))
        #expect(managementSource.contains(".taskRowSwipeActions(store: store, task: task, preservingDestination: .tasks)"))
        #expect(sidebarSource.contains(".taskRowSwipeActions(store: store, task: task, labelStyle: .iconOnly)"))
    }

    @Test
    func taskCategoriesSupportSidebarDividersWithoutDragReassignment() throws {
        let tasksSource = try sourceText("timetracker/Features/Tasks/Management/TasksViews.swift")
        let rowSource = try sourceText("timetracker/Features/Tasks/Management/TaskManagementRowViews.swift")
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarInspectorViews.swift")
        let editorSource = try taskEditorFeatureSource()
        let storeSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+TaskCommands.swift")

        #expect(tasksSource.contains("taskCategoryDropDestination") == false)
        #expect(tasksSource.contains("dropDestination(") == false)
        #expect(tasksSource.contains("CategoryDropTargetRow") == false)
        #expect(rowSource.contains("rootTaskDragIfNeeded") == false)
        #expect(rowSource.contains(".draggable(") == false)
        #expect(rowSource.contains("RootTaskDragPayload") == false)
        #expect(sidebarSource.contains("showsBottomDivider: true"))
        #expect(editorSource.contains("taskCategory.inherited"))
        #expect(editorSource.contains("LabeledContent(AppStrings.localized(\"taskCategory.title\")") == false)
        #expect(storeSource.contains("func moveRootTaskToCategory") == false)
    }

    private func taskEditorFeatureSource() throws -> String {
        try [
            "timetracker/Features/Tasks/Editor/TaskEditorViews.swift",
            "timetracker/Features/Tasks/Editor/TaskEditorComponents.swift",
            "timetracker/Features/Tasks/Editor/TaskEditorInfoSection.swift",
            "timetracker/Features/Tasks/Editor/TaskStatusPicker.swift",
            "timetracker/Features/Tasks/Editor/TaskPlanEditorSection.swift",
            "timetracker/Features/Tasks/Editor/TaskNotesEditorSection.swift",
            "timetracker/Features/Tasks/Editor/TaskChecklistEditorSection.swift",
            "timetracker/Features/Tasks/Editor/ChecklistEditorRow.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
    }
}
