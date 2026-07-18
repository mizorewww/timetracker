import SwiftUI

private struct TodayTaskNavigationDestinationModifier: ViewModifier {
    let store: TimeTrackerStore
    @Binding var route: TasksRoute?

    private var routedTaskIsValid: Bool {
        guard let taskID = route?.taskID else { return true }
        return store.isTaskDetailRouteValid(taskID)
    }

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: $route) { route in
                TaskDetailView(
                    store: store,
                    taskID: route.taskID,
                    startsEditing: route.startsEditing,
                    returnDestination: .today
                )
            }
            .onAppear(perform: clearInvalidRoute)
            .onChange(of: routedTaskIsValid) { _, _ in
                clearInvalidRoute()
            }
    }

    private func clearInvalidRoute() {
        guard routedTaskIsValid == false else { return }
        route = nil
    }
}

extension View {
    func todayTaskNavigationDestination(
        store: TimeTrackerStore,
        route: Binding<TasksRoute?>
    ) -> some View {
        modifier(
            TodayTaskNavigationDestinationModifier(
                store: store,
                route: route
            )
        )
    }
}
