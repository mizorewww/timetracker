import SwiftUI

enum TaskHierarchyPickerSelectionContext: Equatable {
    case pomodoro
    case inboxChildTaskParent
    case inboxChecklistTarget
    case todayHeatmap
}

enum TaskHierarchyPickerMode: Equatable {
    case timer
    case singleSelection(
        selectedTaskID: UUID?,
        context: TaskHierarchyPickerSelectionContext = .pomodoro
    )
    case multipleSelection(
        selectedTaskIDs: Set<UUID>,
        context: TaskHierarchyPickerSelectionContext = .todayHeatmap,
        maximumSelectionCount: Int? = nil
    )
}

struct TaskHierarchyPicker: View {
    let store: TimeTrackerStore
    let mode: TaskHierarchyPickerMode
    let onDismiss: () -> Void
    let onSelect: (UUID) -> Void
    let onCreateTask: (() -> Void)?

    @State var searchText = ""
    @State var expandedTaskIDs: Set<UUID> = []

    init(
        store: TimeTrackerStore,
        mode: TaskHierarchyPickerMode,
        onDismiss: @escaping () -> Void,
        onSelect: @escaping (UUID) -> Void = { _ in },
        onCreateTask: (() -> Void)? = nil
    ) {
        self.store = store
        self.mode = mode
        self.onDismiss = onDismiss
        self.onSelect = onSelect
        self.onCreateTask = onCreateTask
    }

    var body: some View {
        let projection = TaskHierarchyProjection(
            store: store,
            expandedTaskIDs: expandedTaskIDs,
            searchText: searchText,
            availableTaskIDs: mode.selectionEligibleTaskIDs(in: store)
        )
        let sections = displayedSections(in: projection)

        Group {
            if hasContent(projection: projection, sections: sections) {
                pickerList(projection: projection, sections: sections)
            } else {
                emptyState(projection)
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
            .navigationTitle(navigationTitle)
            .accessibilityIdentifier(accessibilityIdentifier)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .onAppear {
                revealSelectedTasks(selectedTaskIDs)
            }
            .onChange(of: selectedTaskIDs) { previous, current in
                revealSelectedTasks(current.subtracting(previous))
            }
    }

    private func pickerList(
        projection: TaskHierarchyProjection,
        sections: [TaskHierarchyProjection.Section]
    ) -> some View {
        List {
            if case .timer = mode, projection.runningItems.isEmpty == false {
                Section {
                    ForEach(projection.runningItems) { item in
                        runningRow(item)
                    }
                } header: {
                    Text(.app("timer.picker.runningHeader"))
                        .accessibilityIdentifier("timer.taskPicker.runningHeader")
                }
            }

            ForEach(sections) { section in
                let items = displayedItems(in: section)
                Section {
                    ForEach(items) { item in
                        hierarchyRow(item, sectionKind: section.kind)
                    }
                } header: {
                    sectionHeader(section)
                } footer: {
                    if section.id == sections.last?.id {
                        pickerFooter
                    }
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

    @ViewBuilder
    private var pickerFooter: some View {
        switch mode {
        case .timer:
            Text(store.timerPickerMode.footer)
        case .singleSelection:
            EmptyView()
        case let .multipleSelection(selectedTaskIDs, _, maximumSelectionCount):
            if let maximumSelectionCount {
                Text(
                    String(
                        format: AppStrings.localized("taskPicker.selection.countFormat"),
                        selectedTaskIDs.count,
                        maximumSelectionCount
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(
        _ section: TaskHierarchyProjection.Section
    ) -> some View {
        switch section.kind {
        case .hierarchy:
            TaskCategorySectionHeader(
                section: section.taskTreeSectionModel,
                style: .compact
            )
        case .searchResults:
            Text(section.title)
        }
    }
}
