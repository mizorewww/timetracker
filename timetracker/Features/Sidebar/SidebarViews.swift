import SwiftUI

enum SidebarSelection: Hashable {
    case destination(TimeTrackerStore.DesktopDestination)
    case task(UUID)

    @MainActor
    func navigate(
        in store: TimeTrackerStore,
        onNavigate: @escaping () -> Void = {}
    ) {
        switch self {
        case let .destination(destination):
            store.closeTaskDetailNavigation()
            store.desktopDestination = destination
        case let .task(taskID):
            store.openTaskDetail(taskID)
        }
        onNavigate()
    }
}

struct SidebarView: View {
    let store: TimeTrackerStore
    let onNavigate: () -> Void
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @State private var expansionState = TaskExpansionState()
    @State private var categoryExpansionState = TaskCategoryExpansionState()
    /// The day the Focus badge counts; advanced when the calendar day changes.
    @State private var today = Date()

    init(store: TimeTrackerStore, onNavigate: @escaping () -> Void = {}) {
        self.store = store
        self.onNavigate = onNavigate
    }

    var body: some View {
        List(selection: selectionBinding) {
            Section {
                ForEach(TimeTrackerStore.DesktopDestination.allCases) { destination in
                    SidebarDestinationLabel(
                        destination: destination,
                        count: count(for: destination),
                        isSelected: selectionFromStore == .destination(destination)
                    )
                    .tag(SidebarSelection.destination(destination))
                    .accessibilityIdentifier("sidebar.\(destination.rawValue)")
                }
                #if !os(macOS)
                // macOS opens its Settings scene from the app menu instead.
                Button {
                    presentationRouter.present(.settings)
                } label: {
                    Label {
                        Text(AppStrings.settings)
                    } icon: {
                        SidebarTile(visual: .settings)
                    }
                }
                .accessibilityIdentifier("sidebar.Settings")
                #endif
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
        .onSystemClockChange { today = Date() }
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
            newValue.navigate(in: store, onNavigate: onNavigate)
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
        case .inbox: store.openInboxItemCount
        case .tasks: store.visibleTaskCount
        case .pomodoro: store.completedPomodoroCount(on: today)
        case .analytics: nil
        }
    }
}
