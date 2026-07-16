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
        store.timerPickerMode.title
    }

    private var actionSystemImage: String {
        store.timerPickerMode.systemImage
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

    private var filteredItems: [TaskStartPickerItem] {
        filteredTasks.map { task in
            TaskStartPickerItem(
                task: task,
                fullPath: store.path(for: task),
                parentPath: store.parentPath(for: task),
                activeSegment: store.activeSegment(for: task.id),
                command: store.timerPickerSelectionCommand(for: task)
            )
        }
    }

    var body: some View {
        let items = filteredItems
        let runningItems = items.filter { $0.command == .alreadyRunning }
        let selectableItems = items.filter { $0.command != .alreadyRunning }

        Group {
            if items.isEmpty {
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
                    if runningItems.isEmpty == false {
                        Section {
                            ForEach(runningItems) { item in
                                TaskStartPickerRunningRow(
                                    task: item.task,
                                    fullPath: item.fullPath,
                                    parentPath: item.parentPath,
                                    onStop: {
                                        guard let activeSegment = item.activeSegment else { return }
                                        store.stop(segment: activeSegment)
                                    }
                                )
                                .accessibilityIdentifier(
                                    "timer.taskPicker.running.\(item.id.uuidString)"
                                )
                            }
                        } header: {
                            Text(.app("timer.picker.runningHeader"))
                        }
                    }

                    if selectableItems.isEmpty == false {
                        Section {
                            ForEach(selectableItems) { item in
                                Button {
                                    let outcome = store.performTimerPickerSelection(item.task)
                                    if outcome.shouldDismissPicker {
                                        onDone()
                                    }
                                } label: {
                                    TaskStartPickerActionRow(
                                        task: item.task,
                                        parentPath: item.parentPath,
                                        command: item.command
                                    )
                                }
                                .accessibilityLabel(
                                    item.command.accessibilityLabel(for: item.task.title)
                                )
                                .accessibilityValue(item.fullPath)
                                .accessibilityHint(item.command.accessibilityHint)
                                .accessibilityIdentifier(
                                    "timer.taskPicker.select.\(item.id.uuidString)"
                                )
                            }
                        } header: {
                            Text(store.timerPickerMode.sectionHeader)
                        } footer: {
                            Text(store.timerPickerMode.footer)
                        }
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
        #else
        .background(AppColors.background)
        #endif
        #if os(iOS)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: AppStrings.localized("tasks.searchPrompt")
        )
        #else
        .searchable(text: $searchText, prompt: AppStrings.localized("tasks.searchPrompt"))
        #endif
        .navigationTitle(store.timerPickerMode.title)
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
