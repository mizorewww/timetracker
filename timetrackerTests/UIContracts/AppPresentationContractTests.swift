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
        #expect(content.contains("router: presentationRouter,"))
        #expect(content.contains("feedbackRouter: feedbackRouter"))

        #expect(settingsScene.contains("@State private var presentationRouter = AppPresentationRouter()"))
        #expect(settingsScene.contains(".environment(presentationRouter)"))
        #expect(settingsScene.contains("router: presentationRouter,"))
        #expect(settingsScene.contains("feedbackRouter: feedbackRouter"))

        #expect(app.contains("AppPresentationRouter") == false)
    }

    @Test
    func presentationHostUsesOneItemDrivenSheetAndMapsEverySupportedCase() throws {
        let host = try sourceText("timetracker/App/AppPresentationHost.swift")

        #expect(host.components(separatedBy: ".sheet(item:").count - 1 == 1)
        #expect(host.contains(".sheet(isPresented:") == false)
        for route in [
            ".taskEditor(",
            ".recoveredTaskEditor(",
            ".taskCategoryEditor(",
            ".manualTime(",
            ".segmentEditor(",
            ".startTaskPicker",
            ".singleTaskPicker(",
            ".singleTaskCategoryPicker(",
            ".quickStartEditor(",
            ".settings",
            ".llmConfiguration(",
            ".llmTaskPlanInstructions(",
            ".aiTaskPlanGenerator"
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
            "timetracker/Features/Settings/SettingsViews.swift",
            "timetracker/Features/Tasks/Management/TaskRecoveryDraftsSection.swift"
        ].map(sourceText).joined(separator: "\n")

        #expect(featureSources.contains(".sheet(") == false)
    }

    @Test
    func orphanedTaskDraftsReuseTheSceneEditorPresentation() throws {
        let router = try sourceText(
            "timetracker/App/AppPresentationRouter+TaskDraftRecovery.swift"
        )
        let host = try sourceText("timetracker/App/AppPresentationHost.swift")
        let editor = try sourceText(
            "timetracker/Features/Tasks/Editor/RecoveredTaskEditorSheet.swift"
        )
        let cleanup = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskDraftRecoveryCleanupSection.swift"
        )
        let section = try sourceText(
            "timetracker/Features/Tasks/Management/TaskRecoveryDraftsSection.swift"
        )
        let tasks = try sourceText(
            "timetracker/Features/Tasks/Management/TasksViews.swift"
        )

        #expect(tasks.contains("TaskRecoveryDraftsSection(store: store)"))
        #expect(section.contains(".recoverableRecords()"))
        #expect(section.contains(
            "store.isTaskDetailRouteValid($0.sourceTaskID) == false"
        ))
        #expect(section.contains(
            "presentationRouter.presentRecoveredTaskDraft("
        ))
        #expect(section.contains(".sheet(") == false)
        #expect(section.contains(".confirmationDialog("))
        #expect(router.contains("record.draft.copyAsNew("))
        #expect(router.contains("store.isTaskDetailRouteValid($0)"))
        #expect(router.contains(
            "savedTaskID: store.task(for: record.draft.id)?.id"
        ))
        #expect(host.contains("RecoveredTaskEditorSheet("))
        #expect(editor.contains(
            "isInteractionDisabled: isDiscarding"
        ))
        #expect(editor.contains(
            "guard savedTaskID == nil, isDiscarding == false"
        ))
        #expect(editor.contains(
            "task.editor.recovery.discarding"
        ))
        #expect(editor.contains("TaskEditorPanel("))
        #expect(editor.contains("store.saveRecoveredTaskDraftResult("))
        #expect(editor.contains(
            "proposedTaskID: presentation.proposedTaskID"
        ))
        #expect(editor.contains(
            ".removeInBackground(for: presentation.sourceTaskID)"
        ))
        #expect(editor.contains("task.editor.recovery.more"))
        #expect(cleanup.contains("tasks.recovery.cleanupLater"))
        #expect(section.contains("tasks.recovery.more"))
        #expect(section.contains(".removeInBackground(for: sourceTaskID)"))
        #expect(section.contains("restoreArchivedHierarchyForRecovery("))
    }

    @Test
    func rootSyncConflictNoticeRoutesToSettingsWithoutAutomaticDestructiveActions() throws {
        let content = try sourceText("timetracker/App/ContentView.swift")
        let iOSRoot = try sourceText(
            "timetracker/App/RootViews/iOSRootViews.swift"
        )
        let notice = try sourceText(
            "timetracker/SharedUI/Components/SyncConflictNotice.swift"
        )
        let recovery = try sourceText(
            "timetracker/Features/Settings/SyncRecoverySettingsSection.swift"
        )

        #expect(content.contains("SyncConflictNotice("))
        #expect(content.contains("store.desktopDestination = .settings"))
        #expect(content.contains("dialog.syncConflict.uploadLocal") == false)
        #expect(content.contains("dialog.syncConflict.downloadCloud") == false)
        #expect(content.contains("store.effectivePersistenceWriteSafety == .ready"))
        #expect(content.contains(".padding(.bottom, 84)") == false)
        #expect(iOSRoot.contains(".tabViewBottomAccessory") == false)
        #expect(iOSRoot.contains(".safeAreaInset(edge: .top, spacing: 0)"))
        #expect(notice.contains("sync.conflict.notice.review"))
        #expect(recovery.contains("pendingConflict.localSummary"))
        #expect(recovery.contains("pendingConflict.cloudSummary"))
        #expect(recovery.contains("Button(role: .destructive, action: onReplaceCloud)"))
        #expect(recovery.contains("Button(role: .destructive, action: onReplaceDevice)"))
    }

    @Test
    func uiTestConflictInjectionCannotBeErasedByRemoteStoreObservers() throws {
        let observers = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+SyncObservers.swift"
        )

        #expect(observers.contains(
            "AppCloudSync.persistenceMode != AppCloudSync.modeUITest"
        ))
    }

    @Test
    func presentationTriggersUseTheSceneRouterAndPickerReplacementIsAtomic() throws {
        let content = try sourceText("timetracker/App/ContentView.swift")
        let deepLinks = try sourceText(
            "timetracker/App/AppSceneDeepLinkCoordinator.swift"
        )
        let homeActions = try sourceText("timetracker/Features/Home/Controls/HomeActionsViews.swift")
        let phoneHome = try sourceText("timetracker/Features/Home/PhoneHomeView.swift")
        let quickStart = try sourceText("timetracker/Features/Home/Sections/HomeQuickStartViews.swift")
        let settings = try [
            "timetracker/Features/Settings/SettingsViews.swift",
            "timetracker/Features/Settings/SettingsCategorySections.swift"
        ].map(sourceText).joined(separator: "\n")
        let host = try sourceText("timetracker/App/AppPresentationHost.swift")

        #expect(content.contains("AppSceneDeepLinkCoordinator("))
        #expect(deepLinks.contains("store.handleDeepLink("))
        #expect(deepLinks.contains("presentationRouter: presentationRouter"))
        #expect(homeActions.contains("presentationRouter.presentStartTaskPicker()"))
        #expect(phoneHome.contains("presentationRouter.presentStartTaskPicker()"))
        #expect(phoneHome.contains("presentationRouter.presentQuickStartEditor(using: store)"))
        #expect(quickStart.contains("presentationRouter.presentQuickStartEditor(using: store)"))
        #expect(settings.contains("presentationRouter.presentLLMConfiguration(using: store)"))
        #expect(settings.contains(
            "presentationRouter.presentLLMTaskPlanInstructions(using: store)"
        ))
        #expect(host.contains("router.replaceWithNewTask("))
        #expect(host.contains("if taskPicker.selectTask(taskID)"))
        #expect(host.contains(
            "if categoryPicker.selectCategory(categoryID)"
        ))
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
        let presentationHost = try sourceText("timetracker/App/AppPresentationHost.swift")

        #expect(categorySections.contains("onAddTime") == false)
        #expect(categorySections.contains("presentManualTime") == false)
        #expect(dataSections.contains("onAddTime") == false)
        #expect(dataSections.contains("AppStrings.addTime") == false)
        #expect(categorySections.contains("onConfigure: presentLLMConfiguration"))
        #expect(categorySections.contains(
            "onEditTaskPlanInstructions: presentLLMTaskPlanInstructions"
        ))
        #expect(settingsView.contains("presentationRouter.presentLLMConfiguration(using: store)"))
        #expect(settingsView.contains(
            "presentationRouter.presentLLMTaskPlanInstructions(using: store)"
        ))
        #expect(presentationHost.contains("private struct AppSettingsSheet: View"))
        #expect(presentationHost.contains("@State private var childRouter = AppPresentationRouter()"))
        #expect(presentationHost.contains(".environment(childRouter)"))
        #expect(presentationHost.contains("router: childRouter,"))
        #expect(presentationHost.contains("feedbackRouter: feedbackRouter"))
        #expect(presentationHost.contains(".environment(feedbackRouter)"))
    }

    @Test
    func phoneSettingsUsesScenePresentationWithoutPollutingATabStack() throws {
        let root = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")
        let router = try sourceText("timetracker/App/AppPresentationRouter.swift")

        #expect(root.contains("@Environment(AppPresentationRouter.self)"))
        #expect(root.contains("presentationRouter.presentSettings()"))
        #expect(root.contains("restoreContentDestinationAfterPresentingSettings()"))
        #expect(root.contains("store.desktopDestination == .settings"))
        #expect(root.contains("PhoneTodayRoute") == false)
        #expect(root.contains("todayPath") == false)
        #expect(root.contains("SettingsView(store: store)") == false)
        #expect(router.contains("case settings"))
        #expect(router.contains("func presentSettings() -> Bool"))
    }

    @Test
    func deepLinksDeferBehindAModalAndResumeWhenTheSheetClears() throws {
        let content = try sourceText("timetracker/App/ContentView.swift")
        let sceneCoordinator = try sourceText(
            "timetracker/App/AppSceneDeepLinkCoordinator.swift"
        )
        let deepLinks = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+DeepLinks.swift"
        )

        #expect(sceneCoordinator.contains("if disposition == .deferred"))
        #expect(sceneCoordinator.contains("pendingDeepLinks.enqueue(url)"))
        #expect(sceneCoordinator.contains("pendingDeepLinks.restoreToFront(deferredURLs)"))
        #expect(content.contains(".onChange(of: presentationRouter.sheet?.id)"))
        #expect(content.contains("hasPendingNavigation"))
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
        let taskView = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskEditorViews.swift"
        )
        let taskSession = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskEditorSession.swift"
        )
        let task = [taskView, taskSession].joined(separator: "\n")
        let category = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskCategoryEditorViews.swift"
        )
        let manual = try sourceText("timetracker/Features/Ledger/ManualTimeViews.swift")
        let segment = try [
            "timetracker/Features/Ledger/SegmentEditorSheet.swift",
            "timetracker/Features/Ledger/SegmentEditorViews.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
        let quickStart = try sourceText(
            "timetracker/Features/Home/Sections/HomeQuickStartEditorViews.swift"
        )
        let llm = try sourceText("timetracker/Features/Settings/LLMSettingsViews.swift")

        #expect(taskView.contains("store.saveTaskDraftResult("))
        #expect(taskView.contains("session.save("))
        #expect(taskView.contains("using: onSave"))
        #expect(taskView.contains("onSaved: { _ in onSaved() }"))
        #expect(taskSession.contains("case .saved(let taskID):"))
        #expect(taskSession.contains("onSaved(taskID)"))
        #expect(category.contains("if store.saveTaskCategoryDraft(draft)"))
        #expect(manual.contains("if store.saveManualTimeDraft(draft)"))
        #expect(segment.contains("try store.commitSegmentDraft(draft)"))
        #expect(segment.contains("try store.commitSegmentDeletion("))
        #expect(segment.contains("currentDraft = latestDraft"))
        #expect(segment.contains(".id(currentDraft.id)"))
        #expect(segment.contains("segment.editor.discardAndClose"))
        #expect(segment.contains("role: .destructive"))
        #expect(segment.contains("Button(AppStrings.cancel, role: .cancel)"))
        #expect(segment.contains("segment.editor.close") == false)
        #expect(segment.contains("segment.editor.deleted.title"))
        #expect(segment.contains("$0.id == currentDraft.segmentID"))
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
