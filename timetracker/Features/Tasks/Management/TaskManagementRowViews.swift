import SwiftUI

struct TaskManagementFlatRow: View {
    let store: TimeTrackerStore
    let task: TaskNode
    var treeDepth: Int = 0
    var childCount = 0
    var isExpanded = false
    var toggleExpansion: (() -> Void)?
    var identityContext: TaskIdentityPresentation.Context = .hierarchical
    let openTaskDetail: (TaskNode) -> Void
#if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
#endif

    var body: some View {
        let rollup = store.rollup(for: task.id)
        let presentation = TaskManagementRowPresentation(
            identity: store.taskIdentityPresentation(for: task),
            identityContext: identityContext,
            progress: store.checklistProgress(for: task.id),
            rollup: rollup,
            workedSeconds: rollup?.workedSeconds ?? store.secondsForTaskTotalRollup(task),
            childCount: childCount,
            isRunning: store.activeSegment(for: task.id) != nil
        )
        rowContent(presentation: presentation)
    }

    private func rowContent(presentation: TaskManagementRowPresentation) -> some View {
        let accessibility = TaskManagementRowAccessibilitySnapshot(
            task: task,
            presentation: presentation
        )

        return HStack(alignment: rowAlignment, spacing: 4) {
            disclosureButton
            Button(action: openTask) {
                TaskManagementRowContent(
                    presentation: presentation,
                    showsNavigationChevron: showsNavigationChevron
                )
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tasks.row.\(task.id.uuidString)")
            .accessibilityLabel(accessibility.label)
            .accessibilityValue(accessibility.value)
            .accessibilityHint(AppStrings.localized("tasks.openDetail"))
        }
        .padding(.leading, CGFloat(min(treeDepth, 6)) * 12)
        .contextMenu {
            TaskContextMenu(
                store: store,
                task: task,
                preservingDestination: .tasks
            )
        }
        .taskRowSwipeActions(
            store: store,
            task: task,
            preservingDestination: .tasks
        )
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
        true
        #else
        false
        #endif
    }

    @ViewBuilder
    private var disclosureButton: some View {
        switch TaskTreeDisclosureSlot(depth: treeDepth, hasChildren: childCount > 0) {
        case .control:
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
        case .reserved:
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        case .none:
            EmptyView()
        }
    }

    private func openTask() {
        openTaskDetail(task)
    }
}
