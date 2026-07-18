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
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        HStack(spacing: 8) {
            disclosureControl
            taskContent
        }
        .padding(.leading, CGFloat(min(row.depth, 6)) * 14)
        .contentShape(Rectangle())
        .taskSelectionPulse(
            selectedID: store.selectedTaskPulseID,
            itemID: task.id,
            pulseToken: store.selectedTaskPulseToken
        )
        .contextMenu {
            TaskContextMenu(
                store: store,
                task: task,
                editTask: { store.openTaskEditor(task.id) },
                requestDelete: { isDeleteConfirmationPresented = true }
            )
        }
        .confirmationDialog(
            AppStrings.localized("task.delete.confirm.title"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(AppStrings.delete, role: .destructive) {
                store.deleteSelectedTask(taskID: task.id)
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("task.delete.confirm.message"))
        }
        .taskRowSwipeActions(
            store: store,
            task: task,
            labelStyle: .iconOnly,
            requestDelete: { isDeleteConfirmationPresented = true }
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
        let blocked = task.status != .completed && !store.isTaskAvailableForTracking(task)

        return HStack(spacing: 8) {
            Image(systemName: task.iconName ?? "checkmark.circle")
                .foregroundStyle(Color(hex: task.colorHex) ?? .blue)
                .accessibilityHidden(true)

            Text(task.title)
                .strikethrough(task.status == .completed)
                .foregroundStyle(task.status == .completed ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if progress.totalCount > 0 {
                Text(progress.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if childCount > 0 {
                Text("\(childCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: blocked ? "pause.circle.fill" : task.status.symbolName)
                .font(.caption)
                .foregroundStyle(
                    blocked ? .orange : (Color(hex: task.status.colorHex) ?? .secondary)
                )
                .frame(width: 14)
                .accessibilityHidden(true)
                .help(
                    blocked
                        ? AppStrings.localized("task.status.blockedByCompletion")
                        : task.status.displayName
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("sidebar.task.\(task.id.uuidString)")
        .accessibilityLabel(task.title)
        .accessibilityValue(
            accessibilityValue(progress: progress, childCount: childCount, blocked: blocked)
        )
    }

    private func accessibilityValue(
        progress: ChecklistProgress,
        childCount: Int,
        blocked: Bool
    ) -> String {
        var values = [
            blocked
                ? AppStrings.localized("task.status.blockedByCompletion")
                : task.status.displayName
        ]
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
}
