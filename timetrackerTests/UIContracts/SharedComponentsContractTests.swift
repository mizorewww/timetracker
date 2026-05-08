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
}
