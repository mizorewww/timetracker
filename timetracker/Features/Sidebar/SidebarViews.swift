import SwiftUI

enum SidebarSelection: Hashable {
    case destination(TimeTrackerStore.DesktopDestination)
    case task(UUID)
}

struct SidebarView: View {
    let store: TimeTrackerStore
    let onNavigate: () -> Void
    @State private var selection: SidebarSelection?
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
        List(selection: $selection) {
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
        .onAppear(perform: syncSelectionFromStore)
        .onChange(of: selection) { _, newValue in
            guard let newValue, newValue != selectionFromStore else { return }
            switch newValue {
            case let .destination(destination):
                store.closeTaskDetailNavigation()
                store.desktopDestination = destination
            case let .task(taskID):
                store.openTaskDetail(taskID)
            }
            onNavigate()
        }
        .onChange(of: store.desktopDestination) { _, _ in syncSelectionFromStore() }
        .onChange(of: store.selectedTaskID) { _, _ in syncSelectionFromStore() }
        .onChange(of: store.desktopTaskDetailID) { _, _ in syncSelectionFromStore() }
        .onChange(of: store.tasks.map(\.id)) { _, _ in syncSelectionFromStore() }
    }

    private func syncSelectionFromStore() {
        if let desktopTaskDetailID = store.desktopTaskDetailID,
           store.task(for: desktopTaskDetailID) != nil {
            for ancestorID in store.ancestorTaskIDs(for: desktopTaskDetailID) {
                expansionState.expand(ancestorID)
            }
        }
        let updatedSelection = selectionFromStore
        guard selection != updatedSelection else { return }
        selection = updatedSelection
    }

    private var selectionFromStore: SidebarSelection {
        if let desktopTaskDetailID = store.desktopTaskDetailID,
           store.task(for: desktopTaskDetailID) != nil {
            return .task(desktopTaskDetailID)
        }
        return .destination(store.desktopDestination)
    }

    private func count(for destination: TimeTrackerStore.DesktopDestination) -> Int? {
        switch destination {
        case .today: store.activeSegments.count
        case .inbox: store.openInboxItems.count
        case .tasks: store.tasks.lazy.filter(store.isTaskVisible).count
        case .pomodoro: store.completedPomodoroCount
        case .analytics, .settings: nil
        }
    }
}
