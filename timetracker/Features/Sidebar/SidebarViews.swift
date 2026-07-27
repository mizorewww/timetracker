import SwiftUI

enum SidebarSelection: Hashable {
    case destination(TimeTrackerStore.DesktopDestination)
    case task(UUID)
}

struct SidebarView: View {
    let store: TimeTrackerStore
    let onNavigate: () -> Void
    @State private var expansionState = TaskExpansionState()
    @State private var categoryExpansionState = TaskCategoryExpansionState()

    init(store: TimeTrackerStore, onNavigate: @escaping () -> Void = {}) {
        self.store = store
        self.onNavigate = onNavigate
    }

    private var destinations: [TimeTrackerStore.DesktopDestination] {
        #if os(macOS)
        TimeTrackerStore.DesktopDestination.allCases.filter { $0 != .settings }
        #else
        TimeTrackerStore.DesktopDestination.allCases
        #endif
    }

    var body: some View {
        List(selection: selectionBinding) {
            Section {
                ForEach(destinations) { destination in
                    SidebarDestinationLabel(destination: destination, count: count(for: destination))
                        .tag(SidebarSelection.destination(destination))
                        .accessibilityIdentifier("sidebar.\(destination.rawValue)")
                }
            }

            ForEach(
                store.taskTreeSections(
                    expandedTaskIDs: expansionState.expandedTaskIDs
                )
            ) { section in
                sidebarCategorySection(section)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppStrings.localized("app.name"))
        .onAppear(perform: expandAncestorsForCurrentTask)
        .onChange(of: store.tasksRoute) { _, _ in expandAncestorsForCurrentTask() }
        .onChange(of: store.taskTreeReadIndexRevision) { _, _ in
            expandAncestorsForCurrentTask()
        }
    }

    @ViewBuilder
    private func sidebarCategorySection(
        _ section: TaskTreeVisibleSectionModel
    ) -> some View {
        if section.rows.isEmpty {
            Section {
                sidebarTaskRows(in: section)
            } header: {
                sidebarCategoryHeader(section)
            }
        } else {
            Section(
                isExpanded: categoryExpansionBinding(for: section.id)
            ) {
                sidebarTaskRows(in: section)
            } header: {
                sidebarCategoryHeader(section)
            }
        }
    }

    private func sidebarTaskRows(
        in section: TaskTreeVisibleSectionModel
    ) -> some View {
        ForEach(section.rows) { row in
            SidebarTaskTreeRowContainer(
                store: store,
                row: row,
                expansionState: $expansionState
            )
            .tag(SidebarSelection.task(row.taskID))
        }
    }

    private func sidebarCategoryHeader(
        _ section: TaskTreeVisibleSectionModel
    ) -> some View {
        TaskCategorySectionHeader(
            section: section,
            style: .sidebar,
            showsBottomDivider: true
        )
        .accessibilityIdentifier(
            "sidebar.category.disclosure.\(section.id)"
        )
    }

    private func categoryExpansionBinding(
        for sectionID: String
    ) -> Binding<Bool> {
        Binding {
            categoryExpansionState.isExpanded(sectionID)
        } set: { isExpanded in
            categoryExpansionState.setExpanded(
                isExpanded,
                for: sectionID
            )
        }
    }

    private var selectionBinding: Binding<SidebarSelection?> {
        Binding {
            selectionFromStore
        } set: { newValue in
            guard let newValue, newValue != selectionFromStore else { return }
            store.taskDetailNavigationGuard.requestNavigation(
                dismissingActiveDetail: true
            ) {
                switch newValue {
                case let .destination(destination):
                    store.closeTaskDetailNavigation()
                    store.desktopDestination = destination
                case let .task(taskID):
                    store.openTaskDetail(taskID)
                }
                onNavigate()
            }
        }
    }

    private var selectionFromStore: SidebarSelection {
        if let taskID = store.tasksRoute?.taskID,
           store.isTaskDetailRouteValid(taskID)
        {
            return .task(taskID)
        }
        return .destination(store.desktopDestination)
    }

    private func expandAncestorsForCurrentTask() {
        guard let taskID = store.tasksRoute?.taskID,
              store.isTaskDetailRouteValid(taskID) else { return }
        for ancestorID in store.ancestorTaskIDs(for: taskID) {
            expansionState.expand(ancestorID)
        }
        let sections = store.taskTreeSections(
            expandedTaskIDs: expansionState.expandedTaskIDs
        )
        if let section = sections.first(where: { section in
            section.rows.contains { $0.taskID == taskID }
        }) {
            categoryExpansionState.expand(section.id)
        }
    }

    private func count(for destination: TimeTrackerStore.DesktopDestination) -> Int? {
        switch destination {
        case .today: store.activeSegments.count
        case .inbox: store.openInboxItems.count
        case .tasks: store.visibleTaskCount
        case .pomodoro: store.completedPomodoroCount
        case .analytics, .settings: nil
        }
    }
}
