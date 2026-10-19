import Foundation
import SwiftUI

struct TaskDetailWorkspace: View {
    let store: TimeTrackerStore
    let taskID: UUID
    let returnDestination: TimeTrackerStore.DesktopDestination
    let dismissDetail: () -> Void
    let replaceDetail: (UUID) -> Void
    let session: TaskEditorSession
    let autosaveController: TaskDetailAutosaveController
    @FocusState var focusedTextField: TaskEditorTextField?
    @FocusState var focusedChecklistDraftID: UUID?

    /// Session and autosave controller created once by the loader.
    struct Prepared {
        let session: TaskEditorSession
        let autosaveController: TaskDetailAutosaveController
    }

    init(
        store: TimeTrackerStore,
        taskID: UUID,
        prepared: Prepared,
        returnDestination: TimeTrackerStore.DesktopDestination,
        dismissDetail: @escaping () -> Void,
        replaceDetail: @escaping (UUID) -> Void
    ) {
        self.store = store
        self.taskID = taskID
        session = prepared.session
        autosaveController = prepared.autosaveController
        self.returnDestination = returnDestination
        self.dismissDetail = dismissDetail
        self.replaceDetail = replaceDetail
    }

    var body: some View {
        Group {
            if let task = store.task(for: taskID) {
                workspace(for: task)
            } else {
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
        .taskEditorStaleDraftAlert(
            session: session,
            reload: reloadLatestDraft
        )
        .taskDetailAutosave(
            taskID: taskID,
            controller: autosaveController,
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
        .onChange(of: autosaveController.status, handleAutosaveStatus)
        .onChange(of: store.isTaskDetailRouteValid(taskID)) { _, isRouteValid in
            guard isRouteValid == false else { return }
            dismissDetail()
        }
    }
}
