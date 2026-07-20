import SwiftUI

enum SidebarSelection: Hashable {
    case destination(TimeTrackerStore.DesktopDestination)
    case task(UUID)
}

struct SidebarView: View {
    let store: TimeTrackerStore
    let onNavigate: () -> Void
    @State private var expansionState = TaskExpansionState()

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

            ForEach(store.taskTreeSections(expandedTaskIDs: expansionState.expandedTaskIDs)) { section in
                Section {
                    ForEach(section.rows) { row in
                        SidebarTaskTreeRowContainer(
                            store: store,
                            row: row,
                            expansionState: $expansionState
                        )
                        .tag(SidebarSelection.task(row.taskID))
                    }
                } header: {
                    TaskCategorySectionHeader(
                        section: section,
                        compact: true,
                        showsBottomDivider: true
                    )
                }
            }
        }
        .navigationTitle(AppStrings.localized("app.name"))
        .onAppear(perform: expandAncestorsForCurrentTask)
        .onChange(of: store.tasksRoute) { _, _ in expandAncestorsForCurrentTask() }
        .onChange(of: store.taskTreeReadIndexRevision) { _, _ in
            expandAncestorsForCurrentTask()
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
           store.isTaskDetailRouteValid(taskID) {
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
