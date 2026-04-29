import SwiftUI

struct QuickStartSection: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var isEditorPresented = false

    private var selectedIDs: [UUID] {
        store.preferences.quickStartTaskIDs
    }

    private var pinnedTasks: [TaskNode] {
        selectedIDs.compactMap { store.task(for: $0) }
            .filter { $0.deletedAt == nil && $0.status != .archived }
    }

    private var recentFillTasks: [TaskNode] {
        store.frequentRecentTasks(
            excluding: Set(pinnedTasks.map(\.id)),
            limit: 3
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppStrings.quickStart)
                        .font(.headline)
                    Text(AppStrings.localized("quickStart.defaultHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isEditorPresented = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .help(AppStrings.localized("quickStart.edit"))
            }

            if pinnedTasks.isEmpty && recentFillTasks.isEmpty {
                ContentUnavailableView(
                    AppStrings.localized("quickStart.empty.title"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(.app("quickStart.empty.description"))
                )
                .frame(maxWidth: .infinity, minHeight: 104)
            } else {
                if !pinnedTasks.isEmpty {
                    QuickStartTaskGroup(
                        title: AppStrings.localized("quickStart.pinnedTasks"),
                        tasks: pinnedTasks,
                        store: store
                    )
                }

                if !recentFillTasks.isEmpty {
                    QuickStartTaskGroup(
                        title: AppStrings.localized("quickStart.recentTasks"),
                        tasks: recentFillTasks,
                        store: store
                    )
                }
            }
        }
        .sheet(isPresented: $isEditorPresented) {
            QuickStartEditorSheet(
                store: store,
                selectedIDs: selectedIDs,
                onSave: { ids in
                    store.setQuickStartTaskIDs(ids)
                }
            )
        }
    }
}

private struct QuickStartTaskGroup: View {
    let title: String
    let tasks: [TaskNode]
    @ObservedObject var store: TimeTrackerStore

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tasks, id: \.id) { task in
                    QuickStartTaskButton(task: task) {
                        store.startTask(task)
                    }
                }
            }
        }
    }
}

private struct QuickStartTaskButton: View {
    let task: TaskNode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: task.iconName ?? "play")
                    .foregroundStyle(Color(hex: task.colorHex) ?? .blue)
                    .frame(width: 18)
                Text(task.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(Color(hex: task.colorHex) ?? .blue)
    }
}

struct QuickStartEditorSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: [UUID]
    let onSave: ([UUID]) -> Void

    init(store: TimeTrackerStore, selectedIDs: [UUID], onSave: @escaping ([UUID]) -> Void) {
        self.store = store
        self.onSave = onSave
        _selectedIDs = State(initialValue: selectedIDs)
    }

    private var availableTasks: [TaskNode] {
        store.tasks.filter { $0.deletedAt == nil && $0.status != .archived }
    }

    private var pinnedTasks: [TaskNode] {
        selectedIDs.compactMap { store.task(for: $0) }
            .filter { $0.deletedAt == nil && $0.status != .archived }
    }

    private func isPinned(_ task: TaskNode) -> Bool {
        selectedIDs.contains(task.id)
    }

    private func togglePinned(_ task: TaskNode) {
        if let index = selectedIDs.firstIndex(of: task.id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(task.id)
        }
    }

    private func cleanedPinnedIDs() -> [UUID] {
        selectedIDs.filter { id in
            guard let task = store.task(for: id) else { return false }
            return task.deletedAt == nil && task.status != .archived
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if pinnedTasks.isEmpty {
                        Label(AppStrings.localized("quickStart.auto"), systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(pinnedTasks.enumerated()), id: \.element.id) { index, task in
                            QuickStartPinnedTaskRow(task: task, path: store.path(for: task), order: index + 1)
                        }
                        .onDelete { offsets in
                            selectedIDs.remove(atOffsets: offsets)
                        }
                    }

                    if !selectedIDs.isEmpty {
                        Button(role: .destructive) {
                            selectedIDs.removeAll()
                        } label: {
                            Label(AppStrings.localized("quickStart.clearPinned"), systemImage: "xmark.circle")
                        }
                    }
                } header: {
                    Text(String(format: AppStrings.localized("quickStart.pinnedHeader"), pinnedTasks.count))
                } footer: {
                    Text(.app("quickStart.pinnedFooter"))
                }

                Section(AppStrings.localized("quickStart.allTasks")) {
                    ForEach(availableTasks, id: \.id) { task in
                        let pinned = isPinned(task)
                        Button {
                            togglePinned(task)
                        } label: {
                            QuickStartSelectableTaskRow(
                                task: task,
                                path: store.path(for: task),
                                isPinned: pinned,
                                order: selectedIDs.firstIndex(of: task.id).map { $0 + 1 },
                                isDisabled: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle(AppStrings.localized("quickStart.edit"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        onSave(cleanedPinnedIDs())
                        dismiss()
                    }
                }
            }
        }
        .platformSheetFrame(width: 420, height: 520)
    }
}

private struct QuickStartPinnedTaskRow: View {
    let task: TaskNode
    let path: String
    let order: Int

    var body: some View {
        HStack(spacing: 12) {
            TaskIcon(task: task, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .foregroundStyle(.primary)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("#\(order)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct QuickStartSelectableTaskRow: View {
    let task: TaskNode
    let path: String
    let isPinned: Bool
    let order: Int?
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            TaskIcon(task: task, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .foregroundStyle(isDisabled ? .secondary : .primary)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let order {
                Text("#\(order)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Image(systemName: isPinned ? "checkmark.circle.fill" : "plus.circle")
                .foregroundStyle(isPinned ? .blue : .secondary)
        }
        .contentShape(Rectangle())
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}
