import SwiftUI

struct SidebarTaskTreeRowContainer: View {
    let store: TimeTrackerStore
    let row: TaskTreeRowModel
    @Binding var expansionState: TaskExpansionState

    var body: some View {
        if let task = store.task(for: row.taskID) {
            SidebarTaskTreeRow(
                store: store,
                task: task,
                row: row,
                expansionState: $expansionState
            )
        }
    }
}

struct SidebarTaskTreeRow: View {
    let store: TimeTrackerStore
    let task: TaskNode
    let row: TaskTreeRowModel
    @Binding var expansionState: TaskExpansionState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            disclosureControl
            taskContent
        }
        .frame(minHeight: minimumRowHeight)
        .padding(.leading, CGFloat(min(row.depth, 6)) * 14)
        .contentShape(Rectangle())
        .contextMenu {
            TaskMenuContent(
                store: store,
                task: task
            )
        }
        .taskRowSwipeActions(
            store: store,
            task: task,
            labelStyle: .iconOnly
        )
    }

    @ViewBuilder
    private var disclosureControl: some View {
        switch TaskTreeDisclosureSlot(depth: row.depth, hasChildren: row.hasChildren) {
        case .control:
            Button {
                expansionState.toggle(task.id)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                    .animation(
                        reduceMotion ? nil : AppMotion.stateChange,
                        value: row.isExpanded
                    )
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 18)
            }
            .buttonStyle(.plain)
            .frame(width: disclosureTargetSize, height: disclosureTargetSize)
            .contentShape(Rectangle())
            .accessibilityIdentifier("sidebar.disclosure.\(task.id.uuidString)")
            .accessibilityLabel(
                "\(task.title), \(row.isExpanded ? AppStrings.localized("task.tree.collapse") : AppStrings.localized("task.tree.expand"))"
            )
        case .reserved:
            Color.clear
                .frame(width: disclosureTargetSize, height: disclosureTargetSize)
                .accessibilityHidden(true)
        case .none:
            EmptyView()
        }
    }

    private var taskContent: some View {
        let progress = store.checklistProgress(for: task.id)
        let childCount = row.childCount
        let isRunning = store.activeSegment(for: task.id) != nil

        return TaskSummaryRow(
            presentation: store.taskIdentityPresentation(for: task),
            context: .hierarchical,
            iconSize: 24,
            metadata: TaskSummaryRowMetadata(
                checklistProgress: progress.totalCount > 0 ? progress : nil,
                isRunning: isRunning
            ),
            layout: .inline
        )
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("sidebar.task.\(task.id.uuidString)")
        .accessibilityLabel(task.title)
        .accessibilityValue(
            accessibilityValue(
                progress: progress,
                childCount: childCount,
                isRunning: isRunning
            )
        )
    }

    private func accessibilityValue(
        progress: ChecklistProgress,
        childCount: Int,
        isRunning: Bool
    ) -> String {
        var values: [String] = []
        if isRunning {
            values.append(AppStrings.running)
        }
        if progress.totalCount > 0 {
            values.append(progress.label)
        }
        if childCount > 0 {
            values.append(
                String.localizedStringWithFormat(
                    AppStrings.localized("tasks.childCount"),
                    childCount
                )
            )
        }
        return values.joined(separator: ", ")
    }

    private var disclosureTargetSize: CGFloat {
        #if os(iOS)
        44
        #else
        24
        #endif
    }

    private var minimumRowHeight: CGFloat? {
        #if os(iOS)
        44
        #else
        nil
        #endif
    }
}
