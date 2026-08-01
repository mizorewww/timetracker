import SwiftUI

struct TasksNavigationView: View {
    let store: TimeTrackerStore
    let ownsRegularNavigationStack: Bool
    @Environment(\.layoutShell) private var layoutShell
    @State private var path: [TasksRoute] = []

    init(
        store: TimeTrackerStore,
        ownsRegularNavigationStack: Bool = true
    ) {
        self.store = store
        self.ownsRegularNavigationStack = ownsRegularNavigationStack
    }

    var body: some View {
        if layoutShell == .regular {
            regularContent
        } else {
            compactContent
        }
    }

    @ViewBuilder
    private var regularContent: some View {
        if ownsRegularNavigationStack {
            NavigationStack {
                regularDestination
            }
        } else {
            regularDestination
        }
    }

    @ViewBuilder
    private var regularDestination: some View {
        if let route = store.tasksRoute {
            taskDetail(for: route)
        } else {
            TasksView(store: store)
        }
    }

    private var compactContent: some View {
        NavigationStack(path: $path) {
            TasksView(store: store)
                .navigationDestination(for: TasksRoute.self) { route in
                    taskDetail(for: route)
                }
        }
        .onAppear {
            synchronizePath(with: store.tasksRoute)
        }
        .onChange(of: store.tasksRoute) { _, route in
            synchronizePath(with: route)
        }
        .onChange(of: path) { _, routes in
            handlePathChange(routes)
        }
    }

    private func taskDetail(for route: TasksRoute) -> some View {
        TaskDetailView(
            store: store,
            taskID: route.taskID,
            dismissDetail: {
                store.closeTaskDetailNavigation(
                    ifMatching: route.taskID
                )
            },
            replaceDetail: store.openTaskDetail
        )
        .id(route.taskID)
    }

    private func synchronizePath(with route: TasksRoute?) {
        let expectedPath = route.map { [$0] } ?? []
        guard path != expectedPath else { return }
        path = expectedPath
    }

    private func handlePathChange(_ routes: [TasksRoute]) {
        if let route = routes.last {
            guard store.tasksRoute != route else { return }
            store.tasksRoute = route
            return
        }
        guard let activeRoute = store.tasksRoute else { return }
        store.taskDetailNavigationGuard.requestNavigation(
            dismissingActiveDetail: true
        ) {}
        if store.tasksRoute == activeRoute {
            synchronizePath(with: activeRoute)
        }
    }
}
