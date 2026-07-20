import SwiftUI

struct TasksNavigationView: View {
    let store: TimeTrackerStore

    var body: some View {
        NavigationStack {
            TasksView(store: store)
                .navigationDestination(item: protectedRoute) { route in
                    TaskDetailView(
                        store: store,
                        taskID: route.taskID,
                        dismissDetail: store.closeTaskDetailNavigation,
                        replaceDetail: store.openTaskDetail
                    )
                    .id(route.taskID)
                }
        }
    }

    private var protectedRoute: Binding<TasksRoute?> {
        Binding(
            get: { store.tasksRoute },
            set: { proposedRoute in
                guard proposedRoute == nil, store.tasksRoute != nil else {
                    store.tasksRoute = proposedRoute
                    return
                }
                store.taskDetailNavigationGuard.requestNavigation(
                    dismissingActiveDetail: true
                ) {}
            }
        )
    }
}
