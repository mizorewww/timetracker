import Foundation
import Testing

@Suite(.serialized)
struct TaskUIContractTests {
    @Test
    func taskTreeRowsExposeStableIdentifiersAndAccessibleDisclosureControls() throws {
        let tasksSource = try sourceText("timetracker/Features/Tasks/Management/TasksViews.swift")
        let rowSource = try taskManagementFeatureSource()
        let serviceSource = try [
            "timetracker/Services/Tasks/TaskTreeModels.swift",
            "timetracker/Services/Tasks/TaskTreeReadIndex.swift",
            "timetracker/Services/Tasks/TaskTreeFlattener.swift"
        ].map(sourceText).joined(separator: "\n")

        #expect(tasksSource.contains("List {"))
        #expect(tasksSource.contains(".accessibilityIdentifier(\"tasks.view\")"))
        #expect(tasksSource.contains("TaskCategorySectionHeader"))
        #expect(rowSource.contains(".accessibilityIdentifier(\"tasks.row.\\(task.id.uuidString)\")"))
        #expect(rowSource.contains(".accessibilityIdentifier(\"tasks.disclosure.\\(task.id.uuidString)\")"))
        #expect(rowSource.contains("AppStrings.localized(\"tasks.openDetail\")"))
        #expect(rowSource.contains("AppStrings.localized(\"tasks.collapse\")"))
        #expect(rowSource.contains("AppStrings.localized(\"tasks.expand\")"))
        #expect(rowSource.contains(".accessibilityValue(task.title)"))
        #expect(rowSource.contains(".frame(width: 44, height: 44)"))
        #expect(serviceSource.contains("struct TaskTreeFlattener"))
        #expect(serviceSource.contains("TaskTreeCategorySectionModel"))
        #expect(serviceSource.contains("TaskTreeRowModel"))
    }

    @Test
    func taskSearchKeepsAVisibleFieldAtAccessibilitySizes() throws {
        let source = try sourceText("timetracker/Features/Tasks/Management/TasksViews.swift")

        #expect(source.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(source.contains("TasksSearchPresentation("))
        #expect(source.contains("TextField(AppStrings.localized(\"tasks.searchTitle\"), text: $searchText)"))
        #expect(source.contains(".accessibilityHint(AppStrings.localized(\"tasks.searchHint\"))"))
        #expect(source.contains(".accessibilityIdentifier(\"tasks.search.field\")"))
        #expect(source.contains("Label(AppStrings.localized(\"tasks.searchPrompt\")") == false)
        #expect(source.contains("content.searchable("))
    }

    @Test
    func longTaskAndAnalyticsPagesUseInlineTitlesToAvoidScrollJitter() throws {
        let tasksSource = try sourceText("timetracker/Features/Tasks/Management/TasksViews.swift")
        let analyticsSource = try sourceText("timetracker/Features/Analytics/AnalyticsViews.swift")
        let pomodoroSource = try sourceText("timetracker/Features/Pomodoro/PomodoroViews.swift")
        let settingsSource = try sourceText("timetracker/Features/Settings/SettingsViews.swift")

        #expect(tasksSource.contains(".navigationTitle(AppStrings.tasks)"))
        #expect(tasksSource.contains(".navigationBarTitleDisplayMode(.inline)"))
        #expect(tasksSource.contains("presentationRouter.presentNewTask("))
        #expect(tasksSource.contains("preservingDestination: .tasks"))
        #expect(tasksSource.contains(".accessibilityIdentifier(\"tasks.add\")"))
        #expect(tasksSource.contains(".accessibilityIdentifier(\"tasks.addRoot\")"))
        #expect(analyticsSource.contains(".navigationTitle(AppStrings.analytics)"))
        #expect(analyticsSource.contains(".navigationBarTitleDisplayMode(.inline)"))
        #expect(pomodoroSource.contains(".navigationTitle(AppStrings.focus)"))
        #expect(pomodoroSource.contains(".navigationBarTitleDisplayMode(.inline)"))
        #expect(settingsSource.contains(".navigationTitle(AppStrings.settings)"))
        #expect(settingsSource.contains(".navigationBarTitleDisplayMode(.inline)"))
    }

    @Test
    func sidebarSelectionTracksNavigationWithStableAccessibleTargets() throws {
        let sidebarSource = try [
            "timetracker/Features/Sidebar/SidebarViews.swift",
            "timetracker/Features/Sidebar/SidebarTaskTreeViews.swift"
        ].map(sourceText).joined(separator: "\n")
        let selectionSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+Selection.swift")
        let rootSource = try sourceText("timetracker/App/RootViews/DesktopRootViews.swift")

        #expect(sidebarSource.contains("List(selection: selectionBinding)"))
        #expect(sidebarSource.contains(".accessibilityIdentifier(\"sidebar.\\(destination.rawValue)\")"))
        #expect(sidebarSource.contains(".accessibilityIdentifier(\"sidebar.task.\\(task.id.uuidString)\")"))
        #expect(sidebarSource.contains("guard let newValue, newValue != selectionFromStore else { return }"))
        #expect(sidebarSource.contains("private var selectionBinding: Binding<SidebarSelection?>"))
        #expect(sidebarSource.contains("private var selectionFromStore: SidebarSelection"))
        #expect(sidebarSource.contains("store.openTaskDetail(taskID)"))
        #expect(sidebarSource.contains("store.closeTaskDetailNavigation()"))
        #expect(sidebarSource.contains(".onChange(of: store.tasksRoute)"))
        #expect(sidebarSource.contains("@State private var selection") == false)
        #expect(selectionSource.contains("func openTaskDetail(_ taskID: UUID)"))
        #expect(selectionSource.contains("func closeTaskDetailNavigation()"))
        #expect(rootSource.contains("TasksNavigationView(store: store)"))
        #expect(rootSource.contains("desktopTaskDetailID") == false)
    }

    @Test
    func phoneTabsKeepTodayTaskDetailsOnTheirSourceStack() throws {
        let rootSource = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")
        let todayNavigationSource = try sourceText(
            "timetracker/Features/Home/TodayTaskNavigation.swift"
        )

        #expect(rootSource.contains("@State private var selectedDestination: TimeTrackerStore.DesktopDestination = .today"))
        #expect(rootSource.contains("@State private var todayTaskRoute: TasksRoute?"))
        #expect(rootSource.contains("TabView(selection: $selectedDestination)"))
        #expect(rootSource.contains(".onChange(of: store.desktopDestination)"))
        #expect(rootSource.contains(".onChange(of: selectedDestination)"))
        #expect(rootSource.contains("private func synchronize(with destination: TimeTrackerStore.DesktopDestination)"))
        #expect(rootSource.contains("Tab(value: .analytics)"))
        #expect(rootSource.contains("Tab(value: .tasks)"))
        #expect(rootSource.contains("Tab(value: .settings)") == false)
        #expect(rootSource.contains("private enum PhoneTodayRoute: Hashable") == false)
        #expect(rootSource.contains("todayPath") == false)
        #expect(rootSource.contains("presentationRouter.presentSettings()"))
        #expect(rootSource.contains("todayTaskRoute = store.prepareTaskDetailRoute(taskID)"))
        #expect(rootSource.contains("store.openTaskDetail(taskID)") == false)
        #expect(rootSource.contains("selectedDestination = .tasks") == false)
        #expect(rootSource.contains("case task(UUID)") == false)
        #expect(todayNavigationSource.contains(".navigationDestination(item: $route)"))
        #expect(todayNavigationSource.contains("returnDestination: .today"))
        #expect(todayNavigationSource.contains("private var routedTaskIsValid: Bool"))
        #expect(todayNavigationSource.contains(".onChange(of: routedTaskIsValid)"))
        #expect(todayNavigationSource.contains("clearInvalidRoute()"))
        #expect(todayNavigationSource.contains("store.taskTreeReadIndexRevision") == false)
    }

    @Test
    func compactTaskRowsShowChecklistProgressBar() throws {
        let source = try taskManagementFeatureSource()
        let sharedSource = try sourceText("timetracker/SharedUI/Components/TaskProgressViews.swift")

        #expect(source.contains("CompactChecklistProgressLine("))
        #expect(sharedSource.contains("ProgressView(value: progress.fraction)"))
        #expect(sharedSource.contains("checklist.progressFormat"))
        #expect(sharedSource.contains("struct TaskProgressLine"))
        #expect(source.contains("if presentation.progress.totalCount > 0 {"))
        #expect(source.contains("progress: presentation.progress"))
    }

    @Test
    func taskActionsRespectArchivedAndRunningSubtreeState() throws {
        let actionSource = try sourceText("timetracker/Features/Tasks/Management/TaskRowComponents.swift")
        let detailSource = try sourceText("timetracker/Features/Tasks/Detail/TaskDetailActionsView.swift")
        let identitySource = try sourceText("timetracker/Features/Tasks/Detail/TaskDetailIdentityViews.swift")

        #expect(actionSource.contains("store.isTaskAvailableForTracking(task)"))
        #expect(actionSource.contains("store.hasActiveTimer(inTaskSubtree: task.id)"))
        #expect(actionSource.contains("task.action.archive.stopFirst"))
        #expect(actionSource.contains("if let activeSegment"))
        #expect(actionSource.contains("store.stop(segment: activeSegment)"))
        #expect(detailSource.contains("task.detail.trackingUnavailable"))
        #expect(detailSource.contains("task.archived.trackingUnavailable"))
        #expect(identitySource.contains("!store.isTaskAvailableForTracking(task)"))
    }

    @Test
    func completedTasksStayVisibleButExposeReopenInsteadOfNewWork() throws {
        let readModels = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+TaskReadModels.swift")
        let tasksSource = try sourceText("timetracker/Features/Tasks/Management/TasksViews.swift")
        let actionSource = try sourceText("timetracker/Features/Tasks/Management/TaskRowComponents.swift")
        let detailSource = try sourceText("timetracker/Features/Tasks/Detail/TaskDetailActionsView.swift")
        let editorSource = try taskEditorFeatureSource()
        let appIntentSource = try sourceText("timetracker/AppIntents/TimeTrackerAppIntents.swift")

        #expect(readModels.contains("visibleTaskIDs = eligibility.visibleTaskIDs"))
        #expect(readModels.contains("trackableTaskIDs = eligibility.trackableTaskIDs"))
        #expect(readModels.contains("taskTreeReadIndex.visibleChildIDsByParentID"))
        #expect(tasksSource.contains("store.visibleTaskCount == 0"))
        #expect(tasksSource.contains("store.taskSearchResults(matching: query)"))
        #expect(tasksSource.contains("store.tasks.contains(where: store.isTaskVisible)") == false)
        #expect(actionSource.contains("store.reopenTaskForWork(task.id)"))
        #expect(actionSource.contains("task.action.reopenAncestorFormat"))
        #expect(actionSource.contains("task.action.complete.stopFirst"))
        #expect(detailSource.contains("task.completed.workUnavailable"))
        #expect(detailSource.contains("task.detail.reopen"))
        #expect(editorSource.contains("task.parent.completedLocked"))
        #expect(editorSource.contains("disabledStatuses:"))
        #expect(appIntentSource.contains(".trackableTaskIDs(tasks: tasks)"))
    }

    @Test
    func trackedTimeAssignmentPickersHideArchivedBranchesWithoutBreakingHistoryEdits() throws {
        let manualSource = try sourceText("timetracker/Features/Ledger/ManualTimeViews.swift")
        let segmentSource = try segmentEditorFeatureSource()

        #expect(manualSource.contains("store.tasks.filter(store.isTaskAvailableForTracking)"))
        #expect(segmentSource.contains("store.isTaskAvailableForTracking(task) || task.id == initialDraft.taskID"))
        #expect(manualSource.contains("ForEach(store.tasks") == false)
        #expect(segmentSource.contains("ForEach(store.tasks") == false)
    }

    @Test
    func trackedTimeEditorsBoundPickersAndDurationsToNow() throws {
        let manualSource = try sourceText("timetracker/Features/Ledger/ManualTimeViews.swift")
        let segmentSource = try segmentEditorFeatureSource()

        #expect(manualSource.components(separatedBy: "in: ...now").count - 1 == 2)
        #expect(segmentSource.components(separatedBy: "in: ...now").count - 1 == 2)
        #expect(manualSource.contains("TrackedTimePolicy.validateWrite("))
        #expect(segmentSource.contains("TrackedTimePolicy.validateWrite("))
        #expect(manualSource.contains("TrackedTimePolicy.elapsedSeconds("))
        #expect(segmentSource.contains("TrackedTimePolicy.elapsedSeconds("))
        #expect(manualSource.contains("segment.error.timeNotFuture"))
        #expect(segmentSource.contains("segment.error.timeNotFuture"))
        #expect(manualSource.contains("validation != .valid"))
        #expect(segmentSource.contains("validation != .valid"))
        #expect(segmentSource.contains("if draft.wasActive"))
        #expect(segmentSource.contains("segment.finished"))
        #expect(segmentSource.contains("Toggle(AppStrings.localized(\"segment.active\")") == false)
        #expect(segmentSource.contains("draft.endedAt = Date()"))
        #expect(segmentSource.contains("segment.keepRunning"))
        #expect(segmentSource.contains("segment.softDelete") == false)
        #expect(manualSource.contains(".presentationDetents([.large])"))
        #expect(manualSource.contains(".medium") == false)
        #expect(segmentSource.contains(".presentationDetents([.large])"))
        #expect(segmentSource.contains("@State private var draft"))
        #expect(segmentSource.contains("@State var draft") == false)
        #expect(manualSource.contains("timeIntervalSince(draft.startedAt)") == false)
        #expect(segmentSource.contains("timeIntervalSince(draft.startedAt)") == false)
    }

    @Test
    func trackedTimeNotesAreMultilineAndValidateBeforeSave() throws {
        let manualSource = try sourceText("timetracker/Features/Ledger/ManualTimeViews.swift")
        let segmentSource = try segmentEditorFeatureSource()

        for source in [manualSource, segmentSource] {
            #expect(source.contains("axis: .vertical"))
            #expect(source.contains(".lineLimit(3...8)"))
            #expect(source.contains("LedgerPersistencePolicy.prepareNote(draft.note)"))
            #expect(source.contains("noteError != nil"))
            #expect(source.contains("noteValidationLabel(noteError)"))
        }
        #expect(manualSource.contains("manualTime.note"))
        #expect(segmentSource.contains("segmentEditor.note"))
    }

    @Test
    func accessibilityTaskLayoutsStackCriticalContentWithoutChangingStableTargets() throws {
        let rowSource = try taskManagementFeatureSource()
        let categorySource = try sourceText("timetracker/SharedUI/Components/TaskCategoryViews.swift")
        let detailSource = try taskDetailFeatureSource()

        #expect(rowSource.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(rowSource.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(rowSource.contains("TaskManagementAccessibilityBody("))
        #expect(rowSource.contains("Text(presentation.path)"))
        #expect(rowSource.contains("AppStrings.localized(\"tasks.workedFormat\")"))
        #expect(rowSource.contains("TaskProgressLine(progress: presentation.progress, rollup: presentation.rollup)"))
        #expect(rowSource.contains("projectedDaysDisplayText"))
        #expect(rowSource.contains("AppStrings.localized(\"tasks.childCount\")"))
        #expect(rowSource.contains("TaskManagementRowAccessibilitySnapshot("))
        #expect(rowSource.contains(".accessibilityLabel(accessibility.label)"))
        #expect(rowSource.contains(".accessibilityValue(accessibility.value)"))
        #expect(rowSource.contains(".accessibilityRepresentation") == false)
        #expect(rowSource.contains(".accessibilityElement(children: .ignore)") == false)
        #expect(rowSource.contains("struct TaskManagementRowPresentation"))
        #expect(rowSource.contains("ListFormatter.localizedString(byJoining: valueComponents)"))
        #expect(rowSource.contains("else if task.status != .active"))
        #expect(rowSource.contains(".lineLimit(nil)"))
        #expect(rowSource.contains(".accessibilityIdentifier(\"tasks.row.\\(task.id.uuidString)\")"))
        #expect(rowSource.contains(".accessibilityIdentifier(\"tasks.disclosure.\\(task.id.uuidString)\")"))

        #expect(categorySource.contains("if dynamicTypeSize.isAccessibilitySize && !compact"))
        #expect(categorySource.contains("private var accessibilityHeader"))
        #expect(categorySource.contains(".frame(minWidth: 18, alignment: .center)"))
        #expect(categorySource.contains(".frame(width: 18)") == false)
        #expect(categorySource.contains(".accessibilityIdentifier(\"tasks.category.actions.\\(section.id)\")"))

        #expect(detailSource.contains("private var actionLayout"))
        #expect(detailSource.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(detailSource.contains("private struct TaskDetailChecklistHeader"))
        #expect(detailSource.contains("private struct TaskDetailForecastValue"))
        #expect(detailSource.contains(".pickerStyle(.menu)"))
        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail.actions\")"))
        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail.identity\")"))
    }

    @Test
    func taskRowsAndDetailExposeLifetimeRollupSemantics() throws {
        let tasksSource = try taskManagementFeatureSource()
        let detailSource = try taskDetailFeatureSource()

        #expect(tasksSource.contains("rollup?.workedSeconds ?? store.secondsForTaskTotalRollup(task)"))
        #expect(tasksSource.contains("secondsForTaskTodayRollup(task)") == false)
        #expect(detailSource.contains("AppStrings.localized(\"forecast.worked\")"))
        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail.summary\")"))
        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail.forecast\")"))
    }

    @Test
    func taskEditorUsesInlineStatusPickerAndRemovesTaskKindClassification() throws {
        let editorSource = try taskEditorFeatureSource()
        let modelsSource = try sourceText("timetracker/Models/TaskModels.swift")
        let englishStrings = try sourceText("timetracker/en.lproj/Localizable.strings")

        #expect(editorSource.contains("TaskStatusPicker("))
        #expect(editorSource.contains("selection: $draft.status"))
        #expect(editorSource.contains(".pickerStyle(.inline)"))
        #expect(editorSource.contains("TaskStatusPickerOption(status: status)"))
        #expect(editorSource.contains("TaskKindPicker") == false)
        #expect(modelsSource.contains("enum TaskNodeKind") == false)
        #expect(englishStrings.contains("editor.task.kind") == false)
    }

    @Test
    func taskCategoryEditorReusesSharedSymbolColorPicker() throws {
        let categoryEditor = try sourceText("timetracker/Features/Tasks/Editor/TaskCategoryEditorViews.swift")
        let symbolPicker = try [
            "timetracker/Features/Tasks/Editor/SymbolPickerViews.swift",
            "timetracker/Features/Tasks/Editor/SymbolColorPickerRow.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")

        #expect(categoryEditor.contains("SymbolColorPickerRow("))
        #expect(categoryEditor.contains("TaskPersistencePolicy.prepareCategory("))
        #expect(categoryEditor.contains("taskCategory.validation"))
        #expect(categoryEditor.contains("validationError != nil"))
        #expect(categoryEditor.contains("Picker(AppStrings.localized(\"taskCategory.symbol\")") == false)
        #expect(categoryEditor.contains("private let symbols") == false)
        #expect(categoryEditor.contains("private var colorGrid") == false)
        #expect(symbolPicker.contains("struct SymbolColorPickerRow"))
        #expect(symbolPicker.contains("SymbolAndColorPicker("))
    }

    @Test
    func symbolColorPickerPushesWithinIOSEditorsInsteadOfStackingSheets() throws {
        let symbolPicker = try sourceText("timetracker/Features/Tasks/Editor/SymbolPickerViews.swift")
        let colorWell = try sourceText(
            "timetracker/Features/Tasks/Editor/SymbolColorWell.swift"
        )
        let project = try sourceText("timetracker.xcodeproj/project.pbxproj")
        let resolved = try sourceText(
            "timetracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        )

        #expect(symbolPicker.contains("NavigationLink {"))
        #expect(symbolPicker.contains(".navigationTitle(AppStrings.localized(\"editor.symbol.title\"))"))
        #expect(symbolPicker.contains(".popover(isPresented: $isPickerPresented)"))
        #expect(symbolPicker.contains(".sheet(isPresented: $isPickerPresented)") == false)
        #expect(symbolPicker.contains("Button(AppStrings.done)") == false)
        #expect(symbolPicker.contains("@FocusState private var isSearchFocused"))
        #expect(symbolPicker.contains(".layoutPriority(1)"))
        #expect(symbolPicker.contains(".scrollDismissesKeyboard(.interactively)"))
        #expect(symbolPicker.contains("SymbolColorWell("))
        #expect(colorWell.contains("import BlossomColorPicker"))
        #expect(colorWell.contains("import BlossomColorPickerCore"))
        #expect(colorWell.contains("ExpandedBlossomView("))
        #expect(colorWell.contains("PetalLayout()"))
        #expect(colorWell.contains("targetDiameter: CGFloat = 44"))
        #expect(colorWell.contains("BlossomConstants.petalSize"))
        #expect(colorWell.contains(".scaleEffect(SymbolBlossomTouchMetrics.scale)"))
        #expect(colorWell.contains("BlossomStyle(") == false)
        #expect(colorWell.contains(".presentationCompactAdaptation(.popover)"))
        #expect(symbolPicker.contains(".onAppear(perform: onOpen)"))
        #expect(project.contains(
            "repositoryURL = \"https://github.com/Lakr233/BlossomColorPicker\";"
        ))
        #expect(project.contains(
            "revision = 9a1ee3df309e37ae271362818dcdfdb072ea9611;"
        ))
        #expect(resolved.contains("\"identity\" : \"blossomcolorpicker\""))
        #expect(resolved.contains(
            "\"revision\" : \"9a1ee3df309e37ae271362818dcdfdb072ea9611\""
        ))
    }

    @Test
    func allTaskEditorsReuseTheSharedSymbolColorPickerLauncher() throws {
        let task = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskEditorInfoSection.swift"
        )
        let category = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskCategoryEditorViews.swift"
        )
        let checklist = try sourceText(
            "timetracker/Features/Tasks/Editor/ChecklistEditorRow.swift"
        )
        let pomodoro = try sourceText(
            "timetracker/Features/Settings/PomodoroSettingsSection.swift"
        )

        #expect(task.contains("SymbolColorPickerRow("))
        #expect(task.contains("pickerAccessibilityIdentifier: \"symbol.picker.open.task\""))
        #expect(task.contains("isTitleFocused = false"))
        #expect(category.contains("SymbolColorPickerRow("))
        #expect(category.contains("pickerAccessibilityIdentifier: \"symbol.picker.open.category\""))
        #expect(category.contains("isTitleFocused = false"))
        #expect(checklist.contains("SymbolColorPickerButton("))
        #expect(checklist.contains("symbol.picker.open.checklist."))
        #expect(checklist.contains("focus.wrappedValue = nil"))
        #expect(pomodoro.contains("SymbolColorPickerButton("))
        #expect(pomodoro.contains("symbol.picker.open.pomodoro."))
        #expect(task.contains("SymbolAndColorPicker(") == false)
        #expect(category.contains("SymbolAndColorPicker(") == false)
        #expect(checklist.contains("SymbolAndColorPicker(") == false)
        #expect(pomodoro.contains("SymbolAndColorPicker(") == false)
        #expect(task.contains("LazyVGrid(") == false)
        #expect(category.contains("LazyVGrid(") == false)
        #expect(checklist.contains("LazyVGrid(") == false)
        #expect(pomodoro.contains("LazyVGrid(") == false)
    }

    @Test
    func taskListShowsStatusBadgesInsteadOfTaskKindBadges() throws {
        let tasksSource = try taskManagementFeatureSource()
        let sharedSource = try [
            "timetracker/SharedUI/Components/ChecklistControls.swift",
            "timetracker/SharedUI/Components/StatusBadges.swift",
            "timetracker/SharedUI/Components/TaskVisuals.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")

        #expect(tasksSource.contains("TaskStatusBadge(status: task.status)"))
        #expect(tasksSource.contains("store.selectTask(task.id, revealInToday: false)") == false)
        #expect(tasksSource.contains("RunningStatusBadge()"))
        #expect(tasksSource.contains("TaskKindBadge") == false)
        #expect(sharedSource.contains("struct TaskKindBadge") == false)
        #expect(sharedSource.contains("struct TaskStatusBadge"))
        #expect(sharedSource.contains("struct RunningStatusBadge"))
    }

    @Test
    func taskRowsOpenOneWorkspaceAndEditActionsUseTheSameDestination() throws {
        let tasksSource = try sourceText("timetracker/Features/Tasks/Management/TasksViews.swift")
        let navigationSource = try sourceText("timetracker/Features/Tasks/Management/TasksNavigationView.swift")
        let rowSource = try taskManagementFeatureSource()
        let actionSource = try sourceText(
            "timetracker/Features/Tasks/Management/TaskRowComponents.swift"
        )
        let detailSource = try taskDetailFeatureSource()
        let desktopRootSource = try sourceText("timetracker/App/RootViews/DesktopRootViews.swift")
        let iosRootSource = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")
        let desktopTasksCase = try #require(
            desktopRootSource.slice(from: "case .tasks:", to: "case .pomodoro:")
        )

        #expect(tasksSource.contains(".accessibilityIdentifier(\"tasks.view\")"))
        #expect(tasksSource.contains("@State private var detailTaskID") == false)
        #expect(tasksSource.contains(".navigationDestination") == false)
        #expect(navigationSource.components(separatedBy: "NavigationStack").count - 1 == 1)
        #expect(navigationSource.contains("@Bindable var bindableStore = store"))
        #expect(navigationSource.contains(".navigationDestination(item: $bindableStore.tasksRoute)"))
        #expect(navigationSource.contains("private var tasksPath") == false)
        #expect(navigationSource.contains("TaskDetailView("))
        #expect(navigationSource.contains("startsEditing: route.startsEditing"))
        #expect(rowSource.contains("Button(action: openTask)"))
        #expect(rowSource.contains(".accessibilityIdentifier(\"tasks.row.\\(task.id.uuidString)\")"))
        #expect(rowSource.contains("store.selectTask(task.id, revealInToday: false)") == false)
        #expect(rowSource.contains("openTaskDetail(task)"))
        #expect(rowSource.contains("openTaskDetail?(task)") == false)
        #expect(rowSource.contains("presentEditTask") == false)
        #expect(actionSource.contains("store.openTaskEditor(task.id)"))
        #expect(actionSource.contains("presentEditTask") == false)
        #expect(desktopTasksCase.contains("TasksNavigationView(store: store)"))
        #expect(desktopTasksCase.contains("NavigationStack") == false)
        #expect(desktopTasksCase.contains("TaskDetailView") == false)
        #expect(iosRootSource.contains("TasksNavigationView(store: store)"))
        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail\")"))
        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail.edit\")"))
        #expect(detailSource.contains("TaskEditorPanel("))
        #expect(detailSource.contains("editorDraft = store.editorDraft(for: task)"))
        #expect(detailSource.contains("presentationRouter.presentEditTask") == false)
    }

    @Test
    func archivedUIRefactorPlanPointsToCurrentSourcesOfTruth() throws {
        let doc = try sourceText("Docs/UIOperationRefactorPlan.md")
        let project = try sourceText("timetracker.xcodeproj/project.pbxproj")
        let infoPlist = try sourceText("timetracker/Info.plist")
        let seedSource = try sourceText("timetracker/App/SeedData.swift")
        let containerSource = try sourceText("timetracker/App/AppModelContainerFactory.swift")

        #expect(doc.contains("# UI and Operation Refactor Plan — Archived"))
        #expect(doc.contains("Status: historical snapshot, superseded"))
        #expect(doc.contains("It is not a current specification"))
        #expect(doc.contains("## Current Sources Of Truth"))
        #expect(doc.contains("[User Guide](UserGuide.md)"))
        #expect(doc.contains("[UI Design Notes](UI-Design.md)"))
        #expect(doc.contains("[Agent Decisions](AgentDecisions.md)"))
        #expect(doc.contains("[Audit-2026-07-14](Audit-2026-07-14.md)"))
        #expect(doc.contains("Simulator sessions started for screenshots or profiling must be shut down"))
        #expect(doc.contains("No May screenshot, generated concept, build command, or test count should be cited as final evidence"))
        #expect(project.contains("TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE = seedIfEmpty;") == false)
        #expect(project.contains("TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE = off;"))
        #expect(project.contains("INFOPLIST_KEY_TimeTrackerAutomaticDemoDataMode"))
        #expect(infoPlist.contains("<key>TimeTrackerAutomaticDemoDataMode</key>"))
        #expect(infoPlist.contains("<string>$(TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE)</string>"))
        #expect(seedSource.contains("case .replaceOnLaunch:"))
        #expect(containerSource.contains("AppDemoDataConfiguration.usesLocalDemoStore"))
        #expect(containerSource.contains("AppDemoDataConfiguration.persistentStoreURL"))
    }

    @Test
    func taskWorkspaceKeepsEvidenceAndEditingInOneDestination() throws {
        let detailSource = try taskDetailFeatureSource()
        let rootSource = try sourceText("timetracker/Features/Tasks/Detail/TaskDetailView.swift")
        let identitySource = try sourceText("timetracker/Features/Tasks/Detail/TaskDetailIdentityViews.swift")

        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail\")"))
        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail.identity\")"))
        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail.actions\")"))
        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail.summary\")"))
        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail.forecast\")"))
        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail.analysis\")"))
        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail.edit\")"))
        #expect(rootSource.contains("@State private var editorDraft: TaskEditorDraft?"))
        #expect(rootSource.contains("TaskEditorPanel("))
        #expect(rootSource.contains("TimelineView") == false)
        #expect(rootSource.contains("canRemainVisible(whileLoading: request)"))
        #expect(rootSource.contains("selectRange("))
        #expect(rootSource.contains("snapshot = resolvedSnapshot"))
        #expect(rootSource.contains("loadedRequest = request"))
        #expect(rootSource.contains("range = selectedRange"))
        #expect(detailSource.contains("TaskDetailActionsView("))
        #expect(detailSource.contains("task.detail.analyticsLoading"))
        #expect(detailSource.contains("task.detail.analysis.range"))
        #expect(detailSource.contains(".contentMargins(.bottom, 16, for: .scrollContent)"))
        #expect(identitySource.contains("Text(task.title)") == false)
        #expect(identitySource.contains("AppStrings.localized(\"task.root\")"))
    }

    @Test
    func taskWorkspaceKeepsAReadableStatusAndUsesTheNativeEditorControl() throws {
        let detailSource = try taskDetailFeatureSource()
        let editorSource = try taskEditorFeatureSource()

        #expect(detailSource.contains("TaskStatusBadge(status: task.status)"))
        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail.identity\")"))
        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail.edit\")"))
        #expect(editorSource.contains("TaskStatusPicker("))
        #expect(editorSource.contains("selection: $draft.status"))
        #expect(editorSource.contains(".pickerStyle(.inline)"))
        #expect(editorSource.contains("TaskDetailStatusSelector") == false)
    }

    @Test
    func taskRowsKeepStatusWithMetadataInsteadOfFloatingAtTrailingEdge() throws {
        let rowSource = try taskManagementFeatureSource()

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
        #expect(settingsSource.contains("try store.jsonExport()"))
        #expect(settingsSource.contains("JSONExportDocument(text: try store.jsonExport())"))
        #expect(settingsSource.contains("defaultFilename: \"time-tracker-export.json\""))
        #expect(settingsSource.contains("Label(AppStrings.localized(\"settings.exportJSON\")") == false)
        #expect(dataSource.contains("title: AppStrings.localized(\"settings.exportJSON\")"))
        #expect(dataSource.contains("systemImage: \"curlybraces.square\""))
    }

    @Test
    func analyticsPageAnswersQuestionsAndKeepsNativeDetailNavigation() throws {
        let analyticsSource = try [
            "timetracker/Features/Analytics/AnalyticsViews.swift",
            "timetracker/Features/Analytics/AnalyticsHomeContent.swift",
            "timetracker/Features/Analytics/AnalyticsCategoryDetailView.swift",
            "timetracker/Features/Analytics/AnalyticsCategoryDetailContent.swift",
            "timetracker/Features/Analytics/AnalyticsCategory.swift",
            "timetracker/Features/Analytics/AnalyticsDetailListViews.swift",
            "timetracker/Features/Analytics/AnalyticsMetricListViews.swift",
            "timetracker/Features/Analytics/AnalyticsOverviewRows.swift",
            "timetracker/Features/Analytics/AnalyticsPeriodSection.swift",
            "timetracker/Features/Analytics/AnalyticsPeriodSelectionViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsGroupBreakdownViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsOverlapViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsQualityViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsTrendViews.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
        let modelsSource = try analyticsReadModelSource()
        let englishStrings = try sourceText("timetracker/en.lproj/Localizable.strings")
        let simplifiedStrings = try sourceText("timetracker/zh-Hans.lproj/Localizable.strings")
        let traditionalStrings = try sourceText("timetracker/zh-Hant.lproj/Localizable.strings")

        #expect(analyticsSource.contains("case decisions"))
        #expect(analyticsSource.contains(".accessibilityIdentifier(\"analytics.decisionSummary\")"))
        #expect(analyticsSource.contains("AnalyticsPeriodSection("))
        #expect(analyticsSource.contains("monthNavigationAnchor: $monthNavigationAnchor"))
        #expect(analyticsSource.contains("range.evaluation("))
        #expect(analyticsSource.contains("await store.loadAnalyticsSnapshot("))
        #expect(analyticsSource.contains("TimelineView") == false)
        #expect(analyticsSource.contains("AnalyticsInsightList(insights: snapshot.insights)"))
        #expect(analyticsSource.contains("AnalyticsQualityContent(quality: snapshot.quality)"))
        #expect(analyticsSource.contains("snapshot.categoryBreakdown"))
        #expect(analyticsSource.contains("NavigationLink(value: category)"))
        #expect(analyticsSource.contains(".navigationDestination(for: AnalyticsCategory.self)"))
        #expect(analyticsSource.contains(".navigationTitle(category.destinationTitle)"))
        #expect(analyticsSource.contains("AnalyticsCategory.questionCategories"))
        #expect(analyticsSource.contains("category.questionTitle"))
        #expect(analyticsSource.contains("category.answerPreview(from: snapshot)"))
        #expect(analyticsSource.contains("category.openLabel"))
        #expect(analyticsSource.contains("guard snapshot.overview.grossSeconds > 0"))
        #expect(analyticsSource.contains("if snapshot.overview.grossSeconds > 0"))
        #expect(modelsSource.contains("struct AnalyticsInsight"))
        #expect(modelsSource.contains("struct TaskAnalyticsSnapshot"))
        #expect(englishStrings.contains("\"analytics.decisions.title\""))
        #expect(englishStrings.contains("\"analytics.quality.title\""))
        #expect(englishStrings.contains("\"analytics.question.overview\""))
        #expect(englishStrings.contains("\"analytics.question.time\""))
        #expect(englishStrings.contains("\"analytics.question.tasks\""))
        #expect(englishStrings.contains("\"analytics.question.pomodoro\""))
        #expect(englishStrings.contains("\"analytics.question.decisions\""))
        #expect(englishStrings.contains("\"analytics.question.quality\""))
        #expect(englishStrings.contains("\"analytics.question.openFormat\""))
        #expect(englishStrings.contains("\"analytics.question.answer.noRecordedTime\""))
        #expect(
            englishStrings.contains(
                "\"analytics.questions.subtitle\" = \"Choose a question to see the explanation and supporting details.\""
            )
        )
        #expect(
            simplifiedStrings.contains(
                "\"analytics.questions.subtitle\" = \"选择一个问题，查看对应的说明和详细数据。\""
            )
        )
        #expect(
            traditionalStrings.contains(
                "\"analytics.questions.subtitle\" = \"選擇一個問題，查看對應的說明和詳細資料。\""
            )
        )
        #expect(englishStrings.contains("\"analytics.summary.grossLabel\""))
        #expect(englishStrings.contains("\"analytics.summary.wallLabel\""))
        #expect(englishStrings.contains("\"analytics.summary.emptyTitle\""))
        #expect(englishStrings.contains("\"analytics.summary.emptyMessage\""))
        #expect(
            englishStrings.contains(
                "\"analytics.summary.dailyAverage\" = \"Average per Tracked Day\""
            )
        )
        #expect(simplifiedStrings.contains("\"analytics.range.week\" = \"周\""))
        #expect(simplifiedStrings.contains("\"analytics.range.month\" = \"月\""))
        #expect(traditionalStrings.contains("\"analytics.range.week\" = \"週\""))
        #expect(traditionalStrings.contains("\"analytics.range.month\" = \"月\""))
    }

    @Test
    func analyticsMakesSelectedPeriodAndMetricMeaningsExplicit() throws {
        let analyticsSource = try [
            "timetracker/Features/Analytics/AnalyticsViews.swift",
            "timetracker/Features/Analytics/AnalyticsHomeContent.swift",
            "timetracker/Features/Analytics/AnalyticsCategoryDetailView.swift",
            "timetracker/Features/Analytics/AnalyticsCategoryDetailContent.swift",
            "timetracker/Features/Analytics/AnalyticsDetailListViews.swift",
            "timetracker/Features/Analytics/AnalyticsPeriodSection.swift",
            "timetracker/Features/Analytics/AnalyticsPeriodSelectionViews.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
        let englishStrings = try sourceText("timetracker/en.lproj/Localizable.strings")

        #expect(analyticsSource.contains("AnalyticsPeriodSection("))
        #expect(analyticsSource.contains("monthNavigationAnchor: $monthNavigationAnchor"))
        #expect(analyticsSource.contains("AnalyticsGlossaryList()"))
        #expect(englishStrings.contains("\"analytics.glossary.gross\""))
        #expect(englishStrings.contains("\"analytics.glossary.wall\""))
        #expect(englishStrings.contains("\"analytics.glossary.overlap\""))

        let focusedSections = try [
            "timetracker/Features/Analytics/Sections/AnalyticsGroupBreakdownViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsOverlapViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsQualityViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsTrendViews.swift"
        ].map(sourceText).joined(separator: "\n")
        #expect(focusedSections.contains("AnalyticsChartCard(") == false)

        let uiTestSource = try sourceText("timetrackerUITests/timetrackerUITests.swift")
        #expect(uiTestSource.contains("analyticsIsReady(in app: XCUIApplication)"))
        #expect(uiTestSource.contains("analytics.view"))
        #expect(uiTestSource.contains("testAnalyticsFinalCategoryScrollsAboveSystemChrome"))
        #expect(uiTestSource.contains("analytics.category.overview"))
        #expect(analyticsSource.contains("analytics.category.\\(category.rawValue)"))
        #expect(analyticsSource.contains("AnalyticsCategory.questionCategories"))
        #expect(englishStrings.contains("\"analytics.questions.title\""))
        #expect(englishStrings.contains("\"analytics.questions.subtitle\""))

        let detailSectionSource = try sourceText(
            "timetracker/Features/Analytics/AnalyticsMetricListViews.swift"
        )
        let subtitleIndex = try #require(detailSectionSource.range(of: "Text(subtitle)"))
        let contentIndex = try #require(detailSectionSource.range(of: "\n                content"))
        #expect(subtitleIndex.lowerBound < contentIndex.lowerBound)
        #expect(detailSectionSource.contains("} footer: {") == false)
    }

    @Test
    func analyticsAvoidsUnsupportedAndDuplicateReviewSignals() throws {
        let insightSource = try sourceText(
            "timetracker/Stores/Domains/AnalyticsStore+Insights.swift"
        )
        let qualitySource = try sourceText(
            "timetracker/Features/Analytics/Sections/AnalyticsQualityViews.swift"
        )
        let englishStrings = try sourceText("timetracker/en.lproj/Localizable.strings")

        #expect(insightSource.contains("\"quality-steady\"") == false)
        #expect(insightSource.contains("\"next-action\"") == false)
        #expect(qualitySource.contains("analytics.quality.longest") == false)
        #expect(englishStrings.contains("\"analytics.insight.quality.steadyBody\"") == false)
        #expect(englishStrings.contains("\"analytics.insight.next.title\"") == false)
        #expect(englishStrings.contains("\"analytics.quality.longest\"") == false)
    }

    @Test
    func analyticsOverlapSeparatesWallWindowsFromConservedExcess() throws {
        let modelSource = try analyticsReadModelSource()
        let storeSource = try [
            "timetracker/Stores/Domains/AnalyticsStore+Overlap.swift",
            "timetracker/Stores/Domains/AnalyticsStore+OverlapMaterialization.swift",
            "timetracker/Stores/Domains/AnalyticsStore+OverlapParticipants.swift",
            "timetracker/Stores/Domains/AnalyticsStore+OverlapSweep.swift"
        ].map(sourceText).joined(separator: "\n")
        let viewSource = try [
            "timetracker/Features/Analytics/Sections/AnalyticsOverlapViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsOverlapRow.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
        let englishStrings = try sourceText("timetracker/en.lproj/Localizable.strings")

        #expect(modelSource.contains("struct OverlapAnalyticsParticipant: Identifiable"))
        #expect(modelSource.contains("let concurrentSegmentCount: Int"))
        #expect(modelSource.contains("let wallDurationSeconds: Int"))
        #expect(modelSource.contains("let excessDurationSeconds: Int"))
        #expect(storeSource.contains("window.concurrentSegmentCount - 1"))
        #expect(storeSource.contains("expectedExcessSeconds: overview(items: canonicalItems).overlapSeconds"))
        #expect(storeSource.contains("taskIDs: Set<UUID>"))
        #expect(viewSource.contains("AnalyticsOverlapFormatting.duration(overlap.excessDurationSeconds"))
        #expect(viewSource.contains("seconds > 0, seconds < 60"))
        #expect(viewSource.contains("DurationFormatter.spoken(seconds"))
        #expect(viewSource.contains("analytics.overlap.hiddenSummary"))
        #expect(viewSource.contains("analytics.overlap.excess.label"))
        #expect(viewSource.contains("firstTitle") == false)
        #expect(englishStrings.contains("\"analytics.overlap.oneMoreParticipantFormat\""))
        #expect(englishStrings.contains("\"analytics.overlap.concurrencyFormat\""))
        #expect(englishStrings.contains("\"analytics.overlap.concurrencyOneTaskFormat\""))
        #expect(englishStrings.contains("\"analytics.overlap.hiddenSummaryFormat\""))
        #expect(englishStrings.contains("\"analytics.overlap.hiddenSummaryOneWindowFormat\""))
    }

    @Test
    func analyticsUsesAccessibilitySpecificRowsAndPeriodControls() throws {
        let analyticsSource = try [
            "timetracker/Features/Analytics/AnalyticsViews.swift",
            "timetracker/Features/Analytics/AnalyticsHomeContent.swift",
            "timetracker/Features/Analytics/AnalyticsCategoryDetailView.swift",
            "timetracker/Features/Analytics/AnalyticsOverviewRows.swift",
            "timetracker/Features/Analytics/AnalyticsMetricListViews.swift",
            "timetracker/Features/Analytics/AnalyticsPeriodSection.swift",
            "timetracker/Features/Analytics/AnalyticsPeriodSelectionViews.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")

        #expect(analyticsSource.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(analyticsSource.contains(".pickerStyle(.menu)"))
        #expect(analyticsSource.contains("VStack(alignment: .leading, spacing: 10)"))
        #expect(analyticsSource.contains(".frame(minWidth: 44, minHeight: 44)"))
        #expect(analyticsSource.contains(".contentMargins("))
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
        let managementSource = try taskManagementFeatureSource()
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarTaskTreeViews.swift")

        #expect(taskRowSource.contains("struct TaskRowSwipeActions"))
        #expect(taskRowSource.contains("enum TaskRowSwipeLabelStyle"))
        #expect(taskRowSource.contains("case iconOnly"))
        #expect(taskRowSource.contains("let requestDelete: () -> Void"))
        #expect(taskRowSource.contains("@State private var isDeleteConfirmationPresented") == false)
        #expect(taskRowSource.contains(".confirmationDialog(") == false)
        #expect(taskRowSource.contains("requestDelete()"))
        #expect(taskRowSource.contains("Label(AppStrings.delete, systemImage: \"trash\")"))
        #expect(taskRowSource.contains("task.action.softDelete") == false)
        #expect(managementSource.contains("requestDelete: { isDeleteConfirmationPresented = true }"))
        #expect(sidebarSource.contains("requestDelete: { isDeleteConfirmationPresented = true }"))
        #expect(managementSource.components(separatedBy: ".confirmationDialog(").count - 1 == 1)
        #expect(sidebarSource.components(separatedBy: ".confirmationDialog(").count - 1 == 1)
    }

    @Test
    func taskCategoriesExposeAccessibleActionsAndNativeDeleteConfirmation() throws {
        let tasksSource = try sourceText("timetracker/Features/Tasks/Management/TasksViews.swift")
        let categorySource = try sourceText("timetracker/SharedUI/Components/TaskCategoryViews.swift")
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarViews.swift")
        let editorSource = try sourceText("timetracker/Features/Tasks/Editor/TaskCategoryEditorViews.swift")

        #expect(categorySource.contains(".accessibilityIdentifier(\"tasks.category.actions.\\(section.id)\")"))
        #expect(categorySource.contains("AppStrings.localized(\"common.more\")"))
        #expect(categorySource.contains("Label(AppStrings.localized(\"tasks.newRoot\"), systemImage: \"plus\")"))
        #expect(categorySource.contains("Label(AppStrings.localized(\"taskCategory.edit\"), systemImage: \"slider.horizontal.3\")"))
        #expect(categorySource.contains("Button(role: .destructive, action: deleteCategory)"))
        #expect(categorySource.contains("Label(AppStrings.localized(\"taskCategory.delete\"), systemImage: \"trash\")"))
        #expect(tasksSource.contains("addTask: newRootTaskAction(for: section)"))
        #expect(tasksSource.contains("editCategory: editAction(for: section)"))
        #expect(tasksSource.contains("deleteCategory: deleteAction(for: section)"))
        #expect(sidebarSource.contains("showsBottomDivider: true"))
        #expect(editorSource.contains(".confirmationDialog("))
        #expect(editorSource.contains("Button(AppStrings.localized(\"taskCategory.delete\"), role: .destructive"))
    }

    @Test
    func taskDetailExposesDiscoverableActionsAndUsesSystemBackNavigation() throws {
        let detailSource = try taskDetailFeatureSource()
        let actionSource = try sourceText("timetracker/Features/Tasks/Management/TaskRowComponents.swift")
        let contextMenuSource = actionSource.components(
            separatedBy: "enum TaskRowSwipeLabelStyle"
        ).first ?? actionSource

        #expect(detailSource.contains(".accessibilityIdentifier(\"task.detail.more\")"))
        #expect(detailSource.contains("TaskContextMenu("))
        #expect(detailSource.contains("editTask: { beginEditing(task) }"))
        #expect(detailSource.contains("task.delete.confirm.message"))
        #expect(detailSource.contains("task.detail.back") == false)
        #expect(detailSource.contains("store.closeTaskDetailNavigation()") == false)
        #expect(detailSource.contains("@Environment(\\.dismiss)") == false)
        #expect(detailSource.contains("dismiss()") == false)
        #expect(contextMenuSource.contains("if let activeSegment"))
        #expect(contextMenuSource.contains("store.stop(segment: activeSegment)"))
        #expect(contextMenuSource.contains("Button(action: editTask)"))
        #expect(contextMenuSource.contains("store.openTaskEditor(task.id)") == false)
    }

    @Test
    func taskEditorsBoundRepeatedWorkToRelevantStateChanges() throws {
        let editor = try taskEditorFeatureSource()
        let symbols = try sourceText("timetracker/Features/Tasks/Editor/SymbolPickerViews.swift")

        #expect(editor.contains("@State private var parentCandidates: [TaskNode]"))
        #expect(editor.contains("Self.parentCandidates(for: initialDraft, store: store)"))
        #expect(editor.contains("parentCandidates = Self.parentCandidates(for: latestDraft, store: store)"))
        #expect(editor.contains("draft.checklistItems.indices.sorted") == false)
        #expect(editor.contains("rowPlacements.map") == false)
        #expect(symbols.contains("@State private var filteredSymbols: [String]"))
        #expect(symbols.contains(".onChange(of: searchText, initial: true)"))
        #expect(symbols.contains("ContentUnavailableView.search(text: searchText)"))
        #expect(symbols.contains("editor.symbol.symbolValue"))
    }

    @Test
    func staleTaskEditorOffersExplicitReloadWithoutSilentlyDiscardingTheDraft() throws {
        let editor = try sourceText("timetracker/Features/Tasks/Editor/TaskEditorViews.swift")
        let store = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+TaskCommands.swift")

        #expect(store.contains("func saveTaskDraftResult("))
        #expect(store.contains("return .stale"))
        #expect(editor.contains("pendingReloadDraft = store.editorDraft(for: latestTask)"))
        #expect(editor.contains("task.editor.stale.reloadMessage"))
        #expect(editor.contains("role: .destructive"))
        #expect(editor.contains("sessionBaseline = latestDraft"))
        #expect(editor.contains("parentCandidates = Self.parentCandidates(for: latestDraft, store: store)"))
        #expect(editor.contains("case .stale:"))
    }

    @Test
    func taskEditorKeepsUnavailableCurrentParentsVisibleWhileAllowingRecoveryMoves() throws {
        let editor = try sourceText("timetracker/Features/Tasks/Editor/TaskEditorViews.swift")
        let info = try sourceText("timetracker/Features/Tasks/Editor/TaskEditorInfoSection.swift")
        let hierarchy = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskEditorHierarchyRows.swift"
        )
        let readModels = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+TaskReadModels.swift")

        #expect(editor.contains("candidates.append(currentParent)"))
        #expect(editor.contains("store.isTaskVisible(currentParent)") == false)
        #expect(info.contains("store.parentChangeBlocker(for: $0)"))
        #expect(info.contains("store.taskIdentityPresentation(for: task).fullPath"))
        #expect(hierarchy.contains("task.parent.currentUnavailableFormat"))
        #expect(hierarchy.contains("task.parent.unavailableFormat"))
        #expect(hierarchy.contains("task.parent.currentMissing"))
        #expect(hierarchy.contains("String(repeating: \"  \"") == false)
        #expect(info.contains("!store.isTaskAvailableForTracking(originalTask)") == false)
        #expect(readModels.contains("func parentChangeBlocker(for task: TaskNode)"))
    }

    @Test
    func taskEditorShowsAccessiblePersistenceErrorsBesideFieldsAndBlocksSave() throws {
        let editor = try sourceText("timetracker/Features/Tasks/Editor/TaskEditorViews.swift")
        let components = try sourceText("timetracker/Features/Tasks/Editor/TaskEditorComponents.swift")
        let info = try sourceText("timetracker/Features/Tasks/Editor/TaskEditorInfoSection.swift")
        let notes = try sourceText("timetracker/Features/Tasks/Editor/TaskNotesEditorSection.swift")
        let policy = try sourceText("timetracker/Services/Tasks/TaskPersistencePolicy.swift")

        #expect(editor.contains("let validation = TaskEditorValidation("))
        #expect(editor.contains(".disabled(!canSave(validation))"))
        #expect(components.contains("struct TaskEditorValidation: Equatable"))
        #expect(components.contains("struct TaskEditorInlineValidationMessage: View"))
        #expect(components.contains(".accessibilityLabel(error.localizedDescription)"))
        #expect(components.contains(".accessibilityAddTraits(.isStaticText)"))
        #expect(info.contains("task.editor.title.error"))
        #expect(info.contains("task.editor.symbol.error"))
        #expect(info.contains("task.editor.color.error"))
        #expect(info.contains(".accessibilityHint(visibleTitleError?.localizedDescription ?? \"\")"))
        #expect(info.contains(".onChange(of: draft.title)"))
        #expect(notes.contains("task.editor.notes.error"))
        #expect(notes.contains(".accessibilityHint(validationError?.localizedDescription ?? \"\")"))
        #expect(policy.contains("static func taskTitleValidationError(for title: String)"))
        #expect(policy.contains("static func taskNotesValidationError(for notes: String?)"))
        #expect(policy.contains("Int64(actual)"))
        #expect(policy.contains("Int64(maximum)"))
    }

    @Test
    func analyticsHomeExposesPeriodNavigationAndChartsExposeReadableFallbacks() throws {
        let analytics = try [
            "timetracker/Features/Analytics/AnalyticsViews.swift",
            "timetracker/Features/Analytics/AnalyticsHomeContent.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
        let distribution = try sourceText("timetracker/Features/Analytics/Sections/AnalyticsDistributionViews.swift")
        let trends = try sourceText("timetracker/Features/Analytics/Sections/AnalyticsTrendViews.swift")
        let timeline = try [
            "timetracker/Features/Analytics/Timeline/AnalyticsTimelineViews.swift",
            "timetracker/SharedUI/Components/TimelineChart.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")

        #expect(analytics.contains("AnalyticsPeriodSection("))
        #expect(analytics.contains("monthNavigationAnchor: $monthNavigationAnchor"))
        #expect(distribution.contains("if displayedSlices.isEmpty"))
        #expect(distribution.contains(".accessibilityLabel(slice.accessibilityTitle)"))
        #expect(trends.contains("daily.allSatisfy"))
        #expect(trends.contains("analytics.chart.day"))
        #expect(trends.contains("point.wallMinutes"))
        #expect(trends.contains("point.grossMinutes"))
        #expect(trends.contains(".chartForegroundStyleScale"))
        #expect(trends.contains(".chartLegend(position: .bottom"))
        #expect(timeline.contains("horizontalSizeClass == .compact"))
        #expect(timeline.contains("UIDevice.current.userInterfaceIdiom") == false)
    }

    private func taskEditorFeatureSource() throws -> String {
        try [
            "timetracker/Features/Tasks/Editor/TaskEditorViews.swift",
            "timetracker/Features/Tasks/Editor/TaskEditorComponents.swift",
            "timetracker/Features/Tasks/Editor/TaskEditorInfoSection.swift",
            "timetracker/Features/Tasks/Editor/TaskEditorHierarchyRows.swift",
            "timetracker/Features/Tasks/Editor/TaskStatusPicker.swift",
            "timetracker/Features/Tasks/Editor/TaskPlanEditorSection.swift",
            "timetracker/Features/Tasks/Editor/TaskNotesEditorSection.swift",
            "timetracker/Features/Tasks/Editor/TaskChecklistEditorSection.swift",
            "timetracker/Features/Tasks/Editor/ChecklistEditorRow.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
    }

    private func segmentEditorFeatureSource() throws -> String {
        try [
            "timetracker/Features/Ledger/SegmentEditorSheet.swift",
            "timetracker/Features/Ledger/SegmentEditorViews.swift",
            "timetracker/Features/Ledger/SegmentEditorPanel+Validation.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
    }

    private func analyticsReadModelSource() throws -> String {
        try [
            "timetracker/Models/AnalyticsPeriodModels.swift",
            "timetracker/Models/AnalyticsSummaryReadModels.swift",
            "timetracker/Models/AnalyticsTimelineReadModels.swift",
            "timetracker/Models/TaskAnalyticsReadModels.swift",
            "timetracker/Models/AnalyticsOverlapReadModels.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
    }

    private func taskManagementFeatureSource() throws -> String {
        try [
            "timetracker/Features/Tasks/Management/TaskManagementRowViews.swift",
            "timetracker/Features/Tasks/Management/TaskManagementRowContent.swift",
            "timetracker/Features/Tasks/Management/TaskManagementAccessibility.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
    }

    private func taskDetailFeatureSource() throws -> String {
        try [
            "timetracker/Features/Tasks/Detail/TaskDetailView.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailContentView.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailActionsView.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailNavigationViews.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailIdentityViews.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailChecklistViews.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailOverviewViews.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailAnalyticsViews.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailRecordViews.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
    }
}
