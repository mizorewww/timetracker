import Foundation
import Testing

@Suite(.serialized)
struct SharedComponentsContractTests {
    @Test
    func ipadSidebarButtonDoesNotOpenInspector() throws {
        let ipadSource = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")

        #expect(ipadSource.contains("if columnVisibility == .detailOnly"))
        #expect(ipadSource.contains("columnVisibility = .all"))
        #expect(ipadSource.contains("isInspectorPresented = inspectorIsRelevant") == false)
    }

    @Test
    func sectionHeadersUseSharedComponentAcrossSettingsAndAnalytics() throws {
        let sharedSource = try sourceText("timetracker/SharedUI/Components/SectionHeaders.swift")
        let settingsSupportSource = try sourceText("timetracker/Features/Settings/Support/SettingsSupportViews.swift")
        let metricSource = try sourceText("timetracker/SharedUI/Components/MetricCards.swift")

        #expect(sharedSource.contains("struct AppSectionHeader"))
        #expect(sharedSource.contains("struct SettingsHeader"))
        #expect(sharedSource.contains("struct SectionTitle"))
        #expect(settingsSupportSource.contains("struct SettingsHeader") == false)
        #expect(metricSource.contains("AppSectionHeader(title: title"))
    }

    @Test
    func primaryActionLabelsUseSharedComponentAcrossHomeAndInspector() throws {
        let sharedSource = try sourceText("timetracker/SharedUI/Components/ActionControls.swift")
        let homeSource = try sourceText("timetracker/Features/Home/Controls/HomeActionsViews.swift")
        let inspectorSource = try sourceText("timetracker/Features/Inspector/Sections/InspectorActionViews.swift")

        #expect(sharedSource.contains("struct AppActionLabel"))
        #expect(sharedSource.contains(".minimumScaleFactor(0.78)"))
        #expect(homeSource.contains("AppActionLabel(title: AppStrings.startTimer"))
        #expect(homeSource.contains("private func actionLabel") == false)
        #expect(inspectorSource.contains("AppActionLabel(title: AppStrings.localized(\"task.action.startTimer\")"))
        #expect(inspectorSource.contains("Label(AppStrings.localized(\"timer.action.pause\")") == false)
    }

    @Test
    func settingsActionRowsUseSharedComponent() throws {
        let sharedSource = try sourceText("timetracker/SharedUI/Components/SettingsRows.swift")
        let settingsSource = try [
            "timetracker/Features/Settings/SettingsSectionsViews.swift",
            "timetracker/Features/Settings/SettingsDataSectionsViews.swift"
        ].map(sourceText).joined(separator: "\n")
        let settingsActionsSource = try sourceText("timetracker/Features/Settings/SettingsViewActions.swift")

        #expect(sharedSource.contains("struct SettingsActionLabel"))
        #expect(sharedSource.contains("struct SettingsStatusRow"))
        #expect(sharedSource.contains(".font(.body)"))
        #expect(settingsSource.contains("SettingsActionLabel("))
        #expect(settingsSource.contains("SettingsStatusRow(feedback: feedback)"))
        #expect(settingsActionsSource.contains("store.syncStatus.feedback("))
        #expect(settingsSource.contains("Label(AppStrings.localized(\"settings.exportCSV\")") == false)
        #expect(settingsSource.contains("Label(AppStrings.localized(\"settings.forceSync\")") == false)
        #expect(settingsSource.contains("Button(role: .destructive, action: onRebuildDemoData) {\n                Text(") == false)
    }

    @Test
    func selectedTaskPulseIsSharedBetweenSidebarAndInspector() throws {
        let sharedSource = try sourceText("timetracker/SharedUI/Components/SelectionPulse.swift")
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarInspectorViews.swift")
        let inspectorSource = try sourceText("timetracker/Features/Inspector/InspectorViews.swift")

        #expect(sharedSource.contains("struct TaskSelectionPulseModifier<"))
        #expect(sharedSource.contains("func taskSelectionPulse<"))
        #expect(sidebarSource.contains(".taskSelectionPulse("))
        #expect(inspectorSource.contains(".taskSelectionPulse("))
        #expect(sidebarSource.contains("@State private var isPulsing") == false)
        #expect(inspectorSource.contains("@State private var isPulsing") == false)
    }

    @Test
    func splitViewToolbarButtonsUseSharedNativeLabels() throws {
        let sharedSource = try sourceText("timetracker/SharedUI/Components/SplitViewToolbarButtons.swift")
        let ipadSource = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")
        let desktopSource = try sourceText("timetracker/App/RootViews/DesktopRootViews.swift")

        #expect(sharedSource.contains("struct SidebarRevealButton"))
        #expect(sharedSource.contains("struct InspectorToggleButton"))
        #expect(sharedSource.contains("Label(AppStrings.localized(\"sidebar.show\"), systemImage: \"sidebar.left\")"))
        #expect(sharedSource.contains("Label(title, systemImage: \"sidebar.right\")"))
        #expect(sharedSource.contains(".labelStyle(.iconOnly)"))
        #expect(ipadSource.contains("SidebarRevealButton"))
        #expect(ipadSource.contains("InspectorToggleButton"))
        #expect(desktopSource.contains("InspectorToggleButton"))
        #expect(ipadSource.contains("Image(systemName: \"sidebar.right\")") == false)
        #expect(desktopSource.contains("Image(systemName: \"sidebar.right\")") == false)
    }

    @Test
    func settingsAndInspectorUsePlatformSurfaces() throws {
        let appSource = try sourceText("timetracker/App/timetrackerApp.swift")
        let settingsSource = try sourceText("timetracker/Features/Settings/SettingsViews.swift")
        let desktopSource = try sourceText("timetracker/App/RootViews/DesktopRootViews.swift")
        let ipadSource = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")

        #expect(appSource.contains("Settings {\n            SettingsSceneView()"))
        #expect(settingsSource.contains("Form {"))
        #expect(settingsSource.contains(".formStyle(.grouped)"))
        #expect(desktopSource.contains(".inspector(isPresented: inspectorBinding)"))
        #expect(ipadSource.contains(".inspector(isPresented: inspectorBinding)"))
        #expect(desktopSource.contains(".inspectorColumnWidth("))
        #expect(ipadSource.contains(".inspectorColumnWidth("))
    }

    @Test
    func compactPrimaryAndSuggestionActionsStayLegible() throws {
        let actionSource = try sourceText("timetracker/SharedUI/Components/ActionControls.swift")
        let homeActionSource = try sourceText("timetracker/Features/Home/Controls/HomeActionsViews.swift")
        let inboxSuggestionSource = try sourceText("timetracker/Features/Inbox/InboxSuggestionRow.swift")

        #expect(actionSource.contains(".minimumScaleFactor(0.78)"))
        #expect(actionSource.contains(".frame(minHeight: fixedHeight == nil ? minHeight : 0)"))
        #expect(homeActionSource.contains("startButton\n                    .frame(maxWidth: .infinity)"))
        #expect(homeActionSource.contains("newTaskButton\n                    .frame(maxWidth: .infinity)"))
        #expect(inboxSuggestionSource.contains("Image(systemName: \"checkmark\")"))
        #expect(inboxSuggestionSource.contains("Image(systemName: \"xmark\")"))
        #expect(inboxSuggestionSource.contains("Text(AppStrings.localized(\"inbox.suggestion.apply\"))") == false)
        #expect(inboxSuggestionSource.contains(".frame(width: isCompact ? 34 : 38, height: isCompact ? 34 : 38)"))
    }
}
