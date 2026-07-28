import SwiftUI

struct TasksNavigationView: View {
    let store: TimeTrackerStore
    @Environment(\.layoutShell) private var layoutShell
    @State private var path: [TasksRoute] = []

    var body: some View {
        if layoutShell == .regular {
            regularContent
        } else {
            compactContent
        }
    }

    private var regularContent: some View {
        NavigationStack {
            if let route = store.tasksRoute {
                taskDetail(for: route)
            } else {
                TasksView(store: store)
            }
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
