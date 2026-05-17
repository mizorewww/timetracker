import Foundation
import Testing

@Suite(.serialized)
struct SharedComponentsContractTests {
    @Test
    func ipadSidebarButtonOnlyRevealsSidebar() throws {
        let ipadSource = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")

        #expect(ipadSource.contains("if columnVisibility == .detailOnly"))
        #expect(ipadSource.contains("columnVisibility = .all"))
        #expect(ipadSource.contains("isInspectorPresented") == false)
        #expect(ipadSource.contains(".inspector(") == false)
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
    func primaryActionLabelsUseSharedComponentAcrossHomeAndTaskDetail() throws {
        let sharedSource = try sourceText("timetracker/SharedUI/Components/ActionControls.swift")
        let homeSource = try sourceText("timetracker/Features/Home/Controls/HomeActionsViews.swift")
        let taskDetailSource = try sourceText("timetracker/Features/Tasks/Detail/TaskDetailHeaderView.swift")

        #expect(sharedSource.contains("struct AppActionLabel"))
        #expect(sharedSource.contains(".minimumScaleFactor(0.78)"))
        #expect(homeSource.contains("AppActionLabel(title: AppStrings.startTimer"))
        #expect(homeSource.contains("private func actionLabel") == false)
        #expect(taskDetailSource.contains("AppActionLabel(title: AppStrings.startTimer"))
        #expect(taskDetailSource.contains("AppActionLabel(title: AppStrings.addTime"))
    }

    @Test
    func settingsActionRowsUseSharedComponent() throws {
        let sharedSource = try sourceText("timetracker/SharedUI/Components/SettingsRows.swift")
        let settingsSource = try [
            "timetracker/Features/Settings/SettingsSectionsViews.swift",
            "timetracker/Features/Settings/SettingsDataSectionsViews.swift",
            "timetracker/Features/Settings/SettingsPomodoroSection.swift",
            "timetracker/Features/Settings/SettingsPomodoroMinuteRows.swift",
            "timetracker/Features/Settings/SettingsCountdownSection.swift",
            "timetracker/Features/Settings/SettingsSyncSection.swift",
            "timetracker/Features/Settings/Support/SettingsSupportViews.swift"
        ].map(sourceText).joined(separator: "\n")
        let settingsActionsSource = try sourceText("timetracker/Features/Settings/SettingsViewActions.swift")

        #expect(sharedSource.contains("struct SettingsActionLabel"))
        #expect(sharedSource.contains("struct SettingsStatusRow"))
        #expect(sharedSource.contains("func settingsRowSeparatorAligned()"))
        #expect(sharedSource.contains("alignmentGuide(.listRowSeparatorLeading)"))
        #expect(sharedSource.contains(".font(.body)"))
        #expect(settingsSource.contains("SettingsActionLabel("))
        #expect(settingsSource.contains("SettingsStatusRow(feedback: feedback)"))
        #expect(settingsSource.contains(".settingsRowSeparatorAligned()"))
        #expect(settingsActionsSource.contains("store.syncStatus.feedback("))
        #expect(settingsSource.contains("Label(AppStrings.localized(\"settings.exportJSON\")") == false)
        #expect(settingsSource.contains("Label(AppStrings.localized(\"settings.forceSync\")") == false)
        #expect(settingsSource.contains("Button(role: .destructive, action: onRebuildDemoData) {\n                Text(") == false)
    }

    @Test
    func llmModelSelectionFetchesFromModelRow() throws {
        let settingsDataSource = try sourceText("timetracker/Features/Settings/SettingsDataSectionsViews.swift")
        let settingsViewSource = try sourceText("timetracker/Features/Settings/SettingsViews.swift")
        let settingsActionsSource = try sourceText("timetracker/Features/Settings/SettingsViewActions.swift")
        let englishStrings = try sourceText("timetracker/en.lproj/Localizable.strings")

        #expect(settingsDataSource.contains("private var modelSelectionRow"))
        #expect(settingsDataSource.contains("SettingsModelSelectionRow("))
        #expect(settingsDataSource.contains("Button(action: onFetchModels)"))
        #expect(settingsDataSource.contains("ProgressView()"))
        #expect(settingsDataSource.contains("AppStrings.localized(\"settings.llm.fetching\")"))
        #expect(settingsDataSource.contains("AppStrings.localized(\"settings.llm.fetchModels\")") == false)
        #expect(settingsViewSource.contains(".onAppear(perform: fetchLLMModelsIfNeeded)") == false)
        #expect(settingsActionsSource.contains("func fetchLLMModelsIfNeeded") == false)
        #expect(englishStrings.contains("\"settings.llm.fetchModels\"") == false)
    }

    @Test
    func selectedTaskPulseIsSharedForSidebarRows() throws {
        let sharedSource = try sourceText("timetracker/SharedUI/Components/SelectionPulse.swift")
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarViews.swift")

        #expect(sharedSource.contains("struct TaskSelectionPulseModifier<"))
        #expect(sharedSource.contains("func taskSelectionPulse<"))
        #expect(sidebarSource.contains(".taskSelectionPulse("))
        #expect(sidebarSource.contains("@State private var isPulsing") == false)
    }

    @Test
    func splitViewToolbarButtonsUseSharedNativeLabels() throws {
        let sharedSource = try sourceText("timetracker/SharedUI/Components/SplitViewToolbarButtons.swift")
        let ipadSource = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")
        let desktopSource = try sourceText("timetracker/App/RootViews/DesktopRootViews.swift")

        #expect(sharedSource.contains("struct SidebarRevealButton"))
        #expect(sharedSource.contains("Label(AppStrings.localized(\"sidebar.show\"), systemImage: \"sidebar.left\")"))
        #expect(sharedSource.contains(".labelStyle(.iconOnly)"))
        #expect(ipadSource.contains("SidebarRevealButton"))
        #expect(sharedSource.contains("InspectorToggleButton") == false)
        #expect(ipadSource.contains("InspectorToggleButton") == false)
        #expect(desktopSource.contains("InspectorToggleButton") == false)
        #expect(ipadSource.contains("Image(systemName: \"sidebar.right\")") == false)
        #expect(desktopSource.contains("Image(systemName: \"sidebar.right\")") == false)
    }

    @Test
    func settingsUsesPlatformSurfaceAndRootsOmitInspector() throws {
        let appSource = try sourceText("timetracker/App/timetrackerApp.swift")
        let settingsSource = try sourceText("timetracker/Features/Settings/SettingsViews.swift")
        let desktopSource = try sourceText("timetracker/App/RootViews/DesktopRootViews.swift")
        let ipadSource = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")

        #expect(appSource.contains("Settings {\n            SettingsSceneView()"))
        #expect(settingsSource.contains("Form {"))
        #expect(settingsSource.contains(".formStyle(.grouped)"))
        #expect(desktopSource.contains(".inspector(") == false)
        #expect(ipadSource.contains(".inspector(") == false)
        #expect(desktopSource.contains(".inspectorColumnWidth(") == false)
        #expect(ipadSource.contains(".inspectorColumnWidth(") == false)
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
