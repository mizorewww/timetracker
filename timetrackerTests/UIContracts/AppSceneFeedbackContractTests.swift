import Foundation
import Testing

@Suite(.serialized)
struct AppSceneFeedbackContractTests {
    @Test
    func everySceneOwnsAndHostsItsFeedbackRouter() throws {
        let content = try sourceText("timetracker/App/ContentView.swift")
        let settingsScene = try sourceText("timetracker/App/SettingsSceneView.swift")

        for source in [content, settingsScene] {
            #expect(source.contains("@State private var feedbackRouter = AppSceneFeedbackRouter()"))
            #expect(source.contains(".environment(feedbackRouter)"))
            #expect(source.contains(".appSceneFeedbackHost(router: feedbackRouter)"))
        }

        #expect(content.contains(".onChange(of: store.errorMessage)"))
        #expect(content.contains("feedbackRouter.present("))
        #expect(content.contains(".alert(Text(.app(\"error.title\")") == false)
        #expect(content.contains("private var errorBinding") == false)
    }

    @Test
    func feedbackHostDismissesOnlyThePresentedIdentity() throws {
        let host = try sourceText("timetracker/App/AppSceneFeedbackHost.swift")

        #expect(host.contains("presenting: feedback"))
        #expect(host.contains("presentationBinding(feedbackID: feedback?.id)"))
        #expect(host.contains("router.dismiss(feedbackID: presentedFeedback.id)"))
        #expect(host.contains("router.dismiss(feedbackID: feedbackID)"))
    }

    @Test
    func settingsDataFailuresStayInTheSettingsScene() throws {
        let settings = try sourceText("timetracker/Features/Settings/SettingsViews.swift")
        let confirmation = try sourceText(
            "timetracker/Features/Settings/SettingsDestructiveConfirmation.swift"
        )
        let dataSection = try sourceText(
            "timetracker/Features/Settings/SettingsDataSectionsViews.swift"
        )
        let maintenance = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+MaintenanceCommands.swift"
        )

        #expect(settings.contains("@Environment(AppSceneFeedbackRouter.self)"))
        #expect(settings.contains("presentSettingsError(context: .dataExport"))
        #expect(settings.contains("(error as? CocoaError)?.code != .userCancelled"))
        #expect(confirmation.contains("feedbackRouter.present("))
        #expect(confirmation.contains("context: .databaseMaintenance"))
        #expect(dataSection.contains("settings.data.operationMessage"))
        #expect(maintenance.contains("func jsonExport() throws -> String"))
        #expect(maintenance.contains("func jsonExport() -> String?") == false)
    }

    @Test
    func ordinarySettingsMutationsConsumeFailuresInTheirOriginatingScene() throws {
        let settings = try sourceText("timetracker/Features/Settings/SettingsViews.swift")
        let bindings = try sourceText("timetracker/Features/Settings/SettingsViewBindings.swift")
        let sections = try sourceText("timetracker/Features/Settings/SettingsCategorySections.swift")
        let preferences = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+PreferenceCommands.swift"
        ) + (try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+PomodoroPreferenceCommands.swift"
        ))
        let countdowns = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+CountdownCommands.swift"
        )

        #expect(settings.contains("func handleSettingsStoreMutation(_ didSucceed: Bool"))
        #expect(settings.components(separatedBy: "store.errorMessage").count - 1 == 3)
        #expect(settings.contains("if store.errorMessage == message"))
        #expect(bindings.components(separatedBy: "handleSettingsStoreMutation(").count >= 8)
        #expect(sections.components(separatedBy: "handleSettingsStoreMutation(").count >= 3)
        #expect(preferences.contains("func setPomodoroPlans(_ plans: [PomodoroPlan]) -> Bool"))
        #expect(preferences.contains("func setAllowParallelTimers(_ value: Bool) -> Bool"))
        #expect(countdowns.contains("func addCountdownEvent() -> Bool"))
        #expect(countdowns.contains("func deleteCountdownEvent(_ event: CountdownEvent) -> Bool"))
    }

    @Test
    func settingsSyncRecoveryFailuresStayInTheSettingsScene() throws {
        let actions = try sourceText(
            "timetracker/Features/Settings/SettingsViewActions.swift"
        )
        let lifecycle = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+Lifecycle.swift"
        )

        #expect(actions.contains("try store.resolveSyncConflict("))
        #expect(actions.contains("presentSyncRecoveryError(error)"))
        #expect(actions.contains("context: .syncRecovery"))
        #expect(lifecycle.contains(") throws -> SyncConflictResolutionResult"))
        #expect(lifecycle.contains("errorMessage = AppStrings.localized(\"sync.conflict.error.changed\")") == false)
        #expect(lifecycle.contains("return .failed") == false)
    }
}
