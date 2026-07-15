import SwiftUI

struct TaskManagementFlatRow: View {
    let store: TimeTrackerStore
    let task: TaskNode
    var treeDepth: Int = 0
    var hasChildren = false
    var isExpanded = false
    var toggleExpansion: (() -> Void)?
    var openTaskDetail: ((TaskNode) -> Void)?
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
#endif
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        let rollup = store.rollup(for: task.id)
        let presentation = TaskManagementRowPresentation(
            path: store.path(for: task),
            progress: store.checklistProgress(for: task.id),
            rollup: rollup,
            workedSeconds: rollup?.workedSeconds ?? store.secondsForTaskTotalRollup(task),
            childCount: store.children(of: task).count,
            isAvailableForTracking: store.isTaskAvailableForTracking(task),
            isRunning: store.activeSegment(for: task.id) != nil
        )
        rowContent(presentation: presentation)
    }

    private func rowContent(presentation: TaskManagementRowPresentation) -> some View {
        HStack(alignment: rowAlignment, spacing: 4) {
            disclosureButton
            Button(action: openTask) {
                TaskManagementRowContent(
                    task: task,
                    presentation: presentation,
                    showsNavigationChevron: showsNavigationChevron
                )
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tasks.row.\(task.id.uuidString)")
            .accessibilityLabel(task.title)
            .accessibilityValue(accessibilitySummary(for: presentation))
            .accessibilityHint(AppStrings.localized("tasks.openDetail"))
        }
        .padding(.leading, CGFloat(min(treeDepth, 6)) * 12)
        .contextMenu {
            TaskContextMenu(
                store: store,
                task: task,
                preservingDestination: .tasks,
                requestDelete: { isDeleteConfirmationPresented = true }
            )
        }
        .confirmationDialog(
            AppStrings.localized("task.delete.confirm.title"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(AppStrings.delete, role: .destructive) {
                store.deleteSelectedTask(taskID: task.id, preservingDestination: .tasks)
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("task.delete.confirm.message"))
        }
        .taskRowSwipeActions(store: store, task: task, preservingDestination: .tasks)
        #if os(iOS)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        #endif
    }

    private var rowAlignment: VerticalAlignment {
        #if os(iOS)
        dynamicTypeSize.isAccessibilitySize ? .top : .center
        #else
        .center
        #endif
    }

    private var showsNavigationChevron: Bool {
        #if os(iOS)
        TaskListLayoutPolicy(horizontalSizeClass: horizontalSizeClass)
            .showsNavigationChevron(hasChildren: hasChildren)
        #else
        false
        #endif
    }

    private func accessibilitySummary(for presentation: TaskManagementRowPresentation) -> String {
        var components = [task.status.displayName]

        if !presentation.isAvailableForTracking, task.status != .completed {
            components[0] = AppStrings.localized("task.status.blockedByCompletion")
        }
        if presentation.path.isEmpty == false,
           presentation.path.localizedCaseInsensitiveCompare(task.title) != .orderedSame {
            components.append(presentation.path)
        }
        if presentation.isRunning {
            components.append(AppStrings.running)
        }
        components.append(
            String(
                format: AppStrings.localized("tasks.workedFormat"),
                DurationFormatter.compact(presentation.workedSeconds)
            )
        )
        if presentation.progress.totalCount > 0 {
            components.append(
                String(
                    format: AppStrings.localized("checklist.progressFormat"),
                    presentation.progress.completedCount,
                    presentation.progress.totalCount
                )
            )
        }
        if presentation.rollup?.isDisplayableForecast == true,
           let remainingSeconds = presentation.rollup?.remainingSeconds {
            components.append(
                String(
                    format: AppStrings.localized("forecast.remainingFormat"),
                    DurationFormatter.compact(remainingSeconds)
                )
            )
        }
        if presentation.childCount > 0 {
            components.append(
                String(
                    format: AppStrings.localized("tasks.childCount"),
                    presentation.childCount
                )
            )
        }
        return ListFormatter.localizedString(byJoining: components)
    }

    @ViewBuilder
    private var disclosureButton: some View {
        if hasChildren {
            Button {
                toggleExpansion?()
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tasks.disclosure.\(task.id.uuidString)")
            .accessibilityLabel(isExpanded ? AppStrings.localized("tasks.collapse") : AppStrings.localized("tasks.expand"))
            .accessibilityValue(task.title)
        } else if treeDepth > 0 {
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(width: 4, height: 44)
                .accessibilityHidden(true)
        }
    }

    private func openTask() {
        store.selectTask(task.id, revealInToday: false)
        openTaskDetail?(task)
    }
}
