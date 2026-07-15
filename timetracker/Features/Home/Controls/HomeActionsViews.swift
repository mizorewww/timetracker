import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ActionStack: View {
    let store: TimeTrackerStore
    var buttonHeight: CGFloat?
    var spacing: CGFloat = 12
    @State private var isTaskPickerPresented = false
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompactPhone: Bool {
        SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass).isCompactPhone
    }
#endif

    var body: some View {
        actionLayout
        .sheet(isPresented: $isTaskPickerPresented) {
            taskPicker
        }
    }

    @ViewBuilder
    private var taskPicker: some View {
        #if os(iOS)
        NavigationStack {
            TaskStartPicker(store: store) {
                isTaskPickerPresented = false
            }
        }
        .presentationDetents([.medium, .large])
        #else
        NavigationStack {
            TaskStartPicker(store: store) {
                isTaskPickerPresented = false
            }
        }
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    @ViewBuilder
    private var actionLayout: some View {
#if os(iOS)
        if isCompactPhone {
            HStack(spacing: spacing) {
                startButton
                    .frame(maxWidth: .infinity)
                newTaskButton
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: spacing) {
                startButton
                newTaskButton
            }
        }
#else
        VStack(spacing: spacing) {
            startButton
            newTaskButton
        }
#endif
    }

    private var startButton: some View {
        Button {
            isTaskPickerPresented = true
        } label: {
            AppActionLabel(title: AppStrings.startTimer, systemImage: "play.fill", fixedHeight: buttonHeight)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .accessibilityIdentifier("home.startTimer")
    }

    private var newTaskButton: some View {
        Button {
            store.presentNewTask()
        } label: {
            AppActionLabel(title: AppStrings.newTask, systemImage: "plus", fixedHeight: buttonHeight)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityIdentifier("home.newTask")
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
