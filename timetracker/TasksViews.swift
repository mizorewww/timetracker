import SwiftUI

struct TasksView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var searchText = ""
    @State private var expandedTaskIDs: Set<UUID> = []

    private var searchResults: [TaskNode] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return store.tasks.filter { task in
            task.title.localizedCaseInsensitiveContains(trimmed) ||
            store.path(for: task).localizedCaseInsensitiveContains(trimmed) ||
            (task.notes?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    private var visibleRows: [TaskTreeDisplayRow] {
        var rows: [TaskTreeDisplayRow] = []

        func append(task: TaskNode, depth: Int) {
            let children = store.children(of: task)
            rows.append(TaskTreeDisplayRow(task: task, depth: depth, hasChildren: !children.isEmpty))
            guard expandedTaskIDs.contains(task.id) else { return }
            for child in children {
                append(task: child, depth: depth + 1)
            }
        }

        for root in store.rootTasks() {
            append(task: root, depth: 0)
        }

        return rows
    }

    var body: some View {
        List {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    ForEach(visibleRows) { row in
                        TaskManagementVisibleRow(
                            store: store,
                            row: row,
                            isExpanded: expandedTaskIDs.contains(row.task.id),
                            onToggleExpanded: {
                                toggleExpanded(row.task.id)
                            }
                        )
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
            expandedTaskIDs.formUnion(store.tasks.map(\.id))
        }
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedTaskIDs.contains(id) {
            expandedTaskIDs.remove(id)
        } else {
            expandedTaskIDs.insert(id)
        }
    }
}

struct TaskTreeDisplayRow: Identifiable {
    let task: TaskNode
    let depth: Int
    let hasChildren: Bool

    var id: UUID { task.id }
}

struct TaskManagementVisibleRow: View {
    @ObservedObject var store: TimeTrackerStore
    let row: TaskTreeDisplayRow
    let isExpanded: Bool
    let onToggleExpanded: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if row.hasChildren {
                Button {
                    onToggleExpanded()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 40, alignment: .center)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 22, height: 40)
            }

            TaskManagementFlatRow(store: store, task: row.task, depth: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 22)
    }
}

struct TaskManagementFlatRow: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode
    var depth: Int = 0
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    private var isRunning: Bool {
        store.activeSegments.contains { $0.taskID == task.id }
    }

    var body: some View {
        Button {
            openTask()
        } label: {
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
                        } else if task.status != .active {
                            TaskStatusBadge(status: task.status)
                        }
                    }

                    Text(store.path(for: task))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(DurationFormatter.compact(store.secondsForTaskToday(task)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)

                    let childCount = store.children(of: task).count
                    if childCount > 0 {
                        Text(String(format: AppStrings.localized("tasks.childCount"), childCount))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

#if os(iOS)
                if horizontalSizeClass == .compact {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
#endif
            }
            .padding(.leading, CGFloat(depth) * 10)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
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
    }

    private func openTask() {
#if os(iOS)
        if horizontalSizeClass == .compact {
            store.selectTask(task.id, revealInToday: false)
            store.presentEditTask(task)
            return
        }
#endif
        store.selectTask(task.id)
    }
}
