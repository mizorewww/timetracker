import Foundation
import Testing

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
        let source = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")
        let ipadRoot = try #require(source.slice(from: "struct iPadRootView", to: "#endif"))

        #expect(ipadRoot.contains("preferredCompactColumn: $preferredCompactColumn"))
        #expect(ipadRoot.contains("SidebarView(store: store) {"))
        #expect(ipadRoot.contains("preferredCompactColumn = .detail"))
        #expect(ipadRoot.contains(".onChange(of: store.desktopDestination)"))
        #expect(ipadRoot.contains("SidebarRevealButton") == false)
        #expect(ipadRoot.contains("ToolbarItem(placement: .topBarLeading)") == false)
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
        #expect(appDelegateSource.contains(".frame(minWidth: 680, minHeight: 500)"))
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
    func macCommandsExposeCreationTrackingNavigationAndRefreshShortcuts() throws {
        let source = try sourceText("timetracker/App/TimeTrackerCommands.swift")

        #expect(source.contains("CommandGroup(replacing: .newItem)"))
        #expect(source.contains("CommandGroup(after: .sidebar)"))
        #expect(source.contains("destinationButton(.today, key: \"1\")"))
        #expect(source.contains("destinationButton(.analytics, key: \"5\")"))
        #expect(source.contains("store?.closeTaskDetailNavigation()"))
        #expect(source.contains(".keyboardShortcut(\"r\", modifiers: [.command])"))
        #expect(source.contains(".disabled(store?.selectedTask == nil)"))
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
