import SwiftUI

struct TasksView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var searchText = ""
    @State private var expansionState = TaskExpansionState()

    private var searchResults: [TaskNode] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return store.tasks.filter { task in
            task.title.localizedCaseInsensitiveContains(trimmed) ||
            store.path(for: task).localizedCaseInsensitiveContains(trimmed) ||
            (task.notes?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        List {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    ForEach(store.taskTreeRows(expandedTaskIDs: expansionState.expandedTaskIDs)) { row in
                        if let task = store.task(for: row.taskID) {
                            TaskManagementFlatRow(
                                store: store,
                                task: task,
                                treeDepth: row.depth,
                                hasChildren: row.hasChildren,
                                isExpanded: row.isExpanded,
                                toggleExpansion: {
                                    expansionState.toggle(row.taskID)
                                }
                            )
                        }
                    }
                } header: {
                    Text(.app("tasks.tree"))
                } footer: {
                    Text(.app("tasks.tree.footer"))
                }
            } else if searchResults.isEmpty {
                EmptyStateRow(title: AppStrings.localized("tasks.empty.search"), icon: "magnifyingglass")
            } else {
                Section(AppStrings.localized("tasks.searchResults")) {
                    ForEach(searchResults, id: \.id) { task in
                        TaskManagementFlatRow(store: store, task: task)
                    }
                }
            }

            Section {
                Button {
                    store.presentNewTask()
                } label: {
                    Label(AppStrings.localized("tasks.newRoot"), systemImage: "plus")
                }
            }
        }
        .navigationTitle(AppStrings.tasks)
        .searchable(text: $searchText, prompt: AppStrings.localized("tasks.searchPrompt"))
        #if os(iOS)
        .listStyle(.insetGrouped)
        .scrollBounceBehavior(.basedOnSize)
        #else
        .listStyle(.inset)
        #endif
        .toolbar {
            Button {
                store.presentNewTask()
            } label: {
                Image(systemName: "plus")
            }
        }
        .onAppear {
            for task in store.tasks {
                expansionState.expand(task.id)
            }
        }
    }
}

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
                        Text(AppStrings.running)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }

                HStack(spacing: 6) {
                    Text(store.path(for: task))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

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
                        Text(AppStrings.running)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
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

private struct CompactChecklistProgressLine: View {
    let progress: ChecklistProgress
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            ProgressView(value: progress.fraction)
                .tint(tint)
                .frame(maxWidth: 76)

            Text(String(format: AppStrings.localized("checklist.progressFormat"), progress.completedCount, progress.totalCount))
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct TaskProgressLine: View {
    let progress: ChecklistProgress
    let rollup: TaskRollup?
    var showsChecklist = true

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                if showsChecklist {
                    checklistLabel
                }
                if let remainingText {
                    Text(remainingText)
                }
                if let daysText {
                    Text(daysText)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                if showsChecklist {
                    checklistLabel
                }
                if let remainingText {
                    Text(remainingText)
                }
                if let daysText {
                    Text(daysText)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var checklistLabel: some View {
        HStack(spacing: 5) {
            if progress.totalCount > 0 {
                ProgressView(value: progress.fraction)
                    .frame(width: 48)
                Text(String(format: AppStrings.localized("checklist.progressFormat"), progress.completedCount, progress.totalCount))
            } else {
                Text(AppStrings.localized("checklist.noItems"))
            }
        }
    }

    private var remainingText: String? {
        guard rollup?.isDisplayableForecast == true, let remaining = rollup?.remainingSeconds else { return nil }
        return String(format: AppStrings.localized("forecast.remainingFormat"), DurationFormatter.compact(remaining))
    }

    private var daysText: String? {
        guard rollup?.isDisplayableForecast == true, let rollup else { return nil }
        return rollup.projectedDaysDisplayText
    }
}
