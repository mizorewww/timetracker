import SwiftUI

struct TaskDetailView: View {
    let store: TimeTrackerStore
    let taskID: UUID
    let returnDestination: TimeTrackerStore.DesktopDestination
    let dismissDetail: () -> Void
    let replaceDetail: (UUID) -> Void
    @State private var initialDraft: TaskEditorDraft?

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
        _initialDraft = State(
            initialValue: store.task(for: taskID).map {
                store.editorDraft(for: $0)
            }
        )
    }

    var body: some View {
        if let initialDraft {
            TaskDetailWorkspace(
                store: store,
                taskID: taskID,
                initialDraft: initialDraft,
                returnDestination: returnDestination,
                dismissDetail: dismissDetail,
                replaceDetail: replaceDetail
            )
            .id(taskID)
        } else {
            ContentUnavailableView(
                AppStrings.localized("task.empty.selectTask"),
                systemImage: "checklist"
            )
        }
    }
}
