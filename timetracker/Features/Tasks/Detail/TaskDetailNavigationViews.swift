import SwiftUI

private struct TaskDetailNavigationModifier: ViewModifier {
    let store: TimeTrackerStore
    let taskID: UUID
    let session: TaskEditorSession
    let isSourceUnavailable: Bool
    let isAwaitingRecoveryCleanup: Bool
    let save: () -> Void
    let requestDiscard: () -> Void
    let preservingDestination: TimeTrackerStore.DesktopDestination
    @Environment(AppPresentationRouter.self) private var presentationRouter

    func body(content: Content) -> some View {
        content
            .navigationTitle(store.task(for: taskID)?.title ?? AppStrings.localized("task.detail.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationBarBackButtonHidden(session.hasUnsavedChanges)
            .toolbar {
                if session.hasUnsavedChanges {
                    if isAwaitingRecoveryCleanup == false {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(AppStrings.cancel, action: requestDiscard)
                                .keyboardShortcut(.cancelAction)
                                .accessibilityIdentifier("task.editor.cancel")
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(saveTitle, action: save)
                            .keyboardShortcut(.defaultAction)
                            .disabled(
                                isAwaitingRecoveryCleanup == false &&
                                    session.validation.isValid == false
                            )
                            .accessibilityIdentifier("task.editor.save")
                    }
                } else if let task = store.task(for: taskID) {
                    ToolbarItemGroup(placement: .primaryAction) {
                        if store.isTaskAvailableForTracking(task) {
                            addTimeButton(task)
                        }
                        moreMenu(task)
                    }
                }
            }
    }

    private var saveTitle: String {
        if isAwaitingRecoveryCleanup {
            return AppStrings.localized("tasks.recovery.finishCleanup")
        }
        return AppStrings.localized(
            isSourceUnavailable
                ? "task.editor.recovery.saveAsNew"
                : "common.save"
        )
    }

    private func addTimeButton(_ task: TaskNode) -> some View {
        Button {
            presentationRouter.presentManualTime(taskID: task.id, using: store)
        } label: {
            Label(AppStrings.addTime, systemImage: "calendar.badge.plus")
        }
        .accessibilityIdentifier("task.detail.addTime")
    }

    private func moreMenu(_ task: TaskNode) -> some View {
        Menu {
            TaskContextMenu(
                store: store,
                task: task,
                preservingDestination: preservingDestination
            )
        } label: {
            Label(AppStrings.localized("common.more"), systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("task.detail.more")
    }
}

extension View {
    func taskDetailNavigation(
        store: TimeTrackerStore,
        taskID: UUID,
        session: TaskEditorSession,
        isSourceUnavailable: Bool,
        isAwaitingRecoveryCleanup: Bool,
        save: @escaping () -> Void,
        requestDiscard: @escaping () -> Void,
        preservingDestination: TimeTrackerStore.DesktopDestination
    ) -> some View {
        modifier(
            TaskDetailNavigationModifier(
                store: store,
                taskID: taskID,
                session: session,
                isSourceUnavailable: isSourceUnavailable,
                isAwaitingRecoveryCleanup: isAwaitingRecoveryCleanup,
                save: save,
                requestDiscard: requestDiscard,
                preservingDestination: preservingDestination
            )
        )
    }
}
