import SwiftUI

enum TaskMenuSurface {
    case contextual
    case pullDown
}

struct TaskMenuContent: View {
    let store: TimeTrackerStore
    let task: TaskNode
    @Environment(AppPresentationRouter.self) private var presentationRouter
    var preservingDestination: TimeTrackerStore.DesktopDestination?
    var surface: TaskMenuSurface = .contextual

    private var activeSegment: TimeSegment? {
        store.activeSegment(for: task.id)
    }

    private var isAvailableForTracking: Bool {
        store.isTaskAvailableForTracking(task)
    }

    private var isEligibleAsParent: Bool {
        store.isTaskEligibleAsParent(task)
    }

    private var hasActiveTimerInSubtree: Bool {
        store.hasActiveTimer(inTaskSubtree: task.id)
    }

    private var showsPrimaryActions: Bool {
        activeSegment != nil ||
            isAvailableForTracking ||
            isEligibleAsParent
    }

    private var showsArchiveAction: Bool {
        guard store.isTaskVisible(task) else { return false }
        if hasActiveTimerInSubtree {
            return surface == .pullDown
        }
        return true
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

        if isEligibleAsParent {
            Button {
                presentationRouter.presentNewTask(
                    using: store,
                    parentID: task.id,
                    preservingDestination: preservingDestination
                )
            } label: {
                Label(AppStrings.localized("task.action.newSubtask"), systemImage: "plus")
            }
        }

        if isAvailableForTracking {
            Button {
                presentationRouter.presentManualTime(taskID: task.id, using: store)
            } label: {
                Label(AppStrings.localized("task.action.addManualTime"), systemImage: "calendar.badge.plus")
            }
        }

        if showsPrimaryActions, showsArchiveAction {
            Divider()
        }

        if showsArchiveAction {
            archiveButton
                .disabled(hasActiveTimerInSubtree)
        }
    }

    private var archiveButton: some View {
        Button {
            store.archiveTaskProtectingUnsavedChanges(task.id)
        } label: {
            Label(AppStrings.localized("task.action.archive"), systemImage: "archivebox")
        }
        .accessibilityIdentifier("task.action.archive.\(task.id.uuidString)")
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

    private var activeSegment: TimeSegment? {
        store.activeSegment(for: task.id)
    }

    private var isAvailableForTracking: Bool {
        store.isTaskAvailableForTracking(task)
    }

    private var isEligibleAsParent: Bool {
        store.isTaskEligibleAsParent(task)
    }

    private var hasActiveTimerInSubtree: Bool {
        store.hasActiveTimer(inTaskSubtree: task.id)
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

                if isEligibleAsParent {
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
                if hasActiveTimerInSubtree == false {
                    Button {
                        store.archiveTaskProtectingUnsavedChanges(task.id)
                    } label: {
                        actionLabel(
                            AppStrings.localized("task.action.archive"),
                            systemImage: "archivebox"
                        )
                    }
                    .tint(.blue)
                    .accessibilityIdentifier("task.swipe.archive.\(task.id.uuidString)")
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
        preservingDestination: TimeTrackerStore.DesktopDestination? = nil
    ) -> some View {
        modifier(
            TaskRowSwipeActions(
                store: store,
                task: task,
                labelStyle: labelStyle,
                preservingDestination: preservingDestination
            )
        )
    }
}
