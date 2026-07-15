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

    private var isRunning: Bool {
        store.activeSegment(for: task.id) != nil
    }

    var body: some View {
        rowContent
    }

    private var rowContent: some View {
        HStack(alignment: rowAlignment, spacing: 4) {
            disclosureButton
            Button(action: openTask) {
                TaskManagementRowContent(
                    store: store,
                    task: task,
                    isRunning: isRunning,
                    showsNavigationChevron: showsNavigationChevron
                )
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tasks.row.\(task.id.uuidString)")
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
