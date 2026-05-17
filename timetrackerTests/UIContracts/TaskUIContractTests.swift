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
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarViews.swift")
        let storeSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore.swift")
        let selectionSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+Selection.swift")
        let rootSource = try sourceText("timetracker/App/RootViews/DesktopRootViews.swift")
        let splitButtonSource = try sourceText("timetracker/SharedUI/Components/SplitViewToolbarButtons.swift")

        #expect(sidebarSource.contains("@State private var isSyncingSelection = false"))
        #expect(sidebarSource.contains("guard !isSyncingSelection else { return }"))
        #expect(sidebarSource.contains("Task { @MainActor in"))
        #expect(sidebarSource.contains("DispatchQueue.main.async") == false)
        #expect(sidebarSource.contains("store.openTaskDetail(taskID)"))
        #expect(sidebarSource.contains("store.closeTaskDetailNavigation()"))
        #expect(sidebarSource.contains("if let desktopTaskDetailID = store.desktopTaskDetailID"))
        #expect(sidebarSource.contains(".accessibilityIdentifier(\"sidebar.task.\\(task.title)\")"))
        #expect(storeSource.contains("@Published var desktopTaskDetailID: UUID?"))
        #expect(selectionSource.contains("func openTaskDetail(_ taskID: UUID)"))
        #expect(selectionSource.contains("desktopTaskDetailID = taskID"))
        #expect(selectionSource.contains("desktopDestination = .tasks"))
        #expect(rootSource.contains("if let taskID = store.desktopTaskDetailID, store.task(for: taskID) != nil"))
        #expect(rootSource.contains("TaskDetailView(store: store, taskID: taskID)"))
        #expect(splitButtonSource.contains(".accessibilityIdentifier(\"sidebar.show\")"))
    }

    @Test
    func phoneTabsBindToSharedNavigationDestination() throws {
        let rootSource = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")

        #expect(rootSource.contains("@State private var selectedDestination: TimeTrackerStore.DesktopDestination = .today"))
        #expect(rootSource.contains("TabView(selection: $selectedDestination)"))
        #expect(rootSource.contains(".onChange(of: store.desktopDestination)"))
        #expect(rootSource.contains(".onChange(of: selectedDestination)"))
        #expect(rootSource.contains("private func phoneDestination(for destination: TimeTrackerStore.DesktopDestination)"))
        #expect(rootSource.contains(".tag(TimeTrackerStore.DesktopDestination.analytics)"))
        #expect(rootSource.contains(".tag(TimeTrackerStore.DesktopDestination.tasks)"))
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
    func tasksSearchUsesNativeSearchableInsteadOfUIKitWrapper() throws {
        let source = try taskManagementFeatureSource()

        #expect(source.contains(".searchable("))
        #expect(source.contains(".navigationBarDrawer(displayMode: .always)"))
        #expect(source.contains("SystemSearchBar") == false)
        #expect(source.contains("UIViewRepresentable") == false)
        #expect(source.contains("UISearchBar") == false)
        #expect(source.contains("import UIKit") == false)
    }

    @Test
    func taskRowsUseLifetimeRollupDurationInsteadOfTodayOnlyDuration() throws {
        let tasksSource = try sourceText("timetracker/Features/Tasks/Management/TaskManagementRowViews.swift")
        let detailSource = try taskDetailFeatureSource()
        let forecastSource = try sourceText("timetracker/Features/Tasks/Detail/TaskForecastPanel.swift")

        #expect(tasksSource.contains("rollup?.workedSeconds ?? store.secondsForTaskTotalRollup(task)"))
        #expect(tasksSource.contains("secondsForTaskTodayRollup(task)") == false)
        #expect(detailSource.contains("task.field.total"))
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
    func taskRowsOpenDetailInsteadOfEditingOnTap() throws {
        let tasksSource = try sourceText("timetracker/Features/Tasks/Management/TasksViews.swift")
        let rowSource = try sourceText("timetracker/Features/Tasks/Management/TaskManagementRowViews.swift")
        let detailSource = try taskDetailFeatureSource()
        let editorSource = try taskDetailEditorFeatureSource()
        let rootSource = try sourceText("timetracker/App/RootViews/DesktopRootViews.swift")
        let openTaskSource = try #require(rowSource.slice(from: "private func openTask()", to: "private struct TaskManagementRowContent"))

        #expect(tasksSource.contains("TaskDetailView(store: store, taskID: task.id)"))
        #expect(tasksSource.contains("@State private var detailTaskID"))
        #expect(rootSource.contains("TaskDetailView(store: store, taskID: taskID)"))
        #expect(rootSource.contains("TasksView(store: store)"))
        #expect(openTaskSource.contains("store.selectTask(task.id, revealInToday: false)"))
        #expect(openTaskSource.contains("presentEditTask") == false)
        #expect(detailSource.contains("TaskDetailEditorCard("))
        #expect(detailSource.contains("@State private var isEditorExpanded = false"))
        #expect(detailSource.contains("edit: { isEditorExpanded = true }"))
        #expect(detailSource.contains("isExpanded: $isEditorExpanded"))
        #expect(detailSource.contains("TaskDetailAnalysisSection"))
        #expect(detailSource.contains("TaskChecklistPanel(store: store, task: task)") == false)
        #expect(editorSource.contains("TextField(AppStrings.localized(\"editor.task.name\")"))
        #expect(editorSource.contains("TaskDetailStatusControl(selection: $draft.status)"))
        #expect(editorSource.contains("TextField(AppStrings.localized(\"editor.task.notes\"), text: $draft.notes, axis: .vertical)"))
        #expect(editorSource.contains("TextEditor(text: $draft.notes)") == false)
        #expect(editorSource.contains("if isExpanded {"))
        #expect(detailSource.contains("Image(systemName: \"pencil\")"))
        #expect(editorSource.contains("status.exampleText") == false)
        #expect(editorSource.contains("ChecklistEditorRow("))
    }

    @Test
    func uiRefactorPlanDocumentsInventoryAndResumableTDDLoop() throws {
        let doc = try sourceText("Docs/UIOperationRefactorPlan.md")
        let project = try sourceText("timetracker.xcodeproj/project.pbxproj")
        let infoPlist = try sourceText("timetracker/Info.plist")
        let seedSource = try sourceText("timetracker/App/SeedData.swift")
        let containerSource = try sourceText("timetracker/App/AppModelContainerFactory.swift")

        #expect(doc.contains("## UI Inventory"))
        #expect(doc.contains("## Operation Logic Inventory"))
        #expect(doc.contains("## TDD Loop"))
        #expect(doc.contains("## Context-Persistence Protocol"))
        #expect(doc.contains("Baseline simulator/app screenshots must happen before any new image generation."))
        #expect(doc.contains("## Screenshot-First Design Reference Workflow"))
        #expect(doc.contains("Date navigation belongs in Analytics"))
        #expect(doc.contains("- [x] Create branch `codex/ui-logic-refactor`."))
        #expect(doc.contains("- [x] Inventory root navigation, screens, and operation logic in this document."))
        #expect(doc.contains("- [x] Capture baseline iPhone/iPad/macOS screenshots before image generation."))
        #expect(doc.contains("- [x] Analyze baseline screenshots and update Screenshot Log."))
        #expect(doc.contains("- [ ] Generate screenshot-grounded design reference images from the prompts above."))
        #expect(doc.contains("Sync phone tab selection with shared navigation destination"))
        #expect(doc.contains("iphone-analytics-baseline.png"))
        #expect(doc.contains("mac-task-detail-baseline.png"))
        #expect(doc.contains("invalidated image generation"))
        #expect(project.contains("TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE = seedIfEmpty;"))
        #expect(project.contains("TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE = off;"))
        #expect(project.contains("INFOPLIST_KEY_TimeTrackerAutomaticDemoDataMode"))
        #expect(infoPlist.contains("<key>TimeTrackerAutomaticDemoDataMode</key>"))
        #expect(infoPlist.contains("<string>$(TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE)</string>"))
        #expect(seedSource.contains("case .replaceOnLaunch:"))
        #expect(containerSource.contains("AppDemoDataConfiguration.usesLocalDemoStore"))
    }

    @Test
    func taskDetailIsReadFirstBeforeInlineEditing() throws {
        let detailSource = try sourceText("timetracker/Features/Tasks/Detail/TaskDetailView.swift")
        let detailContent = try #require(detailSource.slice(from: "return ScrollView", to: ".background(AppColors.background)"))
        let headerIndex = try #require(detailContent.range(of: "TaskDetailHeader(")?.lowerBound)
        let overviewIndex = try #require(detailContent.range(of: "TaskDetailOverviewGrid(snapshot: snapshot)")?.lowerBound)
        let editorIndex = try #require(detailContent.range(of: "TaskDetailEditorCard(")?.lowerBound)
        let forecastIndex = try #require(detailContent.range(of: "TaskForecastPanel(store: store, task: task)")?.lowerBound)
        let analysisIndex = try #require(detailContent.range(of: "TaskDetailAnalysisSection(range: $range, snapshot: snapshot)")?.lowerBound)

        #expect(headerIndex < overviewIndex)
        #expect(overviewIndex < editorIndex)
        #expect(editorIndex < forecastIndex)
        #expect(forecastIndex < analysisIndex)
        #expect(detailContent.contains("TaskDetailHeader("))
        #expect(detailContent.contains("edit: { isEditorExpanded = true }"))
        #expect(detailSource.contains("@State private var isEditorExpanded = false"))
    }

    @Test
    func taskDetailUsesNativeCompactStatusControl() throws {
        let editorSource = try taskDetailEditorFeatureSource()

        #expect(editorSource.contains("TaskDetailStatusControl(selection: $draft.status)"))
        #expect(editorSource.contains("TaskDetailStatusSelector") == false)
        #expect(editorSource.contains(".pickerStyle(.segmented)"))
        #expect(editorSource.contains("status.exampleText") == false)
        #expect(editorSource.contains("HStack(spacing: 8) {\n                    Image(systemName: status.symbolName)") == false)
    }

    @Test
    func taskRowsKeepStatusWithMetadataInsteadOfFloatingAtTrailingEdge() throws {
        let rowSource = try sourceText("timetracker/Features/Tasks/Management/TaskManagementRowViews.swift")

        #expect(rowSource.contains("private var statusMetadataBadge"))
        #expect(rowSource.contains("statusMetadataBadge"))
        #expect(rowSource.contains("TaskStatusBadge(status: task.status)\n\n            if showsNavigationChevron") == false)
        #expect(rowSource.contains("TaskStatusBadge(status: task.status)\n                    if isRunning") == false)
    }

    @Test
    func settingsKeepsJSONExportVisibleInDataSectionOnly() throws {
        let settingsSource = try sourceText("timetracker/Features/Settings/SettingsViews.swift")
        let dataSource = try sourceText("timetracker/Features/Settings/SettingsDataSectionsViews.swift")

        #expect(settingsSource.contains(".fileExporter("))
        #expect(settingsSource.contains("JSONExportDocument(text: store.jsonExport())"))
        #expect(settingsSource.contains("defaultFilename: \"time-tracker-export.json\""))
        #expect(settingsSource.contains("Label(AppStrings.localized(\"settings.exportJSON\")") == false)
        #expect(dataSource.contains("title: AppStrings.localized(\"settings.exportJSON\")"))
        #expect(dataSource.contains("systemImage: \"curlybraces.square\""))
    }

    @Test
    func analyticsPageSurfacesDecisionMetricsAndQualitySections() throws {
        let analyticsSource = try [
            "timetracker/Features/Analytics/AnalyticsViews.swift",
            "timetracker/Features/Analytics/AnalyticsCategoryDetailViews.swift",
            "timetracker/Features/Analytics/AnalyticsPeriodSelectionViews.swift",
            "timetracker/Features/Analytics/AnalyticsPeriodSection.swift",
            "timetracker/Features/Analytics/AnalyticsInsightListViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsDecisionViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsOverviewViews.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
        let modelsSource = try sourceText("timetracker/Models/AnalyticsReadModels.swift")
        let englishStrings = try sourceText("timetracker/en.lproj/Localizable.strings")

        #expect(analyticsSource.contains("AnalyticsCategory.allCases"))
        #expect(analyticsSource.contains("AnalyticsCategoryDetailView("))
        #expect(analyticsSource.contains("case .decisions:"))
        #expect(analyticsSource.contains("AnalyticsInsightList(insights: snapshot.insights)"))
        #expect(analyticsSource.contains("TaskForecastsContent(store: store)"))
        #expect(analyticsSource.contains("AnalyticsPeriodControl(range: range, referenceDate: $referenceDate, liveNow: now)"))
        #expect(analyticsSource.contains("AnalyticsPeriodSection(range: $range, referenceDate: $referenceDate, liveNow: now)"))
        #expect(analyticsSource.contains("effectiveSnapshotDate(referenceDate: referenceDate, liveNow: now)"))
        #expect(analyticsSource.contains("case .quality:"))
        #expect(analyticsSource.contains("AnalyticsRhythmContent(rhythm: snapshot.rhythm)"))
        #expect(analyticsSource.contains("AnalyticsQualityContent(quality: snapshot.quality)"))
        #expect(analyticsSource.contains("AnalyticsOverlapContent(overlaps: snapshot.overlaps)"))
        #expect(analyticsSource.contains("snapshot.categoryBreakdown"))
        #expect(modelsSource.contains("struct AnalyticsInsight"))
        #expect(modelsSource.contains("struct TaskAnalyticsSnapshot"))
        #expect(englishStrings.contains("\"analytics.decisions.title\""))
        #expect(englishStrings.contains("\"analytics.quality.title\""))
    }

    @Test
    func analyticsMakesSelectedPeriodAndMetricMeaningsExplicit() throws {
        let analyticsSource = try [
            "timetracker/Features/Analytics/AnalyticsViews.swift",
            "timetracker/Features/Analytics/AnalyticsCategoryDetailViews.swift",
            "timetracker/Features/Analytics/AnalyticsOverviewDetailViews.swift",
            "timetracker/Features/Analytics/AnalyticsPeriodSelectionViews.swift",
            "timetracker/Features/Analytics/AnalyticsPeriodSection.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsOverviewViews.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
        let englishStrings = try sourceText("timetracker/en.lproj/Localizable.strings")

        #expect(analyticsSource.contains("AnalyticsPeriodTitle(range: range, referenceDate: referenceDate)"))
        #expect(analyticsSource.contains("AnalyticsPeriodSection(range: $range, referenceDate: $referenceDate, liveNow: now)"))
        #expect(analyticsSource.contains("AnalyticsMetricList("))
        #expect(analyticsSource.contains("AnalyticsGlossaryList()"))
        #expect(englishStrings.contains("\"analytics.glossary.gross\""))
        #expect(englishStrings.contains("\"analytics.glossary.wall\""))
        #expect(englishStrings.contains("\"analytics.glossary.overlap\""))

        let decisionSource = try sourceText("timetracker/Features/Analytics/Sections/AnalyticsDecisionViews.swift")
        let decisionGrid = try #require(decisionSource.slice(from: "struct AnalyticsDecisionSummaryGrid", to: "private struct AnalyticsInsightCard"))
        #expect(decisionGrid.contains("AnalyticsChartCard(") == false)

        let uiTestSource = try sourceText("timetrackerUITests/timetrackerUITests.swift")
        #expect(uiTestSource.contains("analyticsIsReady(in app: XCUIApplication)"))
        #expect(uiTestSource.contains("analytics.decisionSummary"))
        #expect(uiTestSource.contains("analytics.periodControl"))
    }

    @Test
    func checklistUsesTodoStyleAndKeepsCompletedHistoryHint() throws {
        let editorSource = try taskEditorFeatureSource()
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
        #expect(editorSource.contains("TextField(AppStrings.localized(\"editor.task.notes\"), text: $notes, axis: .vertical)"))
        #expect(editorSource.contains("TextEditor(text: $notes)") == false)
        #expect(editorSource.contains("EditButton()") == false)
        #expect(editorSource.contains(".onMove(perform: moveChecklistItems)"))
        #expect(editorSource.contains("Image(systemName: \"trash\")"))
        #expect(editorSource.contains("Image(systemName: \"chevron.up\")"))
        #expect(editorSource.contains("Image(systemName: \"chevron.down\")"))
        #expect(editorSource.contains("#if os(macOS)"))
        #expect(editorSource.contains(".labelsHidden()"))
        #expect(editorSource.contains("arrow.up.arrow.down.circle") == false)
        #expect(editorSource.contains(".strikethrough(item.isCompleted)"))
        #expect(englishStrings.contains("\"checklist.showLess\""))
        #expect(englishStrings.contains("\"checklist.keepCompletedHint\""))
    }

    @Test
    func sidebarAndTaskRowsShareSwipeActions() throws {
        let taskRowSource = try sourceText("timetracker/Features/Tasks/Management/TaskRowComponents.swift")
        let managementSource = try sourceText("timetracker/Features/Tasks/Management/TaskManagementRowViews.swift")
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarViews.swift")

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
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarViews.swift")
        let editorSource = try taskEditorFeatureSource()
        let storeSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+TaskCommands.swift")

        #expect(tasksSource.contains("taskCategoryDropDestination") == false)
        #expect(tasksSource.contains("dropDestination(") == false)
        #expect(tasksSource.contains("CategoryDropTargetRow") == false)
        #expect(rowSource.contains("rootTaskDragIfNeeded") == false)
        #expect(rowSource.contains(".draggable(") == false)
        #expect(rowSource.contains("RootTaskDragPayload") == false)
        let leadingSwipe = try #require(tasksSource.slice(from: ".swipeActions(edge: .leading", to: ".swipeActions(edge: .trailing"))
        let trailingSwipe = try #require(tasksSource.slice(from: ".swipeActions(edge: .trailing", to: "ForEach(section.rows)"))
        #expect(leadingSwipe.contains("allowsFullSwipe: true"))
        #expect(trailingSwipe.contains("allowsFullSwipe: true"))
        #expect(tasksSource.contains("Button(action: newRootTaskAction(for: section))"))
        #expect(leadingSwipe.contains("Image(systemName: \"plus\")"))
        #expect(leadingSwipe.contains(".accessibilityLabel(AppStrings.localized(\"tasks.newRoot\"))"))
        #expect(leadingSwipe.contains("Label(AppStrings.localized(\"tasks.newRoot\"), systemImage: \"plus\")") == false)
        #expect(trailingSwipe.contains("Image(systemName: \"trash\")"))
        #expect(trailingSwipe.contains(".accessibilityLabel(AppStrings.localized(\"taskCategory.delete\"))"))
        #expect(trailingSwipe.contains("Label(AppStrings.localized(\"taskCategory.delete\"), systemImage: \"trash\")") == false)
        #expect(tasksSource.contains("store.deleteTaskCategory(category)"))
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

    private func taskDetailFeatureSource() throws -> String {
        try [
            "timetracker/Features/Tasks/Detail/TaskDetailView.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailHeaderView.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailAnalysisViews.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailRecentRecordsViews.swift",
            "timetracker/Features/Tasks/Detail/TaskForecastPanel.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
    }

    private func taskDetailEditorFeatureSource() throws -> String {
        try [
            "timetracker/Features/Tasks/Detail/TaskDetailEditorViews.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailChecklistEditorSection.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailEditorSupportViews.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
    }

    private func taskManagementFeatureSource() throws -> String {
        try [
            "timetracker/Features/Tasks/Management/TasksViews.swift",
            "timetracker/Features/Tasks/Management/TaskSearchPlacementModifier.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
    }
}
