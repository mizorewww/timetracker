import Foundation
import SwiftUI

struct TaskDetailWorkspace: View {
    let store: TimeTrackerStore
    let taskID: UUID
    let returnDestination: TimeTrackerStore.DesktopDestination
    let dismissDetail: () -> Void
    let replaceDetail: (UUID) -> Void
    @State var session: TaskEditorSession
    @State var autosaveController: TaskDetailAutosaveController
    @State var navigationGuardRegistration = TaskDetailNavigationRegistrationToken()
    @State var isRecoveryLoaded = false
    @FocusState var focusedTextField: TaskEditorTextField?
    @FocusState var focusedChecklistDraftID: UUID?
    init(
        store: TimeTrackerStore,
        taskID: UUID,
        initialDraft: TaskEditorDraft,
        returnDestination: TimeTrackerStore.DesktopDestination,
        dismissDetail: @escaping () -> Void,
        replaceDetail: @escaping (UUID) -> Void
    ) {
        self.store = store
        self.taskID = taskID
        self.returnDestination = returnDestination
        self.dismissDetail = dismissDetail
        self.replaceDetail = replaceDetail
        let session = TaskEditorSession(store: store, initialDraft: initialDraft)
        _session = State(initialValue: session)
        _autosaveController = State(
            initialValue: .workspaceController(
                store: store,
                session: session,
                taskID: taskID,
                returnDestination: returnDestination,
                recoveryController: store.taskDraftRecoveryController
            )
        )
    }

    var body: some View {
        Group {
            if isRecoveryLoaded, let task = store.task(for: taskID) {
                workspace(for: task)
            } else if isRecoveryLoaded {
                ContentUnavailableView(
                    AppStrings.localized("task.empty.selectTask"),
                    systemImage: "checklist"
                )
            }
        }
        .taskDetailNavigation(
            store: store,
            taskID: taskID,
            preservingDestination: returnDestination
        )
        .taskEditorSessionSafety(
            session: session,
            discard: discardChanges,
            reload: reloadLatestDraft
        )
        .taskDetailAutosave(
            controller: autosaveController,
            recoveryController: store.taskDraftRecoveryController,
            sourceTaskID: taskID,
            request: autosaveRequest,
            focusedTextField: focusedTextField,
            focusedChecklistDraftID: focusedChecklistDraftID
        )
        .onChange(of: editorSourceToken) { _, sourceToken in
            guard let sourceToken else { return }
            session.synchronizeWithStoreIfClean(
                taskID: taskID,
                sourceBaseline: sourceToken.baseline,
                parentCandidateIDs: sourceToken.parentCandidateIDs
            )
        }
        .onChange(of: session.isDiscardConfirmationPresented) { _, isPresented in
            cancelPendingNavigationIfNeeded(
                isDiscardConfirmationPresented: isPresented
            )
        }
        .onChange(
            of: session.hasUnsavedChanges,
            updateNavigationGuardForDraftChanges
        )
        .onChange(of: autosaveController.status, handleAutosaveStatus)
        .onChange(of: store.isTaskDetailRouteValid(taskID)) { _, isRouteValid in
            guard isRouteValid == false else { return }
            dismissDetail()
        }
        .task {
            await loadPersistedDraftRecovery()
        }
        .onAppear(perform: registerNavigationGuard)
    }
}
