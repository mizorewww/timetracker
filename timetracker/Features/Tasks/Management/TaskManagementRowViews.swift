import SwiftUI

struct TaskManagementFlatRow: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode
    var treeDepth: Int = 0
    var hasChildren = false
    var isExpanded = false
    var toggleExpansion: (() -> Void)?
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    private var isRunning: Bool {
        store.activeSegments.contains { $0.taskID == task.id }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            disclosureButton
            TaskManagementRowContent(
                store: store,
                task: task,
                isRunning: isRunning,
                showsNavigationChevron: showsNavigationChevron
            )
        }
        .padding(.leading, CGFloat(treeDepth) * 14)
        .contentShape(Rectangle())
        .onTapGesture {
            openTask()
        }
        .contextMenu {
            TaskContextMenu(store: store, task: task)
        }
        .swipeActions(edge: .leading) {
            Button {
                store.startTask(task)
            } label: {
                Label(AppStrings.localized("task.swipe.start"), systemImage: "play.fill")
            }
            .tint(.blue)

            Button {
                store.presentNewTask(parentID: task.id)
            } label: {
                Label(AppStrings.localized("task.swipe.subtask"), systemImage: "plus")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button {
                store.presentEditTask(task)
            } label: {
                Label(AppStrings.edit, systemImage: "pencil")
            }
            .tint(.gray)

            Button(role: .destructive) {
                store.deleteSelectedTask(taskID: task.id)
            } label: {
                Label(AppStrings.delete, systemImage: "trash")
            }
        }
        #if os(iOS)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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
                    .frame(width: 16, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? AppStrings.localized("tasks.collapse") : AppStrings.localized("tasks.expand"))
        } else if treeDepth > 0 {
            Color.clear
                .frame(width: 16, height: 24)
        }
    }

    private func openTask() {
        #if os(iOS)
        if TaskListLayoutPolicy(horizontalSizeClass: horizontalSizeClass).usesCompactRows {
            store.selectTask(task.id, revealInToday: false)
            store.presentEditTask(task)
            return
        }
        #endif
        store.selectTask(task.id)
    }
}

private struct TaskManagementRowContent: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode
    let isRunning: Bool
    let showsNavigationChevron: Bool
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    var body: some View {
        #if os(iOS)
        if TaskListLayoutPolicy(horizontalSizeClass: horizontalSizeClass).usesCompactRows {
            compactBody
        } else {
            regularBody
        }
        #else
        regularBody
        #endif
    }

    @ViewBuilder
    private var regularBody: some View {
        let progress = store.checklistProgress(for: task.id)
        let rollup = store.rollup(for: task.id)
        HStack(spacing: 12) {
            TaskIcon(task: task, size: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(task.status == .completed ? .secondary : .primary)
                        .strikethrough(task.status == .completed)
                        .lineLimit(2)

                    if isRunning {
                        RunningStatusBadge()
                    }
                }

                Text(store.path(for: task))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if progress.totalCount > 0 || rollup?.isDisplayableForecast == true {
                    TaskProgressLine(progress: progress, rollup: rollup)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 3) {
                Text(DurationFormatter.compact(rollup?.workedSeconds ?? store.secondsForTaskTotalRollup(task)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                let childCount = store.children(of: task).count
                if childCount > 0 {
                    Text(String(format: AppStrings.localized("tasks.childCount"), childCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            TaskStatusBadge(status: task.status)

            if showsNavigationChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var compactBody: some View {
        let progress = store.checklistProgress(for: task.id)
        let rollup = store.rollup(for: task.id)
        HStack(alignment: .center, spacing: 10) {
            TaskIcon(task: task, size: 30)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(task.status == .completed ? .secondary : .primary)
                    .strikethrough(task.status == .completed)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    TaskStatusBadge(status: task.status)
                    if isRunning {
                        RunningStatusBadge()
                    }
                }

                if progress.totalCount > 0 {
                    CompactChecklistProgressLine(
                        progress: progress,
                        tint: Color(hex: task.colorHex) ?? .blue
                    )
                }

                if rollup?.isDisplayableForecast == true {
                    TaskProgressLine(progress: progress, rollup: rollup, showsChecklist: false)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(DurationFormatter.compact(rollup?.workedSeconds ?? store.secondsForTaskTotalRollup(task)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                let childCount = store.children(of: task).count
                if childCount > 0 {
                    Text(String(format: AppStrings.localized("tasks.childCount"), childCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if showsNavigationChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
