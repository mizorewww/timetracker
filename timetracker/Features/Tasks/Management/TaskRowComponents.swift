import SwiftUI

enum TaskMenuSurface {
    case contextual
    case pullDown
}

/// Per-row action eligibility shared by the context menu and the swipe actions
/// so the two renderers can never disagree about what a task allows.
struct TaskRowActionEligibility {
    let activeSegment: TimeSegment?
    let isAvailableForTracking: Bool
    let isEligibleAsParent: Bool
    let hasActiveTimerInSubtree: Bool

    init(store: TimeTrackerStore, task: TaskNode) {
        activeSegment = store.activeSegment(for: task.id)
        isAvailableForTracking = store.isTaskAvailableForTracking(task)
        isEligibleAsParent = store.isTaskEligibleAsParent(task)
        hasActiveTimerInSubtree = store.hasActiveTimer(inTaskSubtree: task.id)
    }
}

struct TaskMenuContent: View {
    let store: TimeTrackerStore
    let task: TaskNode
    @Environment(AppPresentationRouter.self) private var presentationRouter
    var preservingDestination: TimeTrackerStore.DesktopDestination?
    var surface: TaskMenuSurface = .contextual

    private var eligibility: TaskRowActionEligibility {
        TaskRowActionEligibility(store: store, task: task)
    }

    private var showsPrimaryActions: Bool {
        eligibility.activeSegment != nil ||
            eligibility.isAvailableForTracking ||
            eligibility.isEligibleAsParent
    }

    private var showsArchiveAction: Bool {
        guard store.isTaskVisible(task) else { return false }
        if eligibility.hasActiveTimerInSubtree {
            return surface == .pullDown
        }
        return true
    }

    var body: some View {
        if let activeSegment = eligibility.activeSegment {
            Button {
                store.stop(segment: activeSegment)
            } label: {
                Label(AppStrings.localized("timer.action.stop"), systemImage: "stop.fill")
            }
        } else if eligibility.isAvailableForTracking {
            Button {
                store.startTask(task)
            } label: {
                Label(AppStrings.localized("task.action.startTimer"), systemImage: "play.fill")
            }
        }

        if eligibility.isEligibleAsParent {
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

        if eligibility.isAvailableForTracking {
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
                .disabled(eligibility.hasActiveTimerInSubtree)
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

    private var eligibility: TaskRowActionEligibility {
        TaskRowActionEligibility(store: store, task: task)
    }

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading) {
                if let activeSegment = eligibility.activeSegment {
                    Button(role: .destructive) {
                        store.stop(segment: activeSegment)
                    } label: {
                        actionLabel(AppStrings.localized("timer.action.stop"), systemImage: "stop.fill")
                    }
                    .tint(.red)
                } else if eligibility.isAvailableForTracking {
                    Button {
                        store.startTask(task)
                    } label: {
                        actionLabel(AppStrings.localized("task.swipe.start"), systemImage: "play.fill")
                    }
                    .tint(.blue)
                }

                if eligibility.isEligibleAsParent {
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
                if eligibility.hasActiveTimerInSubtree == false {
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
