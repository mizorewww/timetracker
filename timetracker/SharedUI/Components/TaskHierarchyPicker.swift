import SwiftUI

enum TaskHierarchyPickerSelectionContext: Equatable {
    case pomodoro
    case inboxDestination
}

enum TaskHierarchyPickerMode: Equatable {
    case timer
    case singleSelection(
        selectedTaskID: UUID?,
        context: TaskHierarchyPickerSelectionContext = .pomodoro
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
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

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
            searchText: searchText
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppStrings.cancel, action: onDismiss)
            }
        }
        .onAppear(perform: revealSelectedTask)
        .onChange(of: selectedTaskID) { _, _ in revealSelectedTask() }
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
                    if case .timer = mode, section.id == sections.last?.id {
                        Text(store.timerPickerMode.footer)
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
    private func sectionHeader(
        _ section: TaskHierarchyProjection.Section
    ) -> some View {
        switch section.kind {
        case .hierarchy:
            TaskCategorySectionHeader(
                section: section.taskTreeSectionModel,
                compact: true
            )
        case .searchResults:
            Text(section.title)
        }
    }
}
