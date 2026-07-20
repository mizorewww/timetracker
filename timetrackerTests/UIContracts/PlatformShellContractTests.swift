import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct PlatformShellContractTests {
    @Test
    func iosRootSelectsItsShellFromStableInterfaceIdiom() throws {
        let source = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")
        let iosRoot = try #require(source.slice(from: "struct iOSRootView", to: "struct PhoneRootView"))

        #expect(iosRoot.contains("RootLayoutPolicy"))
        #expect(iosRoot.contains("UIDevice.current.userInterfaceIdiom"))
        #expect(iosRoot.contains("switch layoutPolicy.shell"))
        #expect(iosRoot.contains("@Environment(\\.horizontalSizeClass)") == false)
        #expect(iosRoot.contains("horizontalSizeClass") == false)
    }

    @Test
    func ipadSplitViewPreservesSelectionAndLetsTheSystemAdaptColumns() throws {
        let ipadRoot = try sourceText(
            "timetracker/App/RootViews/iPadRootView.swift"
        )

        #expect(ipadRoot.contains("preferredCompactColumn: $preferredCompactColumn"))
        #expect(ipadRoot.contains("SidebarView(store: store) {"))
        #expect(ipadRoot.contains("preferredCompactColumn = .detail"))
        #expect(ipadRoot.contains(".onChange(of: store.desktopDestination)"))
        #expect(ipadRoot.contains("SidebarRevealButton") == false)
        #expect(ipadRoot.contains("ToolbarItem(placement: .topBarLeading)") == false)
    }

    @Test
    func todayUsesTheNativeCollapsingNavigationTitle() throws {
        let source = try sourceText("timetracker/Features/Home/HomeViews.swift")

        #expect(source.contains(".navigationTitle(AppStrings.today)"))
        #expect(source.contains(".navigationBarTitleDisplayMode(.large)"))
        #expect(source.contains("struct HeaderBar") == false)
        #expect(source.contains("HeaderBar()") == false)
        #expect(source.contains("Text(.app(\"home.subtitle\"))"))
        #expect(source.contains(".onGeometryChange(for: CGFloat.self)"))
        #expect(source.contains("GeometryReader") == false)
    }

    @Test
    @MainActor
    func taskTreeDisclosureSlotsOnlyIndentRowsThatNeedHierarchySpace() throws {
        #expect(TaskTreeDisclosureSlot(depth: 0, hasChildren: true) == .control)
        #expect(TaskTreeDisclosureSlot(depth: 0, hasChildren: false) == .none)
        #expect(TaskTreeDisclosureSlot(depth: 1, hasChildren: true) == .control)
        #expect(TaskTreeDisclosureSlot(depth: 1, hasChildren: false) == .reserved)

        let sidebar = try sourceText(
            "timetracker/Features/Sidebar/SidebarTaskTreeViews.swift"
        )
        let tasks = try sourceText(
            "timetracker/Features/Tasks/Management/TaskManagementRowViews.swift"
        )
        let hierarchyPicker = try sourceText(
            "timetracker/SharedUI/Components/TaskHierarchyPickerRows.swift"
        )

        #expect(sidebar.contains(
            "TaskTreeDisclosureSlot(depth: row.depth, hasChildren: row.hasChildren)"
        ))
        #expect(tasks.contains(
            "TaskTreeDisclosureSlot(depth: treeDepth, hasChildren: childCount > 0)"
        ))
        #expect(hierarchyPicker.contains(
            "TaskTreeDisclosureSlot(depth: item.depth, hasChildren: item.hasChildren)"
        ))
        #expect(sidebar.contains(
            ".padding(.leading, CGFloat(min(row.depth, 6)) * 14)"
        ))
        #expect(sidebar.contains(
            ".accessibilityIdentifier(\"sidebar.disclosure.\\(task.id.uuidString)\")"
        ))
    }

    @Test
    func uiAuditCanNavigateWhenTheSystemStartsWithACollapsedIPadSidebar() throws {
        let source = try sourceText("timetrackerUITests/timetrackerUITests.swift")

        #expect(source.contains("openCollapsedSidebarDestination(sidebarIdentifier, in: app)"))
        #expect(source.contains("app.descendants(matching: .any)[\"sidebar.show\"]"))
        #expect(source.contains("app.buttons[\"Show Sidebar\"]"))
        #expect(source.contains("destination.waitForExistence(timeout: 3)"))
        #expect(source.contains("app.descendants(matching: .any)[\"ipad.splitNavigation\"]"))
        #expect(source.contains("The iPad sidebar must expose seeded tasks"))
        #expect(source.contains("Sidebar is not visible in this size class.") == false)
        #expect(source.contains("XCUIDevice.shared.orientation = .landscapeLeft"))
        #expect(source.contains("ipad-sidebar-task-detail-restored"))
        #expect(source.contains("XCUIScreen.main.screenshot()"))
    }

    @Test
    func sidebarTaskIdentifierLivesOnTheMergedAccessibilityElement() throws {
        let source = try sourceText("timetracker/Features/Sidebar/SidebarTaskTreeViews.swift")
        let content = try #require(source.slice(from: "private var taskContent", to: "private func accessibilityValue"))

        let merge = try #require(content.range(of: ".accessibilityElement(children: .ignore)"))
        let identifier = try #require(content.range(of: ".accessibilityIdentifier(\"sidebar.task."))
        #expect(identifier.lowerBound > merge.lowerBound)
    }

    @Test
    func sidebarUsesStableRowsAndTracksProgrammaticNavigation() throws {
        let source = try [
            "timetracker/Features/Sidebar/SidebarViews.swift",
            "timetracker/Features/Sidebar/SidebarTaskTreeViews.swift"
        ].map(sourceText).joined(separator: "\n")

        #expect(source.contains("SidebarTaskTreeRowContainer("))
        #expect(source.contains(".tag(SidebarSelection.task(row.taskID))"))
        #expect(source.contains("List(selection: selectionBinding)"))
        #expect(source.contains(".onChange(of: store.tasksRoute)"))
        #expect(source.contains(".onChange(of: store.taskTreeReadIndexRevision)"))
        #expect(source.contains("store.isTaskDetailRouteValid(taskID)"))
        #expect(source.contains("@State private var selection") == false)
        #expect(source.contains("sidebar.task.\\(task.id.uuidString)"))
        #expect(source.contains("let onNavigate: () -> Void"))
        #expect(source.contains("44"))
        #expect(source.contains("24"))
        #expect(source.contains("SettingsLink") == false)
    }

    @Test
    func macWindowUsesFocusedStoreCommandsAndRoutesSettingsToItsScene() throws {
        let appSource = try sourceText("timetracker/App/timetrackerApp.swift")
        let appDelegateSource = try sourceText("timetracker/App/TimeTrackerAppDelegate.swift")
        let rootSource = try sourceText("timetracker/App/RootViews/DesktopRootViews.swift")
        let commandSource = try sourceText("timetracker/App/TimeTrackerCommands.swift")
        let focusedValueSource = try sourceText("timetracker/App/FocusedSceneActions.swift")

        #expect(appSource.contains(".frame(minWidth: 680, minHeight: 500)"))
        #expect(appSource.contains("Window(AppStrings.localized(\"app.name\"), id: \"main\")"))
        #expect(appSource.components(separatedBy: "WindowGroup {").count - 1 == 1)
        #expect(appSource.contains("static let applicationStore = TimeTrackerStore()"))
        #expect(appSource.contains(
            "@State private var store = timetrackerApp.applicationStore"
        ))
        #expect(appDelegateSource.contains(".frame(minWidth: 680, minHeight: 500)"))
        #expect(appDelegateSource.contains(
            "ContentView(store: timetrackerApp.applicationStore)"
        ))
        #expect(appDelegateSource.contains(
            ".modelContainer(timetrackerApp.applicationModelContainer)"
        ))
        #expect(appDelegateSource.contains("makeUITestModelContainer()") == false)
        #expect(appSource.contains(".windowToolbarStyle(.unified)"))
        #expect(appSource.contains("SidebarCommands()"))
        #expect(rootSource.contains("NavigationSplitView(columnVisibility: $columnVisibility)"))
        #expect(rootSource.contains(".focusedSceneValue(\\.timeTrackerStore, store)"))
        #expect(rootSource.contains("@Environment(\\.openSettings)"))
        #expect(rootSource.contains("routeSettingsDestination"))
        #expect(commandSource.contains("@FocusedValue(\\.timeTrackerStore) private var store"))
        #expect(commandSource.contains("@FocusedObject") == false)
        #expect(focusedValueSource.contains("@Entry var timeTrackerStore: TimeTrackerStore?"))
        #expect(focusedValueSource.contains("typealias Value = TimeTrackerStore") == false)
        #expect(focusedValueSource.contains("() -> Void") == false)
        #expect(commandSource.contains("CommandMenu(AppStrings.appName)") == false)
    }

    @Test
    func macSettingsKeepsItsCategorySidebarVisibleWithoutAToggle() throws {
        let source = try sourceText(
            "timetracker/Features/Settings/SettingsViews.swift"
        )

        #expect(source.contains(
            "NavigationSplitView(columnVisibility: fixedSettingsColumnVisibility)"
        ))
        #expect(source.contains("private var fixedSettingsColumnVisibility"))
        #expect(source.contains("get: { .all }"))
        #expect(source.contains("set: { _ in }"))
        #expect(source.contains(".toolbar(removing: .sidebarToggle)"))
    }

    @Test
    func macCommandsExposeCreationTaskLifecycleNavigationAndRefresh() throws {
        let source = try sourceText("timetracker/App/TimeTrackerCommands.swift")

        #expect(source.contains("CommandGroup(replacing: .newItem)"))
        #expect(source.contains("CommandMenu(AppStrings.localized(\"menu.task\"))"))
        #expect(source.contains("Button(AppStrings.localized(\"menu.archiveSelectedTask\"))"))
        #expect(source.contains("store.archiveTaskProtectingUnsavedChanges(selectedTask.id)"))
        #expect(source.contains("private var canArchiveSelectedTask: Bool"))
        #expect(source.contains("store.isTaskVisible(selectedTask)"))
        #expect(source.contains("store.hasActiveTimer(inTaskSubtree: selectedTask.id)"))
        #expect(source.contains("CommandGroup(after: .sidebar)"))
        #expect(source.contains("destinationButton(.today, key: \"1\")"))
        #expect(source.contains("destinationButton(.analytics, key: \"5\")"))
        #expect(source.contains("store?.closeTaskDetailNavigation()"))
        #expect(source.contains(".keyboardShortcut(\"r\", modifiers: [.command])"))
    }

    @Test
    func platformShellAvoidsOptingIntoLiquidGlassWithoutAProductDecision() throws {
        let source = try [
            "timetracker/App/RootViews/DesktopRootViews.swift",
            "timetracker/App/RootViews/iOSRootViews.swift",
            "timetracker/Features/Sidebar/SidebarViews.swift",
            "timetracker/Features/Sidebar/SidebarTaskTreeViews.swift",
            "timetracker/App/TimeTrackerCommands.swift",
            "timetracker/App/timetrackerApp.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")

        #expect(source.contains(".glassEffect(") == false)
        #expect(source.contains("GlassEffectContainer") == false)
        #expect(source.contains(".buttonStyle(.glass") == false)
    }
}
