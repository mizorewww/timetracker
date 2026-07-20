import Foundation
import Testing

@Suite(.serialized)
struct TaskWorkspaceContractTests {
    @Test
    func existingTaskEditingStaysInsideTheCanonicalTaskWorkspace() throws {
        let detail = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailView.swift"
        )
        let workspace = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailWorkspace.swift"
        )
        let workspaceNavigation = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailWorkspace+Navigation.swift"
        )
        let workspaceRecovery = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailWorkspace+Recovery.swift"
        )
        let draftRecoveryModifier = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailDraftRecoveryModifier.swift"
        )
        let draftRecoveryController = try sourceText(
            "timetracker/Services/Tasks/TaskDraftRecoveryController.swift"
        )
        let draftRecoveryEnumeration = try sourceText(
            "timetracker/Services/Tasks/TaskDraftRecoveryStore+Enumeration.swift"
        )
        let editorSession = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskEditorSession.swift"
        )
        let store = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore.swift"
        )
        let content = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailContentView.swift"
        )
        let identity = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailIdentityViews.swift"
        )
        let navigation = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailNavigationViews.swift"
        )
        let taskNavigation = try sourceText(
            "timetracker/Features/Tasks/Management/TasksNavigationView.swift"
        )
        let todayNavigation = try sourceText(
            "timetracker/Features/Home/TodayTaskNavigation.swift"
        )
        let actions = try sourceText(
            "timetracker/Features/Tasks/Management/TaskRowComponents.swift"
        )
        let selection = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+Selection.swift"
        )
        let sidebar = try sourceText(
            "timetracker/Features/Sidebar/SidebarViews.swift"
        )
        let commands = try sourceText("timetracker/App/TimeTrackerCommands.swift")
        let iosRoot = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")
        let phoneTabSafety = try sourceText(
            "timetracker/App/RootViews/PhoneTabNavigationSafety.swift"
        )
        let infoPlist = try sourceText("timetracker/Info.plist")
        let project = try sourceText("timetracker.xcodeproj/project.pbxproj")
        let navigationGuard = try sourceText(
            "timetracker/Stores/Navigation/TaskDetailNavigationGuard.swift"
        )
        let route = try sourceText("timetracker/Stores/Navigation/TasksRoute.swift")
        let router = try sourceText("timetracker/App/AppPresentationRouter.swift")

        #expect(detail.contains("TaskDetailWorkspace("))
        #expect(detail.contains(".id(taskID)"))
        #expect(detail.contains("let replaceDetail: (UUID) -> Void"))
        #expect(detail.contains("TaskEditorPanel(") == false)
        #expect(detail.contains("startsEditing") == false)
        #expect(workspace.contains("@State var session: TaskEditorSession"))
        #expect(workspace.contains("TaskDetailList("))
        #expect(workspaceNavigation.contains("store.saveTaskDraftResult("))
        #expect(workspaceNavigation.contains("session.acceptLatestDraft(for: savedTaskID)"))
        #expect(workspaceNavigation.contains("onStale: {"))
        #expect(workspaceNavigation.contains(
            "draftRecoveryReason = isSourceUnavailable"
        ))
        #expect(workspace.contains("session.synchronizeWithStoreIfClean(taskID: taskID)"))
        #expect(workspace.contains(".taskEditorSessionSafety("))
        #expect(workspace.contains(".taskDetailDraftRecovery("))
        #expect(workspace.contains("draftRecoveryLoadState"))
        #expect(workspace.contains(".task(id: draftRecoveryLoadRequestID)"))
        #expect(workspace.contains("registerNavigationGuard"))
        #expect(workspaceNavigation.contains(
            "discardChangesAndCompletePendingNavigation("
        ))
        #expect(workspaceRecovery.contains("replaceDetail(savedTaskID)"))
        #expect(workspaceRecovery.contains(
            "store.saveRecoveredTaskDraftResult("
        ))
        #expect(workspaceRecovery.contains(
            "proposedTaskID: session.draft.id"
        ))
        #expect(workspaceRecovery.contains(
            "store.restoreArchivedHierarchyForRecovery(taskID: taskID)"
        ))
        #expect(workspaceRecovery.contains("clearPersistedDraftRecovery()"))
        #expect(workspace.contains(
            "@State var draftRecoveryReason: TaskDraftRecoveryReason?"
        ))
        #expect(workspaceNavigation.contains(
            "draftRecoveryReason = nil"
        ))
        #expect(workspaceNavigation.contains(
            "oldValue != hasUnsavedChanges"
        ))
        #expect(editorSession.contains("func restoreRecoveredDraft("))
        #expect(editorSession.contains("sessionBaseline = recoveredDraft") == false)
        #expect(store.contains("let taskDraftRecoveryController: TaskDraftRecoveryController"))
        #expect(workspaceRecovery.contains("try await store.taskDraftRecoveryController.load("))
        #expect(workspaceRecovery.contains("draftRecoveryLoadState = .failed"))
        #expect(draftRecoveryModifier.contains("await controller.removeExpired()"))
        #expect(draftRecoveryModifier.contains(".onChange(of: request, initial: true)"))
        #expect(draftRecoveryModifier.contains("controller.makePersistenceTicket("))
        #expect(draftRecoveryModifier.contains("await controller.persist(ticket)"))
        #expect(draftRecoveryModifier.contains(".onChange(of: scenePhase)"))
        #expect(draftRecoveryModifier.contains(".onDisappear(perform: flushCurrentDraft)"))
        #expect(draftRecoveryModifier.contains("NSApplication.willTerminateNotification"))
        #expect(draftRecoveryController.contains("private actor TaskDraftRecoveryWorker"))
        #expect(draftRecoveryController.contains("TaskDraftRecoveryOperationGate"))
        #expect(draftRecoveryController.contains("let didRemove = try gate.performIfCurrent("))
        #expect(draftRecoveryController.contains("removalSuperseded"))
        #expect(draftRecoveryController.contains(
            "func recoverableRecords() async throws"
        ))
        #expect(draftRecoveryEnumeration.contains(
            "struct TaskDraftRecoveryRecord"
        ))
        #expect(draftRecoveryEnumeration.contains(
            "localFile.managedDirectoryContents("
        ))
        #expect(content.contains("TaskEditorSections("))
        #expect(content.contains("showsTitleField: false"))
        #expect(content.contains("notesStartInPreview: true"))
        #expect(identity.contains("text: $draft.title"))
        #expect(identity.contains("axis: .vertical") == false)
        #expect(identity.contains(".submitLabel(.done)"))
        #expect(identity.contains("focusedTextField.wrappedValue = nil"))
        #expect(navigation.contains("session.hasUnsavedChanges"))
        #expect(navigation.contains(".navigationBarBackButtonHidden(session.hasUnsavedChanges)"))
        #expect(navigation.contains("task.context.edit") == false)
        #expect(navigation.contains("presentationRouter.presentEditTask") == false)
        #expect(taskNavigation.contains("startsEditing") == false)
        #expect(taskNavigation.contains("replaceDetail: store.openTaskDetail"))
        #expect(taskNavigation.contains(".id(route.taskID)"))
        #expect(todayNavigation.contains(".id(route.taskID)"))
        #expect(actions.contains("store.openTaskEditor") == false)
        #expect(actions.contains("task.context.edit") == false)
        #expect(actions.contains("presentEditTask") == false)
        #expect(selection.contains("func openTaskEditor") == false)
        #expect(selection.contains("archiveTaskProtectingUnsavedChanges"))
        #expect(selection.contains("dismissingActiveDetail: true"))
        #expect(selection.contains("beforeDiscardingChanges:"))
        #expect(sidebar.contains("taskDetailNavigationGuard.requestNavigation"))
        #expect(commands.contains("taskDetailNavigationGuard.requestNavigation"))
        #expect(iosRoot.contains("TabView(selection: selectedDestinationBinding)"))
        #expect(iosRoot.contains("taskDetailNavigationGuard.requestNavigation"))
        #expect(iosRoot.contains("presentingConfirmationInSource: false"))
        #expect(iosRoot.contains(".phoneTabNavigationSafety("))
        #expect(phoneTabSafety.contains(".editorDiscardConfirmation("))
        #expect(phoneTabSafety.contains("discardChangesAndCompletePendingNavigation"))
        #expect(phoneTabSafety.contains("requestID: requestID"))
        #expect(infoPlist.contains("<key>UIApplicationSupportsMultipleScenes</key>"))
        #expect(infoPlist.contains("<false/>"))
        #expect(project.components(
            separatedBy: "INFOPLIST_KEY_UIApplicationSceneManifest_Generation"
        ).count - 1 == 4)
        #expect(project.components(
            separatedBy: "INFOPLIST_KEY_UIApplicationSceneManifest_Generation[sdk="
        ).dropFirst().allSatisfy { $0.contains("]\" = NO;") })
        #expect(navigationGuard.contains("registration.hasUnsavedChanges()"))
        #expect(navigationGuard.contains("registration.requestDiscardConfirmation(requestID)"))
        #expect(navigationGuard.contains("pendingNavigationID = requestID"))
        #expect(navigationGuard.contains("pending.dismissConfirmation()"))
        #expect(workspace.contains("@State var navigationGuardRegistration"))
        #expect(workspace.contains("@State var navigationConfirmationRequestID") == false)
        #expect(workspaceNavigation.contains(
            "requestDiscardConfirmation: { [weak session] requestID in"
        ))
        #expect(workspaceNavigation.contains(
            "session?.requestDiscardConfirmation(for: requestID)"
        ))
        #expect(workspace.contains(".onDisappear") == false)
        #expect(route.contains("case editor") == false)
        #expect(route.contains("startsEditing") == false)
        #expect(router.contains("func presentEditTask(") == false)
    }

    @Test
    func unavailableRemoteSourcePreservesAndRecoversTheDraft() throws {
        let detail = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailView.swift"
        )
        let workspace = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailWorkspace.swift"
        )
        let workspaceRecovery = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailWorkspace+Recovery.swift"
        )
        let availability = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailAvailabilityViews.swift"
        )
        let refresh = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+RefreshLifecycle.swift"
        )
        let selection = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+Selection.swift"
        )

        #expect(detail.contains("@State private var initialDraft: TaskEditorDraft?"))
        #expect(workspace.contains("TaskDetailRecoveryList("))
        #expect(workspace.contains("isPresentingRecovery"))
        #expect(workspaceRecovery.contains("savePreservedDraftAsNew"))
        #expect(workspaceRecovery.contains("copyAsNew("))
        #expect(workspaceRecovery.contains(
            "recoveredDraft.baseline != session.sessionBaseline.baseline"
        ))
        #expect(workspaceRecovery.contains(
            "draftRecoveryReason = .sourceChanged"
        ))
        #expect(workspaceRecovery.contains("prepareRecoveryCopy") == false)
        #expect(availability.contains("TaskDetailDraftRecoverySection"))
        #expect(availability.contains("TaskDetailDraftRecoveryLoadFailureView"))
        #expect(availability.contains("task.editor.recovery.saveAsNew"))
        #expect(availability.contains("task.editor.recovery.discard"))
        #expect(refresh.contains("shouldRetainTaskDetailRoute("))
        #expect(selection.contains("protectsUnsavedChanges(for: taskID)"))
    }

    @Test
    func theSharedEditorSessionWorksInSheetsAndNavigationDestinations() throws {
        let editorView = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskEditorViews.swift"
        )
        let editorComponents = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskEditorComponents.swift"
        )
        let editorSession = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskEditorSession.swift"
        )
        let editorSafety = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskEditorSessionSafety.swift"
        )

        #expect(editorView.contains("struct TaskEditorSheet: View"))
        #expect(editorView.contains("NavigationStack {\n            TaskEditorPanel("))
        #expect(editorView.contains("struct TaskEditorPanel: View"))
        #expect(editorView.contains("@State private var session: TaskEditorSession"))
        #expect(editorView.components(separatedBy: "NavigationStack {").count - 1 == 1)
        #expect(editorView.contains(".navigationBarBackButtonHidden(true)"))
        #expect(editorView.contains("session.save("))
        #expect(editorView.contains(".taskEditorSessionSafety("))
        #expect(editorComponents.contains("Form {\n            TaskEditorSections("))
        #expect(editorComponents.contains("struct TaskEditorSections: View"))
        #expect(editorComponents.components(
            separatedBy: "TaskInfoEditorSection("
        ).count - 1 == 1)
        #expect(editorSession.contains("pendingReloadDraft = store.editorDraft(for: latestTask)"))
        #expect(editorSession.contains("sessionBaseline = latestDraft"))
        #expect(editorSafety.contains(".editorDiscardConfirmation("))
    }
}
