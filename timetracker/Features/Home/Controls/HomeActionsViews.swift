import SwiftUI

struct TodayTimerAction: View {
    let store: TimeTrackerStore
    @State private var isTaskPickerPresented = false

    var body: some View {
        startButton
        .sheet(isPresented: $isTaskPickerPresented) {
            TaskStartPickerSheet(store: store) {
                isTaskPickerPresented = false
            }
        }
    }

    @ViewBuilder
    private var startButton: some View {
        if store.activeSegments.isEmpty {
            startButtonContent
                .buttonStyle(.borderedProminent)
        } else {
            startButtonContent
                .buttonStyle(.bordered)
        }
    }

    private var startButtonContent: some View {
        Button {
            isTaskPickerPresented = true
        } label: {
            AppActionLabel(title: actionTitle, systemImage: actionSystemImage)
        }
        .controlSize(.large)
        .accessibilityIdentifier("home.startTimer")
    }

    private var actionTitle: String {
        guard !store.activeSegments.isEmpty else { return AppStrings.startTimer }
        return store.preferences.allowParallelTimers
            ? AppStrings.localized("home.startAnotherTimer")
            : AppStrings.localized("home.switchTimer")
    }

    private var actionSystemImage: String {
        guard !store.activeSegments.isEmpty else { return "play.fill" }
        return store.preferences.allowParallelTimers ? "plus" : "arrow.left.arrow.right"
    }
}

struct TaskStartPickerSheet: View {
    let store: TimeTrackerStore
    let onDone: () -> Void
#if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
#endif

    var body: some View {
        NavigationStack {
            TaskStartPicker(store: store, onDone: onDone)
        }
#if os(iOS)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
#else
        .frame(minWidth: 420, minHeight: 520)
#endif
    }
}

struct TaskStartPicker: View {
    let store: TimeTrackerStore
    let onDone: () -> Void
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
                ContentUnavailableView {
                    Label(
                        availableTasks.isEmpty
                            ? AppStrings.localized("tasks.empty.title")
                            : AppStrings.localized("tasks.empty.search"),
                        systemImage: availableTasks.isEmpty ? "checklist" : "magnifyingglass"
                    )
                } description: {
                    Text(
                        availableTasks.isEmpty
                            ? AppStrings.localized("tasks.empty.description")
                            : AppStrings.localized("timer.search.empty.description")
                    )
                } actions: {
                    Button {
                        createTask()
                    } label: {
                        Label(AppStrings.newTask, systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    Section {
                        ForEach(filteredTasks, id: \.id) { task in
                            let activeSegment = store.activeSegment(for: task.id)
                            Button {
                                if let activeSegment {
                                    store.stop(segment: activeSegment)
                                } else {
                                    store.startTask(task)
                                }
                                onDone()
                            } label: {
                                TaskStartPickerRow(
                                    task: task,
                                    path: store.path(for: task),
                                    isRunning: activeSegment != nil
                                )
                            }
                            .accessibilityHint(AppStrings.localized(
                                activeSegment == nil ? "timer.task.startHint" : "timer.task.stopHint"
                            ))
                        }
                    } header: {
                        Text(.app("timer.chooseTaskHeader"))
                    } footer: {
                        Text(.app("timer.chooseTaskFooter"))
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
                .scrollContentBackground(.hidden)
            }
        }
        #if os(iOS)
        .background(Color(uiColor: .systemGroupedBackground))
        #else
        .background(AppColors.background)
        #endif
        .searchable(text: $searchText, prompt: AppStrings.localized("tasks.searchPrompt"))
        .navigationTitle(AppStrings.startTimer)
        .accessibilityIdentifier("timer.taskPicker")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppStrings.cancel, action: onDone)
            }
        }
    }

    private func createTask() {
        onDone()
        Task { @MainActor in
            await Task.yield()
            store.presentNewTask()
        }
    }
}

private struct TaskStartPickerRow: View {
    let task: TaskNode
    let path: String
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 12) {
            TaskIcon(task: task, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .foregroundStyle(.primary)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isRunning {
                RunningStatusBadge()
            }
        }
    }
}
