import SwiftUI

struct TaskDetailView: View {
    let store: TimeTrackerStore
    let taskID: UUID
    let returnDestination: TimeTrackerStore.DesktopDestination
    let dismissDetail: () -> Void
    let replaceDetail: (UUID) -> Void

    init(
        store: TimeTrackerStore,
        taskID: UUID,
        returnDestination: TimeTrackerStore.DesktopDestination = .tasks,
        dismissDetail: @escaping () -> Void,
        replaceDetail: @escaping (UUID) -> Void
    ) {
        self.store = store
        self.taskID = taskID
        self.returnDestination = returnDestination
        self.dismissDetail = dismissDetail
        self.replaceDetail = replaceDetail
    }

    var body: some View {
        TaskDetailWorkspaceLoader(
            store: store,
            taskID: taskID,
            returnDestination: returnDestination,
            dismissDetail: dismissDetail,
            replaceDetail: replaceDetail
        )
        .id(taskID)
    }
}

/// Builds the editor session once per task, restores any persisted recovery
/// draft into it, and only then mounts the workspace, so the workspace never
/// renders or autosaves an unrecovered draft.
private struct TaskDetailWorkspaceLoader: View {
    let store: TimeTrackerStore
    let taskID: UUID
    let returnDestination: TimeTrackerStore.DesktopDestination
    let dismissDetail: () -> Void
    let replaceDetail: (UUID) -> Void
    @State private var prepared: TaskDetailWorkspace.Prepared?
    @State private var isTaskMissing = false

    var body: some View {
        Group {
            if let prepared {
                TaskDetailWorkspace(
                    store: store,
                    taskID: taskID,
                    prepared: prepared,
                    returnDestination: returnDestination,
                    dismissDetail: dismissDetail,
                    replaceDetail: replaceDetail
                )
            } else if isTaskMissing {
                ContentUnavailableView(
                    AppStrings.localized("task.empty.selectTask"),
                    systemImage: "checklist"
                )
            } else {
                // A real view, not an empty branch: on macOS the in-place
                // detail swap never appears while the Group is empty, so the
                // `.task` below would never run.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard let task = store.task(for: taskID) else {
                isTaskMissing = true
                return
            }
            let session = TaskEditorSession(
                store: store,
                initialDraft: store.editorDraft(for: task)
            )
            let recovery = store.taskDraftRecoveryController
            let recoveredDraft = try? await recovery.load(
                for: taskID,
                currentDraft: session.sessionBaseline
            )
            await recovery.removeExpired()
            guard Task.isCancelled == false else { return }
            if let recoveredDraft {
                session.restoreRecoveredDraft(recoveredDraft)
            }
            prepared = TaskDetailWorkspace.Prepared(
                session: session,
                autosaveController: .workspaceController(
                    store: store,
                    session: session,
                    taskID: taskID,
                    returnDestination: returnDestination,
                    recoveryController: recovery
                )
            )
        }
    }
}
