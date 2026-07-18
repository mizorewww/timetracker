import SwiftUI

struct TaskContextMenu: View {
    let store: TimeTrackerStore
    let task: TaskNode
    @Environment(AppPresentationRouter.self) private var presentationRouter
    var preservingDestination: TimeTrackerStore.DesktopDestination? = nil
    let editTask: () -> Void
    let requestDelete: () -> Void

    private var activeSegment: TimeSegment? {
        store.activeSegment(for: task.id)
    }

    private var isAvailableForTracking: Bool {
        store.isTaskAvailableForTracking(task)
    }

    private var completedWorkBlocker: TaskNode? {
        store.completedWorkBlocker(for: task)
    }

    private var reopenActionTitle: String {
        guard let completedWorkBlocker, completedWorkBlocker.id != task.id else {
            return AppStrings.localized("task.action.reopen")
        }
        return String(
            format: AppStrings.localized("task.action.reopenAncestorFormat"),
            completedWorkBlocker.title
        )
    }

    private var hasActiveTimerInSubtree: Bool {
        store.hasActiveTimer(inTaskSubtree: task.id)
    }

    var body: some View {
        if let activeSegment {
            Button {
                store.stop(segment: activeSegment)
            } label: {
                Label(AppStrings.localized("timer.action.stop"), systemImage: "stop.fill")
            }
        } else if isAvailableForTracking {
            Button {
                store.startTask(task)
            } label: {
                Label(AppStrings.localized("task.action.startTimer"), systemImage: "play.fill")
            }
        }

        if completedWorkBlocker != nil {
            Button {
                store.reopenTaskForWork(task.id)
            } label: {
                Label(reopenActionTitle, systemImage: "arrow.uturn.backward.circle")
            }
        }

        if isAvailableForTracking {
            Button {
                presentationRouter.presentNewTask(
                    using: store,
                    parentID: task.id,
                    preservingDestination: preservingDestination
                )
            } label: {
                Label(AppStrings.localized("task.action.newSubtask"), systemImage: "plus")
            }

            Button {
                presentationRouter.presentManualTime(taskID: task.id, using: store)
            } label: {
                Label(AppStrings.localized("task.action.addManualTime"), systemImage: "calendar.badge.plus")
            }
        }

        Menu(AppStrings.localized("task.status.menu")) {
            ForEach(TaskStatus.editableCases, id: \.self) { status in
                if status == .completed,
                   task.status != .completed,
                   hasActiveTimerInSubtree {
                    Button {} label: {
                        Label(
                            AppStrings.localized("task.action.complete.stopFirst"),
                            systemImage: status.symbolName
                        )
                    }
                    .disabled(true)
                } else {
                    Button {
                        if status == .active, completedWorkBlocker != nil {
                            store.reopenTaskForWork(task.id)
                        } else {
                            store.setTaskStatus(status, taskID: task.id)
                        }
                    } label: {
                        Label(status.displayName, systemImage: status.symbolName)
                    }
                }
            }
        }

        Divider()

        Button(action: editTask) {
            Label(AppStrings.edit, systemImage: "pencil")
        }
        .accessibilityIdentifier("task.context.edit")

        if store.isTaskVisible(task) {
            if hasActiveTimerInSubtree {
                Button {} label: {
                    Label(AppStrings.localized("task.action.archive.stopFirst"), systemImage: "archivebox")
                }
                .disabled(true)
            } else {
                Button {
                    store.archiveSelectedTask(taskID: task.id)
                } label: {
                    Label(AppStrings.localized("task.action.archive"), systemImage: "archivebox")
                }
            }
        }

        Button(role: .destructive) {
            requestDelete()
        } label: {
            Label(AppStrings.delete, systemImage: "trash")
        }
    }
}

enum TaskRowSwipeLabelStyle {
    case titleAndIcon
    case iconOnly
}

struct TaskRowSwipeActions: ViewModifier {
    let store: TimeTrackerStore
    let task: TaskNode
    @Environment(AppPresentationRouter.self) private var presentationRouter
    var labelStyle: TaskRowSwipeLabelStyle = .titleAndIcon
    var preservingDestination: TimeTrackerStore.DesktopDestination?
    let requestDelete: () -> Void

    private var activeSegment: TimeSegment? {
        store.activeSegment(for: task.id)
    }

    private var isAvailableForTracking: Bool {
        store.isTaskAvailableForTracking(task)
    }

    private var completedWorkBlocker: TaskNode? {
        store.completedWorkBlocker(for: task)
    }

    private var reopenActionTitle: String {
        guard let completedWorkBlocker, completedWorkBlocker.id != task.id else {
            return AppStrings.localized("task.action.reopen")
        }
        return String(
            format: AppStrings.localized("task.action.reopenAncestorFormat"),
            completedWorkBlocker.title
        )
    }

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading) {
                if let activeSegment {
                    Button(role: .destructive) {
                        store.stop(segment: activeSegment)
                    } label: {
                        actionLabel(AppStrings.localized("timer.action.stop"), systemImage: "stop.fill")
                    }
                    .tint(.red)
                } else if isAvailableForTracking {
                    Button {
                        store.startTask(task)
                    } label: {
                        actionLabel(AppStrings.localized("task.swipe.start"), systemImage: "play.fill")
                    }
                    .tint(.blue)
                }

                if completedWorkBlocker != nil {
                    Button {
                        store.reopenTaskForWork(task.id)
                    } label: {
                        actionLabel(reopenActionTitle, systemImage: "arrow.uturn.backward.circle")
                    }
                    .tint(.orange)
                }

                if isAvailableForTracking {
                    Button {
                        presentationRouter.presentNewTask(
                            using: store,
                            parentID: task.id,
                            preservingDestination: preservingDestination
                        )
                    } label: {
                        actionLabel(AppStrings.localized("task.swipe.subtask"), systemImage: "plus")
                    }
                    .tint(.green)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    store.openTaskEditor(task.id)
                } label: {
                    actionLabel(AppStrings.edit, systemImage: "pencil")
                }
                .tint(.gray)

                Button(role: .destructive) {
                    requestDelete()
                } label: {
                    actionLabel(AppStrings.delete, systemImage: "trash")
                }
            }
    }

    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String) -> some View {
        switch labelStyle {
        case .titleAndIcon:
            Label(title, systemImage: systemImage)
        case .iconOnly:
            Image(systemName: systemImage)
                .accessibilityLabel(title)
        }
    }
}

extension View {
    func taskRowSwipeActions(
        store: TimeTrackerStore,
        task: TaskNode,
        labelStyle: TaskRowSwipeLabelStyle = .titleAndIcon,
        preservingDestination: TimeTrackerStore.DesktopDestination? = nil,
        requestDelete: @escaping () -> Void
    ) -> some View {
        modifier(
            TaskRowSwipeActions(
                store: store,
                task: task,
                labelStyle: labelStyle,
                preservingDestination: preservingDestination,
                requestDelete: requestDelete
            )
        )
    }
}
