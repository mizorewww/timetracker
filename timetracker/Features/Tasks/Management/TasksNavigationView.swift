import SwiftUI

struct TasksNavigationView: View {
    let store: TimeTrackerStore

    var body: some View {
        @Bindable var bindableStore = store
        NavigationStack {
            TasksView(store: store)
                .navigationDestination(item: $bindableStore.tasksRoute) { route in
                    TaskDetailView(store: store, taskID: route.taskID)
                }
        }
    }
}
