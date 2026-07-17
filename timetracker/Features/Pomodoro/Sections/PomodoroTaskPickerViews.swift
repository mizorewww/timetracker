import SwiftUI

struct PomodoroFocusTaskPickerSheet: View {
    let store: TimeTrackerStore
    let selectedTaskID: UUID?
    let onSelect: (UUID) -> Void
    let onCancel: () -> Void
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    var body: some View {
        NavigationStack {
            PomodoroFocusTaskPicker(
                store: store,
                selectedTaskID: selectedTaskID,
                onSelect: onSelect,
                onCancel: onCancel
            )
        }
        #if os(iOS)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        #else
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }
}

struct PomodoroFocusTaskPicker: View {
    let store: TimeTrackerStore
    let selectedTaskID: UUID?
    let onSelect: (UUID) -> Void
    let onCancel: () -> Void
    @State private var searchText = ""

    private var availableTasks: [TaskNode] {
        store.tasks.filter(store.isTaskAvailableForTracking)
    }

    private var filteredTasks: [TaskNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return availableTasks }
        return availableTasks.filter { task in
            task.title.localizedCaseInsensitiveContains(query) ||
                store.path(for: task).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if filteredTasks.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredTasks, id: \.id) { task in
                        Button {
                            onSelect(task.id)
                        } label: {
                            PomodoroFocusTaskPickerRow(
                                task: task,
                                parentPath: store.parentPath(for: task),
                                isSelected: task.id == selectedTaskID
                            )
                        }
                        .accessibilityIdentifier("pomodoro.taskPicker.select.\(task.id.uuidString)")
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                .listSectionSpacing(18)
                #else
                .listStyle(.inset)
                #endif
                .scrollContentBackground(.hidden)
            }
        }
        #if os(iOS)
        .background(Color(uiColor: .systemGroupedBackground))
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: AppStrings.localized("tasks.searchPrompt")
        )
        #else
        .background(AppColors.background)
        .searchable(text: $searchText, prompt: AppStrings.localized("tasks.searchPrompt"))
        #endif
        .navigationTitle(AppStrings.localized("pomodoro.chooseTask"))
        .accessibilityIdentifier("pomodoro.taskPicker")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppStrings.cancel, action: onCancel)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                availableTasks.isEmpty
                    ? AppStrings.localized("pomodoro.noTasks.title")
                    : AppStrings.localized("tasks.empty.search"),
                systemImage: availableTasks.isEmpty ? "checklist" : "magnifyingglass"
            )
        } description: {
            Text(
                availableTasks.isEmpty
                    ? AppStrings.localized("pomodoro.noTasks.description")
                    : AppStrings.localized("timer.search.empty.description")
            )
        } actions: {
            if searchText.isEmpty == false {
                Button(AppStrings.localized("tasks.search.clear")) {
                    searchText = ""
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct PomodoroFocusTaskPickerRow: View {
    let task: TaskNode
    let parentPath: String?
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TaskIcon(task: task, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                if let parentPath, parentPath.isEmpty == false {
                    Text(parentPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}
