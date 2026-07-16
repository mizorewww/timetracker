import Foundation
import Testing

@Suite(.serialized)
struct AppPresentationContractTests {
    @Test
    func everySceneOwnsItsPresentationRouterAndMacSettingsHostsLocally() throws {
        let content = try sourceText("timetracker/App/ContentView.swift")
        let settingsScene = try sourceText("timetracker/App/SettingsSceneView.swift")
        let app = try sourceText("timetracker/App/timetrackerApp.swift")

        #expect(content.contains("@State private var presentationRouter = AppPresentationRouter()"))
        #expect(content.contains(".environment(presentationRouter)"))
        #expect(content.contains(".appPresentationHost(store: store, router: presentationRouter)"))

        #expect(settingsScene.contains("@State private var presentationRouter = AppPresentationRouter()"))
        #expect(settingsScene.contains(".environment(presentationRouter)"))
        #expect(settingsScene.contains(".appPresentationHost(store: store, router: presentationRouter)"))

        #expect(app.contains("AppPresentationRouter") == false)
    }

    @Test
    func presentationHostUsesOneItemDrivenSheetAndMapsEverySupportedCase() throws {
        let host = try sourceText("timetracker/App/AppPresentationHost.swift")

        #expect(host.components(separatedBy: ".sheet(item:").count - 1 == 1)
        #expect(host.contains(".sheet(isPresented:") == false)
        for route in [
            ".taskEditor(",
            ".taskCategoryEditor(",
            ".manualTime(",
            ".segmentEditor(",
            ".startTaskPicker",
            ".quickStartEditor(",
            ".llmConfiguration("
        ] {
            #expect(host.contains(route))
        }
        #expect(host.contains("inboxSuggestionEditor") == false)
    }

    @Test
    func featureRootsDoNotOwnCompetingSheets() throws {
        let featureSources = try [
            "timetracker/App/ContentView.swift",
            "timetracker/Features/Home/Controls/HomeActionsViews.swift",
            "timetracker/Features/Home/PhoneHomeView.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartViews.swift",
            "timetracker/Features/Settings/SettingsViews.swift"
        ].map(sourceText).joined(separator: "\n")

        #expect(featureSources.contains(".sheet(") == false)
    }

    @Test
    func presentationTriggersUseTheSceneRouterAndPickerReplacementIsAtomic() throws {
        let content = try sourceText("timetracker/App/ContentView.swift")
        let homeActions = try sourceText("timetracker/Features/Home/Controls/HomeActionsViews.swift")
        let phoneHome = try sourceText("timetracker/Features/Home/PhoneHomeView.swift")
        let quickStart = try sourceText("timetracker/Features/Home/Sections/HomeQuickStartViews.swift")
        let settings = try [
            "timetracker/Features/Settings/SettingsViews.swift",
            "timetracker/Features/Settings/SettingsCategorySections.swift"
        ].map(sourceText).joined(separator: "\n")
        let host = try sourceText("timetracker/App/AppPresentationHost.swift")

        #expect(content.contains("store.handleDeepLink("))
        #expect(content.contains("presentationRouter: presentationRouter"))
        #expect(homeActions.contains("presentationRouter.presentStartTaskPicker()"))
        #expect(phoneHome.contains("presentationRouter.presentStartTaskPicker()"))
        #expect(phoneHome.contains("presentationRouter.presentQuickStartEditor(using: store)"))
        #expect(quickStart.contains("presentationRouter.presentQuickStartEditor(using: store)"))
        #expect(settings.contains("presentationRouter.presentLLMConfiguration(using: store)"))
        #expect(host.contains("router.replaceWithNewTask("))
        #expect(homeActions.contains("Task.yield()") == false)
    }

    @Test
    func settingsKeepsDataActionsSettingsScopedAndHostsLLMLocally() throws {
        let categorySections = try sourceText(
            "timetracker/Features/Settings/SettingsCategorySections.swift"
        )
        let dataSections = try sourceText(
            "timetracker/Features/Settings/SettingsDataSectionsViews.swift"
        )
        let settingsView = try sourceText("timetracker/Features/Settings/SettingsViews.swift")

        #expect(categorySections.contains("onAddTime") == false)
        #expect(categorySections.contains("presentManualTime") == false)
        #expect(dataSections.contains("onAddTime") == false)
        #expect(dataSections.contains("AppStrings.addTime") == false)
        #expect(categorySections.contains("onConfigure: presentLLMConfiguration"))
        #expect(settingsView.contains("presentationRouter.presentLLMConfiguration(using: store)"))
    }

    @Test
    func deepLinksDeferBehindAModalAndResumeWhenTheSheetClears() throws {
        let content = try sourceText("timetracker/App/ContentView.swift")
        let deepLinks = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+DeepLinks.swift"
        )

        #expect(content.contains("if disposition == .deferred"))
        #expect(content.contains("pendingDeepLinks.enqueue(url)"))
        #expect(content.contains(".onChange(of: presentationRouter.sheet?.id)"))
        #expect(content.contains("drainPendingDeepLinks()"))
        #expect(deepLinks.contains("return .deferred"))
        #expect(deepLinks.contains("return .handled"))
        #expect(deepLinks.contains("return .rejected"))
    }

    @Test
    func macCommandsResolveTheFocusedScenesRouterInsteadOfGlobalPresentationState() throws {
        let focusedValues = try sourceText("timetracker/App/FocusedSceneActions.swift")
        let desktopRoot = try sourceText(
            "timetracker/App/RootViews/DesktopRootViews.swift"
        )
        let commands = try sourceText("timetracker/App/TimeTrackerCommands.swift")

        #expect(focusedValues.contains("@Entry var appPresentationRouter: AppPresentationRouter?"))
        #expect(focusedValues.contains("() -> Void") == false)
        #expect(desktopRoot.contains(".focusedSceneValue(\\.appPresentationRouter, presentationRouter)"))
        #expect(commands.contains("@FocusedValue(\\.appPresentationRouter)"))
        #expect(commands.contains("presentationRouter.presentNewTask(using: store)"))
        #expect(commands.contains("presentationRouter.presentManualTime(using: store)"))
        #expect(commands.contains("store?.presentNewTask") == false)
        #expect(commands.contains("store?.presentManualTime") == false)
    }

    @Test
    func storeNoLongerOwnsScenePresentationStateOrDeadInboxEditorRoute() throws {
        let store = try sourceText("timetracker/Stores/Facade/TimeTrackerStore.swift")
        let deepLinks = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+DeepLinks.swift")
        let inbox = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+InboxSuggestionCommands.swift"
        )
        let router = try sourceText("timetracker/App/AppPresentationRouter.swift")

        for legacyState in [
            "taskEditorDraft",
            "taskCategoryEditorDraft",
            "manualTimeDraft",
            "segmentEditorDraft",
            "inboxSuggestionEditorDraft",
            "isStartTaskPickerPresented"
        ] {
            #expect(store.contains(legacyState) == false)
        }
        #expect(deepLinks.contains("presentationRouter"))
        #expect(deepLinks.contains("isStartTaskPickerPresented") == false)
        #expect(inbox.contains("presentInboxSuggestionEditor") == false)
        #expect(inbox.contains("inboxSuggestionEditorDraft") == false)
        #expect(router.contains("inboxSuggestionEditor") == false)
    }

    @Test
    func editorSheetsDismissOnlyAfterSuccessfulMutation() throws {
        let task = try sourceText("timetracker/Features/Tasks/Editor/TaskEditorViews.swift")
        let category = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskCategoryEditorViews.swift"
        )
        let manual = try sourceText("timetracker/Features/Ledger/ManualTimeViews.swift")
        let segment = try sourceText("timetracker/Features/Ledger/SegmentEditorViews.swift")
        let quickStart = try sourceText(
            "timetracker/Features/Home/Sections/HomeQuickStartEditorViews.swift"
        )
        let llm = try sourceText("timetracker/Features/Settings/LLMSettingsViews.swift")

        #expect(task.contains("if store.saveTaskDraft(draft"))
        #expect(category.contains("if store.saveTaskCategoryDraft(draft)"))
        #expect(manual.contains("if store.saveManualTimeDraft(draft)"))
        #expect(segment.contains("if store.saveSegmentDraft(draft)"))
        #expect(quickStart.contains("if onSave(cleanedPinnedIDs())"))
        #expect(llm.contains("if onSave(draft.normalized)"))

        let editorSources = [task, category, manual, segment].joined(separator: "\n")
        for legacyState in [
            "store.taskEditorDraft = nil",
            "store.taskCategoryEditorDraft = nil",
            "store.manualTimeDraft = nil",
            "store.segmentEditorDraft = nil"
        ] {
            #expect(editorSources.contains(legacyState) == false)
        }
    }
}
